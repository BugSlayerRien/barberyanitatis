<?php
// Face scan capture storage and customer preview URLs for appointments.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/replicate_helper.php';
require_once __DIR__ . '/ai_gemini_image_helper.php';
require_once __DIR__ . '/ai_tryon_provider.php';
require_once __DIR__ . '/ai_service_client.php';
require_once __DIR__ . '/face_scan_attach.php';
require_once __DIR__ . '/customer_auth.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

function ensure_face_scan_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS face_scan_sessions (
            scan_session_id VARCHAR(80) PRIMARY KEY,
            user_id BIGINT,
            face_shape VARCHAR(50),
            hair_texture TEXT,
            hair_density TEXT,
            consent_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_face_scan_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL
        )"
    );

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS face_scan_captures (
            capture_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            scan_session_id VARCHAR(80) NOT NULL,
            angle VARCHAR(10) NOT NULL,
            file_path TEXT NOT NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_face_capture_session FOREIGN KEY (scan_session_id) REFERENCES face_scan_sessions(scan_session_id) ON DELETE CASCADE,
            CONSTRAINT uq_face_capture_angle UNIQUE (scan_session_id, angle)
        )"
    );

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS face_scan_previews (
            preview_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            scan_session_id VARCHAR(80) NOT NULL,
            variant_id BIGINT,
            front_url TEXT,
            left_url TEXT,
            right_url TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_face_preview_session FOREIGN KEY (scan_session_id) REFERENCES face_scan_sessions(scan_session_id) ON DELETE CASCADE
        )"
    );

    $pdo->exec(
        'ALTER TABLE appointment_details
         ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_right_url TEXT'
    );

    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS scan_session_id VARCHAR(80)'
    );

    $pdo->exec('ALTER TABLE face_scan_sessions ADD COLUMN IF NOT EXISTS hair_length_level INT');
    $pdo->exec('ALTER TABLE face_scan_sessions ADD COLUMN IF NOT EXISTS hair_length_label TEXT');
    $pdo->exec('ALTER TABLE face_scan_sessions ADD COLUMN IF NOT EXISTS hair_color_label TEXT');
    $pdo->exec('ALTER TABLE face_scan_sessions ADD COLUMN IF NOT EXISTS no_hair_detected BOOLEAN DEFAULT FALSE');

    // Marks previews made from captures that have since been overwritten (e.g. the user
    // retook their photos in the same session). Stale previews are never served from
    // cache or attached to a booking, but they still count toward the generation quota —
    // otherwise retaking a photo would be a free way to reset the 2-style limit.
    $pdo->exec('ALTER TABLE face_scan_previews ADD COLUMN IF NOT EXISTS is_stale BOOLEAN NOT NULL DEFAULT FALSE');
}

/**
 * Mark any previews generated from this session's previous captures as stale so a new
 * physical scan (or a retake within the same session) can never surface an old try-on
 * image as if it came from the current face.
 */
function invalidate_stale_previews_for_session(PDO $pdo, string $scanSessionId): void
{
    $pdo->prepare(
        'UPDATE face_scan_previews
         SET is_stale = TRUE
         WHERE scan_session_id = :scan_session_id
           AND is_stale = FALSE'
    )->execute([':scan_session_id' => $scanSessionId]);
}

function face_scan_upload_root(): string
{
    return api_project_root() . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'face_scans';
}

function ensure_scan_session_row(
    PDO $pdo,
    string $scanSessionId,
    ?int $userId = null,
    ?string $faceShape = null,
    ?string $hairTexture = null
): void {
    $stmt = $pdo->prepare(
        'INSERT INTO face_scan_sessions (scan_session_id, user_id, face_shape, hair_texture, consent_at)
         VALUES (:scan_session_id, :user_id, :face_shape, :hair_texture, :consent_at)
         ON CONFLICT (scan_session_id) DO UPDATE
         SET user_id = COALESCE(EXCLUDED.user_id, face_scan_sessions.user_id),
             face_shape = COALESCE(EXCLUDED.face_shape, face_scan_sessions.face_shape),
             hair_texture = COALESCE(EXCLUDED.hair_texture, face_scan_sessions.hair_texture)'
    );
    $stmt->execute([
        ':scan_session_id' => $scanSessionId,
        ':user_id' => $userId,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':consent_at' => date('c'),
    ]);
}

