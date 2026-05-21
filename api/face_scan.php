<?php
// Face scan capture storage and customer preview URLs for appointments.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/replicate_helper.php';

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
}

function face_scan_upload_root(): string
{
    return dirname(__DIR__) . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'face_scans';
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

    $dir = face_scan_upload_root() . DIRECTORY_SEPARATOR . preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId);
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('Unable to create upload directory');
    }

    $filename = $angle . '.jpg';
    $fullPath = $dir . DIRECTORY_SEPARATOR . $filename;
    if (file_put_contents($fullPath, $bytes) === false) {
        throw new RuntimeException("Unable to write {$filename}");
    }

    return 'uploads/face_scans/' . basename($dir) . '/' . $filename;
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

    $dir = face_scan_upload_root() . DIRECTORY_SEPARATOR . preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId) . DIRECTORY_SEPARATOR . 'previews';
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('Unable to create preview directory');
    }

    $ext = is_valid_jpeg_bytes($bytes) ? 'jpg' : 'png';
    $filename = $angle . '.' . $ext;
    $fullPath = $dir . DIRECTORY_SEPARATOR . $filename;
    if (file_put_contents($fullPath, $bytes) === false) {
        throw new RuntimeException("Unable to write preview {$filename}");
    }

    return 'uploads/face_scans/' . basename(dirname($dir)) . '/previews/' . $filename;
}

try {
    $pdo = get_db_connection();
    ensure_face_scan_tables($pdo);

    if ($action === 'uploadCaptures') {
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        if ($scanSessionId === '') {
            json_response(['error' => 'scanSessionId required'], 422);
        }

        $userID = isset($input['userID']) ? (int)$input['userID'] : 0;
        if ($userID <= 0) {
            $userID = null;
        }

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
        $userID = isset($input['userID']) ? (int)$input['userID'] : 0;
        if ($userID <= 0) {
            $userID = null;
        }

        if ($scanSessionId === '' || $variantID <= 0 || !is_array($previews)) {
            json_response(['error' => 'Invalid preview payload'], 422);
        }

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

        $previewStmt = $pdo->prepare(
            'SELECT front_url, left_url, right_url
             FROM face_scan_previews
             WHERE scan_session_id = :scan_session_id
               AND (:variant_id <= 0 OR variant_id = :variant_id)
             ORDER BY preview_id DESC
             LIMIT 1'
        );
        $previewStmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':variant_id' => $variantID,
        ]);
        $preview = $previewStmt->fetch();

        $front = $preview['front_url'] ?? ($input['frontViewUrl'] ?? null);
        $left = $preview['left_url'] ?? ($input['sideViewUrl'] ?? null);
        $right = $preview['right_url'] ?? ($input['backViewUrl'] ?? null);

        $pdo->beginTransaction();

        $apptStmt = $pdo->prepare(
            'UPDATE appointments SET scan_session_id = :scan_session_id WHERE appointment_id = :appointment_id'
        );
        $apptStmt->execute([
            ':scan_session_id' => $scanSessionId,
            ':appointment_id' => $appointmentID,
        ]);

        $detailStmt = $pdo->prepare(
            'UPDATE appointment_details
             SET customer_front_url = COALESCE(:front_url, customer_front_url),
                 customer_left_url = COALESCE(:left_url, customer_left_url),
                 customer_right_url = COALESCE(:right_url, customer_right_url)
             WHERE appointment_id = :appointment_id'
        );
        $detailStmt->execute([
            ':appointment_id' => $appointmentID,
            ':front_url' => $front,
            ':left_url' => $left,
            ':right_url' => $right,
        ]);

        $pdo->commit();

        json_response([
            'message' => 'Appointment previews attached',
            'frontViewUrl' => $front,
            'sideViewUrl' => $left,
            'backViewUrl' => $right,
        ]);
    }

    if ($action === 'generateReplicatePreview') {
        if (!replicate_is_configured()) {
            json_response([
                'error' => 'Replicate is not configured',
                'hint' => 'Set REPLICATE_API_TOKEN in .env on the server.',
            ], 503);
        }

        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $styleName = trim((string)($input['styleName'] ?? 'Selected haircut'));
        $angle = trim((string)($input['angle'] ?? 'front'));
        if ($scanSessionId === '') {
            json_response(['error' => 'scanSessionId required'], 422);
        }
        if (!in_array($angle, ['front', 'left', 'right'], true)) {
            json_response(['error' => 'angle must be front, left, or right'], 422);
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

        $absolutePath = dirname(__DIR__) . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim((string)$capture['file_path'], '/'));
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