/** @return array{front:?string,left:?string,right:?string} */
function capture_paths_for_session(PDO $pdo, string $scanSessionId): array
{
    $stmt = $pdo->prepare(
        'SELECT angle, file_path FROM face_scan_captures WHERE scan_session_id = :scan_session_id'
    );
    $stmt->execute([':scan_session_id' => $scanSessionId]);
    $paths = ['front' => null, 'left' => null, 'right' => null];
    foreach ($stmt->fetchAll() as $row) {
        $angle = (string)($row['angle'] ?? '');
        if (array_key_exists($angle, $paths)) {
            $paths[$angle] = (string)$row['file_path'];
        }
    }

    return $paths;
}

function is_valid_jpeg_bytes(string $bytes): bool
{
    if (strlen($bytes) < 4) {
        return false;
    }
    return ord($bytes[0]) === 0xFF && ord($bytes[1]) === 0xD8 && ord($bytes[2]) === 0xFF;
}

function decode_base64_image(string $base64): ?string
{
    $raw = $base64;
    if (str_contains($raw, ',')) {
        $raw = substr($raw, (int)strpos($raw, ',') + 1);
    }
    $decoded = base64_decode($raw, true);
    if ($decoded === false || $decoded === '') {
        return null;
    }
    return $decoded;
}

function save_jpeg_capture(string $scanSessionId, string $angle, string $base64): string
{
    $bytes = decode_base64_image($base64);
    if ($bytes === null || !is_valid_jpeg_bytes($bytes)) {
        throw new InvalidArgumentException("Invalid JPEG for angle {$angle}");
    }

    $session = preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId);
    $relative = 'uploads/face_scans/' . $session . '/' . $angle . '.jpg';
    storage_put_bytes($relative, $bytes, 'image/jpeg');

    return $relative;
}

function save_preview_bytes(string $scanSessionId, int $variantId, string $angle, string $bytes): string
{
    if ($bytes === '') {
        throw new InvalidArgumentException("Empty preview bytes for {$angle}");
    }

    if (function_exists('imagecreatefromstring') && function_exists('imagejpeg')) {
        $image = @imagecreatefromstring($bytes);
        if ($image !== false) {
            ob_start();
            imagejpeg($image, null, 92);
            $jpeg = ob_get_clean();
            imagedestroy($image);
            if (is_string($jpeg) && $jpeg !== '') {
                $bytes = $jpeg;
            }
        }
    }

    $session = preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId);
    $variantPart = $variantId > 0 ? ('v' . $variantId . '_') : '';
    $filename = $variantPart . $angle . '.jpg';
    $relative = 'uploads/face_scans/' . $session . '/previews/' . $filename;
    storage_put_bytes($relative, $bytes, 'image/jpeg');

    return $relative;
}

function save_jpeg_preview(string $scanSessionId, string $angle, string $base64): string
{
    $bytes = decode_base64_image($base64);
    if ($bytes === null) {
        throw new InvalidArgumentException("Invalid image for preview {$angle}");
    }
    if (!is_valid_jpeg_bytes($bytes)) {
        // Allow PNG previews converted client-side — accept PNG signature too.
        $isPng = strlen($bytes) >= 8
            && ord($bytes[0]) === 0x89
            && ord($bytes[1]) === 0x50;
        if (!$isPng) {
            throw new InvalidArgumentException("Invalid preview image for {$angle}");
        }
    }

    $session = preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId);
    $ext = is_valid_jpeg_bytes($bytes) ? 'jpg' : 'png';
    $filename = $angle . '.' . $ext;
    $relative = 'uploads/face_scans/' . $session . '/previews/' . $filename;
    $mime = $ext === 'png' ? 'image/png' : 'image/jpeg';
    storage_put_bytes($relative, $bytes, $mime);

    return $relative;
}

try {
    $pdo = get_db_connection();
    ensure_face_scan_tables($pdo);
    $customer = require_customer_or_guest($pdo, $input);
    $userID = $customer !== null ? (int)$customer['user_id'] : null;

    if ($action === 'uploadCaptures') {
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        if ($scanSessionId === '') {
            json_response(['error' => 'scanSessionId required'], 422);
        }
        require_scan_session_access($pdo, $scanSessionId, $userID);

        $captures = $input['captures'] ?? [];
        if (!is_array($captures)) {
            json_response(['error' => 'captures must be an object'], 422);
        }

        $required = ['front', 'right', 'left'];
        foreach ($required as $angle) {
            if (empty($captures[$angle])) {
                json_response(['error' => "Missing capture: {$angle}"], 422);
            }
        }

        $consentAt = trim((string)($input['consentAt'] ?? ''));
        $consentTs = $consentAt !== '' ? $consentAt : date('c');

        $pdo->beginTransaction();

        // New/overwritten captures mean any previously generated previews for this
        // session no longer reflect the current face — invalidate them up front.
        invalidate_stale_previews_for_session($pdo, $scanSessionId);

        $sessionStmt = $pdo->prepare(
            'INSERT INTO face_scan_sessions (scan_session_id, user_id, face_shape, hair_texture, hair_density, consent_at)
             VALUES (:scan_session_id, :user_id, :face_shape, :hair_texture, :hair_density, :consent_at)
             ON CONFLICT (scan_session_id) DO UPDATE
             SET user_id = COALESCE(EXCLUDED.user_id, face_scan_sessions.user_id),
                 face_shape = COALESCE(EXCLUDED.face_shape, face_scan_sessions.face_shape),
                 hair_texture = COALESCE(EXCLUDED.hair_texture, face_scan_sessions.hair_texture),
                 hair_density = COALESCE(EXCLUDED.hair_density, face_scan_sessions.hair_density),
                 consent_at = COALESCE(EXCLUDED.consent_at, face_scan_sessions.consent_at)'
        );
        $sessionStmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':user_id' => $userID,
            ':face_shape' => trim((string)($input['faceShape'] ?? '')) ?: null,
            ':hair_texture' => trim((string)($input['hairTexture'] ?? '')) ?: null,
            ':hair_density' => trim((string)($input['hairDensity'] ?? '')) ?: null,
            ':consent_at' => $consentTs,
        ]);

        $saved = [];
        $captureStmt = $pdo->prepare(
            'INSERT INTO face_scan_captures (scan_session_id, angle, file_path)
             VALUES (:scan_session_id, :angle, :file_path)
             ON CONFLICT (scan_session_id, angle) DO UPDATE
             SET file_path = EXCLUDED.file_path, created_at = NOW()'
        );

        foreach ($required as $angle) {
            $path = save_jpeg_capture($scanSessionId, $angle, (string)$captures[$angle]);
            $captureStmt->execute([
                ':scan_session_id' => $scanSessionId,
                ':angle' => $angle,
                ':file_path' => $path,
            ]);
            $saved[$angle] = $path;
        }

        $pdo->commit();

        json_response([
            'message' => 'Captures saved',
            'scanSessionId' => $scanSessionId,
            'captures' => $saved,
        ]);
    }

    if ($action === 'savePreviews') {
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $variantID = (int)($input['variantID'] ?? 0);
        $previews = $input['previews'] ?? [];
        if ($scanSessionId === '' || $variantID <= 0 || !is_array($previews)) {
            json_response(['error' => 'Invalid preview payload'], 422);
        }
        require_scan_session_access($pdo, $scanSessionId, $userID);

        ensure_scan_session_row(
            $pdo,
            $scanSessionId,
            $userID,
            trim((string)($input['faceShape'] ?? '')) ?: null,
            trim((string)($input['hairTexture'] ?? '')) ?: null
        );

        $front = null;
        $left = null;
        $right = null;

        $frontB64 = trim((string)($previews['front'] ?? ''));
        $leftB64 = trim((string)($previews['left'] ?? ''));
        $rightB64 = trim((string)($previews['right'] ?? ''));

        if ($frontB64 !== '') {
            $front = save_jpeg_preview($scanSessionId, 'front', $frontB64);
        }
        if ($leftB64 !== '') {
            $left = save_jpeg_preview($scanSessionId, 'left', $leftB64);
        }
        if ($rightB64 !== '') {
            $right = save_jpeg_preview($scanSessionId, 'right', $rightB64);
        }

        $captures = capture_paths_for_session($pdo, $scanSessionId);
        $front ??= $captures['front'];
        $left ??= $captures['left'];
        $right ??= $captures['right'];

        if ($front === null && $left === null && $right === null) {
            json_response(['error' => 'No preview or capture images available for this scan'], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO face_scan_previews (scan_session_id, variant_id, front_url, left_url, right_url)
             VALUES (:scan_session_id, :variant_id, :front_url, :left_url, :right_url)'
        );
        $stmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':variant_id' => $variantID,
            ':front_url' => $front,
            ':left_url' => $left,
            ':right_url' => $right,
        ]);

        json_response([
            'message' => 'Previews saved',
            'frontViewUrl' => $front,
            'sideViewUrl' => $left,
            'backViewUrl' => $right,
        ]);
    }

    if ($action === 'attachToAppointment') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $variantID = (int)($input['variantID'] ?? 0);

        if ($appointmentID <= 0 || $scanSessionId === '') {
            json_response(['error' => 'Invalid attach payload'], 422);
        }

        $customer = require_customer($pdo, $input);
        $userID = (int)$customer['user_id'];
        require_customer_owns_appointment($pdo, $userID, $appointmentID);
        require_scan_session_access($pdo, $scanSessionId, $userID);

        $result = attach_scan_previews_to_appointment(
            $pdo,
            $appointmentID,
            $scanSessionId,
            $variantID,
            [
                'frontViewUrl' => (string)($input['frontViewUrl'] ?? ''),
                'sideViewUrl' => (string)($input['sideViewUrl'] ?? ''),
                'backViewUrl' => (string)($input['backViewUrl'] ?? ''),
            ]
        );

        if (!$result['attached']) {
            json_response(['error' => 'No preview images found for this scan session'], 422);
        }

        json_response([
            'message' => 'Appointment previews attached',
            'frontViewUrl' => $result['front'],
            'sideViewUrl' => $result['left'],
            'backViewUrl' => $result['right'],
        ]);
    }

    if ($action === 'analyzeCaptures') {
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        if ($scanSessionId === '') {
            json_response(['error' => 'scanSessionId required'], 422);
        }
        require_scan_session_access($pdo, $scanSessionId, $userID);

        $captures = capture_paths_for_session($pdo, $scanSessionId);
        if ($captures['front'] === null || $captures['left'] === null || $captures['right'] === null) {
            json_response(['error' => 'Upload all three captures before analysis'], 422);
        }

        if (!ai_service_is_available()) {
            $base = ai_service_base_url();
            json_response([
                'error' => 'AI analysis service is not running',
                'hint' => 'On the shop PC run: cd ai-service && uvicorn api:app --host 127.0.0.1 --port 8000. Set AI_SERVICE_URL in .env (current: ' . ($base !== '' ? $base : 'not set') . ').',
                'aiServiceUrl' => $base,
            ], 503);
        }

        $absolute = ai_service_absolute_capture_paths([
            'front' => (string)$captures['front'],
            'left' => (string)$captures['left'],
            'right' => (string)$captures['right'],
        ]);

        $analysis = ai_service_analyze_face($absolute);
        if (!$analysis['ok']) {
            json_response([
                'error' => $analysis['error'] !== '' ? $analysis['error'] : 'Face analysis failed',
                'hint' => 'Check the ai-service terminal for errors. Ensure uvicorn is running on the URL in AI_SERVICE_URL.',
            ], 502);
        }

        $data = $analysis['data'];
        // The sidecar returns HTTP 200 with placeholder values when the face
        // landmarker is unavailable (e.g. libGL/GLES failure on a headless
        // host). Without this check those placeholders were passed through as a
        // normal result, so the app recorded scanSucceeded=true and downstream
        // features (Library hair-texture guidance) trusted fabricated data.
        $analysisDegraded = ($data['degraded'] ?? false) === true
            || (string)($data['landmarker'] ?? '') === 'unavailable';
        $faceShape = (string)($data['face_shape'] ?? 'oval');
        $hairTexture = (string)($data['hair_texture'] ?? 'Wavy');
        $allowedTextures = ['Straight', 'Wavy', 'Curly'];
        if (!in_array($hairTexture, $allowedTextures, true)) {
            $hairTexture = 'Wavy';
        }
        $hairLengthLevel = (int)($data['hair_length_level'] ?? 1);
        $hairLengthLabel = (string)($data['hair_length'] ?? 'short');
        $hairColorLabel = trim((string)($data['hair_color'] ?? ''));
        $noHairDetected = (bool)($data['no_hair_detected'] ?? false);

        $updateStmt = $pdo->prepare(
            'UPDATE face_scan_sessions
             SET face_shape = :face_shape,
                 hair_texture = :hair_texture,
                 hair_length_level = :hair_length_level,
                 hair_length_label = :hair_length_label,
                 hair_color_label = :hair_color_label,
                 no_hair_detected = :no_hair_detected
             WHERE scan_session_id = :scan_session_id'
        );
        $updateStmt->execute([
            ':face_shape' => $faceShape,
            ':hair_texture' => $hairTexture,
            ':hair_length_level' => $hairLengthLevel,
            ':hair_length_label' => $hairLengthLabel,
            ':hair_color_label' => $hairColorLabel !== '' ? $hairColorLabel : null,
            ':no_hair_detected' => $noHairDetected ? 1 : 0,
            ':scan_session_id' => $scanSessionId,
        ]);

        json_response([
            'message' => 'Analysis complete',
            'faceShape' => $faceShape,
            'hairTexture' => $hairTexture,
            'hairLength' => $hairLengthLabel,
            'hairLengthLevel' => $hairLengthLevel,
            'hairLengthScore' => $data['hair_length_score'] ?? null,
            'hairTextureScore' => $data['hair_texture_score'] ?? null,
            'hairMaskCoverage' => $data['hair_mask_coverage'] ?? null,
            'noHairDetected' => (bool)($data['no_hair_detected'] ?? false),
            // 'ok' | 'none' (bald/shaved) | 'obstructed' (cap, hood, tied back).
            // Anything other than 'ok' means the sidecar deliberately returned
            // no texture/colour rather than guessing from a few pixels.
            'hairVisibility' => (string)($data['hair_visibility'] ?? 'ok'),
            'hairColor' => (string)($data['hair_color'] ?? ''),
            'hairColorRgb' => $data['hair_color_rgb'] ?? null,
            'topStyles' => $data['top_styles'] ?? [],
            'achievableStyles' => $data['achievable_styles'] ?? [],
            'degraded' => $analysisDegraded,
            'degradedReason' => $analysisDegraded
                ? (string)($data['degraded_reason'] ?? 'face_landmarker_unavailable')
                : null,
            // 'fallback' when the values are placeholders — the app keys its
            // scanSucceeded flag off this, so it must not claim 'ai-service'.
            'provider' => $analysisDegraded ? 'fallback' : 'ai-service',
        ]);
    }

    if ($action === 'generateStylePreviews') {
        set_time_limit(600);

        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $variantID = (int)($input['variantID'] ?? 0);
        $force = (bool)($input['forceRegenerate'] ?? false);

        if ($scanSessionId === '' || $variantID <= 0) {
            json_response(['error' => 'scanSessionId and variantID required'], 422);
        }
        require_scan_session_access($pdo, $scanSessionId, $userID);

        if (!ai_service_is_available() && !ai_tryon_is_configured()) {
            json_response([
                'error' => 'AI generation is not configured',
                'hint' => 'Start ai-service (AI_SERVICE_URL) or set XAI_API_KEY / GEMINI_API_KEY / REPLICATE_API_TOKEN in .env.',
            ], 503);
        }

        if (!$force) {
            $cachedStmt = $pdo->prepare(
                'SELECT front_url, left_url, right_url
                 FROM face_scan_previews
                 WHERE scan_session_id = :scan_session_id AND variant_id = :variant_id AND is_stale = FALSE
                 ORDER BY preview_id DESC
                 LIMIT 1'
            );
            $cachedStmt->execute([
                ':scan_session_id' => $scanSessionId,
                ':variant_id' => $variantID,
            ]);
            $cached = $cachedStmt->fetch(PDO::FETCH_ASSOC);
            if ($cached && !empty($cached['front_url'])) {
                $cacheValid = face_scan_preview_file_exists((string)$cached['front_url'])
                    && face_scan_preview_file_exists((string)($cached['left_url'] ?? ''))
                    && face_scan_preview_file_exists((string)($cached['right_url'] ?? ''));
                if ($cacheValid) {
                    json_response([
                        'message' => 'Previews loaded from cache',
                        'frontViewUrl' => $cached['front_url'],
                        'sideViewUrl' => $cached['left_url'],
                        'backViewUrl' => $cached['right_url'],
                        'provider' => 'cache',
                        'cached' => true,
                        'quota' => $userID !== null
                            ? ai_tryon_quota_status($pdo, $userID)
                            : ai_tryon_kiosk_quota_status($pdo, $scanSessionId),
                    ]);
                }
            }
        }

        // Quota is enforced only on a genuine new generation call (cache hits above are
        // free, and a regenerate of a style the user already has never costs a new slot).
        //
        // Mobile app (userID set, signed in) uses AI_TRYON_STYLE_LIMIT, counted per
        // account across all of that user's scans — unchanged from before.
        //
        // Kiosk / guest (userID null — no login at a walk-in kiosk) uses the separate
        // AI_TRYON_KIOSK_LIMIT, counted per scan session, since a walk-in has no
        // persistent identity to count against across visits. Previously this branch
        // did not exist at all, so kiosk generations were unmetered.
        if (!ai_tryon_unlimited()) {
            if ($userID !== null) {
                $styleLimit = ai_tryon_style_limit();
                $stylesUsed = ai_tryon_styles_used($pdo, $userID);
                $alreadyGenerated = ai_tryon_user_has_generated_variant($pdo, $userID, $variantID);
            } else {
                $styleLimit = ai_tryon_kiosk_limit();
                $stylesUsed = ai_tryon_kiosk_styles_used($pdo, $scanSessionId);
                $alreadyGenerated = ai_tryon_kiosk_has_generated_variant($pdo, $scanSessionId, $variantID);
            }

            if ($stylesUsed >= $styleLimit && !$alreadyGenerated) {
                json_response([
                    'error' => "You've reached your free AI hairstyle generation limit ({$styleLimit} styles).",
                    'quotaExceeded' => true,
                    'quota' => [
                        'limit' => $styleLimit,
                        'used' => $stylesUsed,
                        'remaining' => 0,
                        'unlimited' => false,
                    ],
                    'hint' => 'You can still view or regenerate a style you already tried.',
                ], 429);
            }
        }

        $variantStmt = $pdo->prepare(
            'SELECT hs.style_name, hs.style_code
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hv.variant_id = :variant_id
             LIMIT 1'
        );
        $variantStmt->execute([':variant_id' => $variantID]);
        $variant = $variantStmt->fetch(PDO::FETCH_ASSOC);
        if (!$variant) {
            json_response(['error' => 'Hairstyle variant not found'], 404);
        }

        $styleName = trim((string)($input['styleName'] ?? $variant['style_name'] ?? 'Selected haircut'));
        $styleCode = trim((string)($input['styleCode'] ?? $variant['style_code'] ?? ''));

        $captures = capture_paths_for_session($pdo, $scanSessionId);
        if ($captures['front'] === null || $captures['left'] === null || $captures['right'] === null) {
            json_response(['error' => 'Upload all three captures before generating previews'], 422);
        }

        $sessionMetaStmt = $pdo->prepare(
            'SELECT face_shape, hair_length_level, hair_length_label, hair_color_label
             FROM face_scan_sessions
             WHERE scan_session_id = :scan_session_id
             LIMIT 1'
        );
        $sessionMetaStmt->execute([':scan_session_id' => $scanSessionId]);
        $sessionMeta = $sessionMetaStmt->fetch(PDO::FETCH_ASSOC) ?: [];

        $hairLengthLevel = (int)($input['hairLengthLevel'] ?? $sessionMeta['hair_length_level'] ?? 1);
        $hairLengthLevel = max(0, min(3, $hairLengthLevel));

        $absolute = ai_service_absolute_capture_paths([
            'front' => (string)$captures['front'],
            'left' => (string)$captures['left'],
            'right' => (string)$captures['right'],
        ]);

        $feasibleToday = true;
        $lengthNote = null;
        $provider = ai_tryon_provider_name();
        $images = [];
        $previewDiagnostics = [];

        $hairColorLabel = trim((string)($sessionMeta['hair_color_label'] ?? ''));

        // Explicit gemini/grok in AI_TRYON_PROVIDER always wins over the Python sidecar
        // for image generation (sidecar remains used for face analysis only).
        //
        // Which of the two generation paths below runs is config-dependent, and
        // both are reachable — the sidecar branch is NOT dead code:
        //   AI_TRYON_PROVIDER=grok|gemini  -> cloud branch (current production)
        //   AI_TRYON_PROVIDER=replicate    -> sidecar /generate branch, if reachable
        //   AI_TRYON_PROVIDER unset/blank  -> sidecar /generate branch, if reachable
        // With the sidecar unreachable it always falls through to the cloud branch.
        $useCloudTryOn = ai_tryon_prefers_cloud_provider() || !ai_service_is_available();

        if (!$useCloudTryOn && ai_service_is_available()) {
            $generated = ai_service_generate_style(
                $absolute,
                $styleName,
                $styleCode !== '' ? $styleCode : null,
                $hairLengthLevel,
                $hairColorLabel
            );
            if (!$generated['ok']) {
                $err = (string)$generated['error'];
                $isBilling = stripos($err, '402') !== false
                    || stripos($err, 'insufficient credit') !== false
                    || stripos($err, 'billing') !== false;
                json_response([
                    'error' => $isBilling
                        ? 'Replicate account has no credits left for AI haircut generation.'
                        : $err,
                    'hint' => $isBilling
                        ? 'Add credits at https://replicate.com/account/billing — wait a few minutes, then tap Regenerate preview.'
                        : 'Check the ai-service terminal (uvicorn) for the full error.',
                ], $isBilling ? 402 : 502);
            }
            $images = $generated['images'];
            $feasibleToday = $generated['feasibleToday'];
            $lengthNote = $generated['lengthNote'];
            $previewDiagnostics = $generated['previewDiagnostics'] ?? [];
            $provider = 'ai-service';
        } else {
            $generated = ai_tryon_generate_three_view_previews(
                [
                    'front' => (string)$captures['front'],
                    'left' => (string)$captures['left'],
                    'right' => (string)$captures['right'],
                ],
                $styleName,
                $styleCode !== '' ? $styleCode : null,
                $hairLengthLevel,
                $hairColorLabel
            );
            $provider = $generated['provider'] ?? $provider;
            if (!$generated['ok']) {
                $err = (string)$generated['error'];
                $isBilling = stripos($err, '402') !== false
                    || stripos($err, 'insufficient credit') !== false
                    || stripos($err, 'billing') !== false
                    || stripos($err, 'quota') !== false
                    || stripos($err, 'resource_exhausted') !== false
                    || stripos($err, '429') !== false;
                // Name the provider that actually failed and whether fallback was
                // even permitted. With AI_TRYON_PROVIDER set explicitly and
                // AI_TRYON_ALLOW_FALLBACK off (the default), a single provider
                // outage fails the whole request instead of trying another —
                // that is intentional (it avoids spending on a second provider),
                // but it was previously indistinguishable from a hard error.
                $failedProvider = (string)($generated['provider'] ?? $provider ?? 'unknown');
                $fallbackAllowed = ai_tryon_allow_fallback();
                json_response([
                    'error' => $isBilling
                        ? "The AI provider ({$failedProvider}) has no credits/quota left for haircut generation right now."
                        : $err,
                    'provider' => $failedProvider,
                    'fallbackAllowed' => $fallbackAllowed,
                    'hint' => $isBilling
                        ? ($fallbackAllowed
                            ? "Every configured provider was tried and all are out of quota. Check billing for {$failedProvider}, then retry."
                            : "Only {$failedProvider} is used because AI_TRYON_PROVIDER is set explicitly and AI_TRYON_ALLOW_FALLBACK is off. Top up {$failedProvider}, or set AI_TRYON_ALLOW_FALLBACK=true to let it try another configured provider.")
                        : 'Check server logs for details.',
                ], $isBilling ? 402 : 502);
            }
            $images = $generated['images'];
            $feasibleToday = $generated['feasibleToday'];
            $lengthNote = $generated['lengthNote'];

            // The cloud helpers produce an orientation report but nothing ever
            // read it, so the per-angle warning banner the app already renders
            // was dead on this branch. Forward the entries the client knows how
            // to display; 'ok:' and 'skipped:' verdicts are noise.
            foreach (($generated['orientation'] ?? []) as $angle => $verdict) {
                $verdict = (string)$verdict;
                if (str_starts_with($verdict, 'duplicate:')) {
                    $previewDiagnostics[$angle]['duplicateView'] = true;
                    $previewDiagnostics[$angle]['orientation'] = $verdict;
                } elseif (str_starts_with($verdict, 'mismatch:')) {
                    $previewDiagnostics[$angle]['orientation'] = $verdict;
                }
            }
        }

        ensure_scan_session_row(
            $pdo,
            $scanSessionId,
            $userID,
            trim((string)($input['faceShape'] ?? $sessionMeta['face_shape'] ?? '')) ?: null,
            trim((string)($input['hairTexture'] ?? '')) ?: null
        );

        $front = save_preview_bytes($scanSessionId, $variantID, 'front', $images['front']);
        $left = save_preview_bytes($scanSessionId, $variantID, 'left', $images['left']);
        $right = save_preview_bytes($scanSessionId, $variantID, 'right', $images['right']);

        error_log(sprintf(
            'face_scan preview saved session=%s variant=%d front=%s (%d bytes)',
            $scanSessionId,
            $variantID,
            $front,
            strlen($images['front'])
        ));

        $stmt = $pdo->prepare(
            'INSERT INTO face_scan_previews (scan_session_id, variant_id, front_url, left_url, right_url)
             VALUES (:scan_session_id, :variant_id, :front_url, :left_url, :right_url)'
        );
        $stmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':variant_id' => $variantID,
            ':front_url' => $front,
            ':left_url' => $left,
            ':right_url' => $right,
        ]);

        json_response([
            'message' => 'Style previews generated',
            'frontViewUrl' => $front,
            'sideViewUrl' => $left,
            'backViewUrl' => $right,
            'provider' => $provider,
            'feasibleToday' => $feasibleToday,
            'lengthNote' => $lengthNote,
            'cached' => false,
            'previewDiagnostics' => $previewDiagnostics,
            'quota' => $userID !== null
                ? ai_tryon_quota_status($pdo, $userID)
                : ai_tryon_kiosk_quota_status($pdo, $scanSessionId),
        ]);
    }

    if ($action === 'generateReplicatePreview') {
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $styleName = trim((string)($input['styleName'] ?? 'Selected haircut'));
        $angle = trim((string)($input['angle'] ?? 'front'));
        if ($scanSessionId === '') {
            json_response(['error' => 'scanSessionId required'], 422);
        }
        if (!in_array($angle, ['front', 'left', 'right'], true)) {
            json_response(['error' => 'angle must be front, left, or right'], 422);
        }
        require_scan_session_access($pdo, $scanSessionId, $userID);

        if (!replicate_is_configured()) {
            json_response([
                'error' => 'Replicate is not configured',
                'hint' => 'Set REPLICATE_API_TOKEN in .env on the server.',
            ], 503);
        }

        $captureStmt = $pdo->prepare(
            'SELECT file_path FROM face_scan_captures WHERE scan_session_id = :scan_session_id AND angle = :angle LIMIT 1'
        );
        $captureStmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':angle' => $angle,
        ]);
        $capture = $captureStmt->fetch(PDO::FETCH_ASSOC);
        if (!$capture || empty($capture['file_path'])) {
            json_response(['error' => 'Capture not found for this session'], 404);
        }

        $absolutePath = api_project_root() . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim((string)$capture['file_path'], '/'));
        if (!is_readable($absolutePath)) {
            json_response(['error' => 'Capture file is not readable'], 500);
        }

        $bytes = file_get_contents($absolutePath);
        if ($bytes === false || $bytes === '') {
            json_response(['error' => 'Capture file is empty'], 500);
        }

        $mime = is_valid_jpeg_bytes($bytes) ? 'image/jpeg' : 'image/png';
        $dataUrl = 'data:' . $mime . ';base64,' . base64_encode($bytes);
        $generated = replicate_tryon_from_face_image($dataUrl, $styleName);
        if (!$generated['ok']) {
            json_response(['error' => $generated['error']], 502);
        }

        json_response([
            'message' => 'Replicate preview generated',
            'imageUrl' => $generated['imageUrl'],
            'provider' => 'replicate',
            'angle' => $angle,
        ]);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (InvalidArgumentException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => $e->getMessage()], 422);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => $e->getMessage()], 500);
}
