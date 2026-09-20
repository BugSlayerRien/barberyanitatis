<?php
// Admin hairstyles API (list + CRUD + variant CRUD + overlay upload)

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';
// ensure_top_pick_eligible_column() lives there because the recommendation
// ranking query needs the column too, not just this screen.
require_once __DIR__ . '/variant_ranking.php';

const ADMIN_OVERLAY_MAX_BYTES = 5 * 1024 * 1024;

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

try {
    $pdo = get_db_connection();

    schema_ensure_once('hairstyles.top_pick_eligible', static function () use ($pdo): void {
        ensure_top_pick_eligible_column($pdo);
    });

    // Category decides which Library section a cut appears in. It is stored per
    // style (see hairstyle_categories_and_catalog.sql) so a haircut cannot drift
    // between sections between requests.
    $normalizeCategory = static function ($raw): string {
        $value = strtolower(trim((string)$raw));
        return in_array($value, ['formal', 'alternative'], true) ? $value : 'alternative';
    };

    // Absent means eligible: a client that does not send the field (an older
    // admin build) must not silently drop styles out of Top picks.
    $normalizeTopPickEligible = static function ($raw): bool {
        if ($raw === null) {
            return true;
        }
        if (is_bool($raw)) {
            return $raw;
        }
        return !in_array(strtolower(trim((string)$raw)), ['0', 'false', 'no', ''], true);
    };

    if ($method === 'GET') {
        $stmt = $pdo->query(<<<'SQL'
            SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description,
                   hs.gender, hs.difficulty, hs.maintenance, hs.category, hs.is_active,
                   hs.top_pick_eligible, hs.created_at,
                   COUNT(hv.variant_id) AS variant_count,
                   -- Textures live on the variants, not the style. Aggregate them
                   -- so the admin list can filter by texture without a second query.
                   -- Nowdoc, not a single-quoted string: the ',' separator below
                   -- would otherwise close the string and become a second
                   -- argument to PDO::query().
                   STRING_AGG(DISTINCT hv.hair_texture, ',') AS hair_textures
              FROM hairstyles hs
              LEFT JOIN hairstyle_variants hv ON hv.hairstyle_id = hs.hairstyle_id
             GROUP BY hs.hairstyle_id, hs.style_code, hs.style_name, hs.description,
                      hs.gender, hs.difficulty, hs.maintenance, hs.category, hs.is_active,
                      hs.top_pick_eligible, hs.created_at
             ORDER BY hs.style_name
            SQL
        );
        $rows = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $normalized = apply_hairstyle_overlay_paths($row);
            $overlayInfo = overlay_paths_for_hairstyle($row);
            $normalized['overlay_folder'] = $overlayInfo['folder'] ?? ($normalized['overlay_folder'] ?? null);
            $normalized['has_overlay_assets'] = hairstyle_overlay_files_exist($normalized);
            $rows[] = $normalized;
        }

        json_response(['hairstyles' => $rows]);
    }

    if ($method === 'POST' && isset($_POST['action']) && (string)$_POST['action'] === 'uploadOverlay') {
        handle_upload_overlay($pdo);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = trim((string)($input['action'] ?? ''));

    if ($action === 'get') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        if ($hairstyleID <= 0) {
            json_response(['error' => 'Invalid hairstyleID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT hairstyle_id, style_code, style_name, description, gender, difficulty, maintenance, category, is_active, top_pick_eligible, created_at
             FROM hairstyles WHERE hairstyle_id = :id LIMIT 1'
        );
        $stmt->execute([':id' => $hairstyleID]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            json_response(['error' => 'Hairstyle not found'], 404);
        }

        $hairstyle = apply_hairstyle_overlay_paths($row);
        $overlayInfo = overlay_paths_for_hairstyle($row);
        $hairstyle['overlay_folder'] = $overlayInfo['folder'] ?? ($hairstyle['overlay_folder'] ?? null);
        $hairstyle['has_overlay_assets'] = hairstyle_overlay_files_exist($hairstyle);

        $variantStmt = $pdo->prepare(
            'SELECT variant_id, hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
                    barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
             FROM hairstyle_variants
             WHERE hairstyle_id = :id
             ORDER BY face_shape, hair_texture'
        );
        $variantStmt->execute([':id' => $hairstyleID]);

        json_response([
            'hairstyle' => $hairstyle,
            'variants' => $variantStmt->fetchAll(PDO::FETCH_ASSOC),
        ]);
    }

    if ($action === 'create') {
        $styleName = trim((string)($input['styleName'] ?? ''));
        $styleCode = trim((string)($input['styleCode'] ?? ''));
        if ($styleName === '') {
            json_response(['error' => 'styleName is required'], 422);
        }

        if ($styleCode === '') {
            $styleCode = 'HC-' . strtoupper(preg_replace('/[^A-Z0-9]+/', '-', $styleName) ?? 'STYLE');
            $styleCode = substr($styleCode, 0, 20);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, category, is_active, top_pick_eligible)
             VALUES (:style_code, :style_name, :description, :gender, :difficulty, :maintenance, :category, :is_active, :top_pick_eligible)
             RETURNING hairstyle_id'
        );
        $stmt->execute([
            ':style_code' => $styleCode,
            ':style_name' => $styleName,
            ':description' => trim((string)($input['description'] ?? '')) ?: null,
            ':gender' => normalize_hairstyle_gender($input['gender'] ?? 'Unisex'),
            ':difficulty' => normalize_hairstyle_tier($input['difficulty'] ?? 'Medium', ['Easy', 'Medium', 'Hard']),
            ':maintenance' => normalize_hairstyle_tier($input['maintenance'] ?? 'Medium', ['Low', 'Medium', 'High']),
            ':category' => $normalizeCategory($input['category'] ?? 'alternative'),
            ':is_active' => !empty($input['isActive']) && (string)$input['isActive'] !== '0',
            ':top_pick_eligible' => $normalizeTopPickEligible($input['topPickEligible'] ?? null),
        ]);

        json_response([
            'message' => 'Hairstyle created',
            'hairstyleID' => (int)$stmt->fetchColumn(),
        ]);
    }

    if ($action === 'update') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        $styleName = trim((string)($input['styleName'] ?? ''));
        if ($hairstyleID <= 0 || $styleName === '') {
            json_response(['error' => 'Invalid hairstyle payload'], 422);
        }

        $styleCode = trim((string)($input['styleCode'] ?? ''));
        $sql = 'UPDATE hairstyles
                SET style_name = :style_name,
                    description = :description,
                    gender = :gender,
                    difficulty = :difficulty,
                    maintenance = :maintenance,
                    category = :category,
                    is_active = :is_active,
                    top_pick_eligible = :top_pick_eligible';
        $params = [
            ':style_name' => $styleName,
            ':description' => trim((string)($input['description'] ?? '')) ?: null,
            ':gender' => normalize_hairstyle_gender($input['gender'] ?? 'Unisex'),
            ':difficulty' => normalize_hairstyle_tier($input['difficulty'] ?? 'Medium', ['Easy', 'Medium', 'Hard']),
            ':maintenance' => normalize_hairstyle_tier($input['maintenance'] ?? 'Medium', ['Low', 'Medium', 'High']),
            ':category' => $normalizeCategory($input['category'] ?? 'alternative'),
            ':is_active' => !empty($input['isActive']) && (string)$input['isActive'] !== '0',
            ':top_pick_eligible' => $normalizeTopPickEligible($input['topPickEligible'] ?? null),
            ':id' => $hairstyleID,
        ];

        if ($styleCode !== '') {
            $sql .= ', style_code = :style_code';
            $params[':style_code'] = $styleCode;
        }
        $sql .= ' WHERE hairstyle_id = :id';

        $pdo->prepare($sql)->execute($params);
        json_response(['message' => 'Hairstyle updated']);
    }

    if ($action === 'delete') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        if ($hairstyleID <= 0) {
            json_response(['error' => 'Invalid hairstyleID'], 422);
        }

        $pdo->prepare('UPDATE hairstyles SET is_active = FALSE WHERE hairstyle_id = :id')
            ->execute([':id' => $hairstyleID]);

        json_response(['message' => 'Hairstyle deactivated']);
    }

    if ($action === 'createVariant') {
        $hairstyleID = (int)($input['hairstyleID'] ?? 0);
        $faceShape = trim((string)($input['faceShape'] ?? 'Oval'));
        $hairTexture = trim((string)($input['hairTexture'] ?? 'Straight'));
        if ($hairstyleID <= 0) {
            json_response(['error' => 'hairstyleID is required'], 422);
        }

        $paths = variant_overlay_paths_for_hairstyle($pdo, $hairstyleID);
        $stmt = $pdo->prepare(
            'INSERT INTO hairstyle_variants (
                hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
                barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
             ) VALUES (
                :hairstyle_id, :face_shape, :hair_texture, :front_view_url, :side_view_url, :back_view_url,
                :barber_instructions, :clipper_sizes, :styling_products, :estimated_minutes, :confidence_score
             )
             RETURNING variant_id'
        );
        $stmt->execute([
            ':hairstyle_id' => $hairstyleID,
            ':face_shape' => $faceShape,
            ':hair_texture' => normalize_hair_texture($hairTexture),
            ':front_view_url' => $paths['front'] ?? '',
            ':side_view_url' => $paths['side'] ?? '',
            ':back_view_url' => $paths['back'] ?? '',
            ':barber_instructions' => trim((string)($input['barberInstructions'] ?? 'Standard finish.')),
            ':clipper_sizes' => trim((string)($input['clipperSizes'] ?? '0.5, 1, 2')),
            ':styling_products' => trim((string)($input['stylingProducts'] ?? 'Matte clay')),
            ':estimated_minutes' => max(10, (int)($input['estimatedMinutes'] ?? 40)),
            ':confidence_score' => (float)($input['confidenceScore'] ?? 0.85),
        ]);

        json_response([
            'message' => 'Variant created',
            'variantID' => (int)$stmt->fetchColumn(),
        ]);
    }

    if ($action === 'updateVariant') {
        $variantID = (int)($input['variantID'] ?? 0);
        if ($variantID <= 0) {
            json_response(['error' => 'variantID is required'], 422);
        }

        $pdo->prepare(
            'UPDATE hairstyle_variants
             SET face_shape = :face_shape,
                 hair_texture = :hair_texture,
                 barber_instructions = :barber_instructions,
                 clipper_sizes = :clipper_sizes,
                 styling_products = :styling_products,
                 estimated_minutes = :estimated_minutes,
                 confidence_score = :confidence_score
             WHERE variant_id = :variant_id'
        )->execute([
            ':face_shape' => trim((string)($input['faceShape'] ?? 'Oval')),
            ':hair_texture' => normalize_hair_texture((string)($input['hairTexture'] ?? 'Straight')),
            ':barber_instructions' => trim((string)($input['barberInstructions'] ?? '')),
            ':clipper_sizes' => trim((string)($input['clipperSizes'] ?? '')),
            ':styling_products' => trim((string)($input['stylingProducts'] ?? '')),
            ':estimated_minutes' => max(10, (int)($input['estimatedMinutes'] ?? 40)),
            ':confidence_score' => (float)($input['confidenceScore'] ?? 0.85),
            ':variant_id' => $variantID,
        ]);

        json_response(['message' => 'Variant updated']);
    }

    if ($action === 'deleteVariant') {
        $variantID = (int)($input['variantID'] ?? 0);
        if ($variantID <= 0) {
            json_response(['error' => 'variantID is required'], 422);
        }

        $pdo->prepare('DELETE FROM hairstyle_variants WHERE variant_id = :id')
            ->execute([':id' => $variantID]);

        json_response(['message' => 'Variant deleted']);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response(['error' => 'Server error', 'details' => $e->getMessage()], 500);
}

function normalize_hairstyle_gender(string $value): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    return in_array($normalized, ['Male', 'Female', 'Unisex'], true) ? $normalized : 'Unisex';
}

/**
 * @param list<string> $allowed
 */
function normalize_hairstyle_tier(string $value, array $allowed): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    return in_array($normalized, $allowed, true) ? $normalized : $allowed[1];
}

function normalize_hair_texture(string $value): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    if ($normalized === 'Coily') {
        return 'Curly';
    }
    return in_array($normalized, ['Straight', 'Wavy', 'Curly'], true) ? $normalized : 'Straight';
}

/**
 * @return array{front?: string, side?: string, back?: string}
 */
function variant_overlay_paths_for_hairstyle(PDO $pdo, int $hairstyleId): array
{
    $stmt = $pdo->prepare(
        'SELECT style_name, style_code FROM hairstyles WHERE hairstyle_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $hairstyleId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return [];
    }

    $paths = overlay_paths_for_hairstyle($row);

    return $paths ?? [];
}

function overlay_asset_is_present(string $relativePath): bool
{
    static $cache = [];
    $relativePath = ltrim(str_replace('\\', '/', trim($relativePath)), '/');
    if ($relativePath === '') {
        return false;
    }
    if (array_key_exists($relativePath, $cache)) {
        return $cache[$relativePath];
    }

    $present = overlay_library_local_exists($relativePath);
    if (!$present && function_exists('storage_exists')) {
        $present = storage_exists($relativePath);
    }

    $cache[$relativePath] = $present;

    return $present;
}

function hairstyle_overlay_files_exist(array $hairstyle): bool
{
    $mapped = overlay_paths_for_hairstyle($hairstyle);
    $paths = $mapped !== null
        ? [$mapped['front'], $mapped['side'], $mapped['back']]
        : array_values(array_filter([
            (string)($hairstyle['front_view_url'] ?? ''),
            (string)($hairstyle['side_view_url'] ?? ''),
            (string)($hairstyle['back_view_url'] ?? ''),
        ]));

    if (count($paths) < 3) {
        return false;
    }

    foreach ($paths as $path) {
        if (!overlay_asset_is_present((string)$path)) {
            return false;
        }
    }

    return true;
}

function handle_upload_overlay(PDO $pdo): void
{
    $hairstyleID = (int)($_POST['hairstyleID'] ?? $_POST['hairstyle_id'] ?? 0);
    $view = trim((string)($_POST['view'] ?? ''));
    $folderOverride = trim((string)($_POST['overlayFolder'] ?? ''));

    if ($hairstyleID <= 0 || $view === '') {
        json_response(['error' => 'hairstyleID and view are required'], 422);
    }

    if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'] ?? '')) {
        json_response(['error' => 'PNG file is required'], 422);
    }

    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
        json_response(['error' => 'Upload failed'], 422);
    }

    if ((int)($file['size'] ?? 0) > ADMIN_OVERLAY_MAX_BYTES) {
        json_response(['error' => 'File exceeds 5MB limit'], 422);
    }

    $mime = mime_content_type($file['tmp_name']) ?: '';
    if (!in_array($mime, ['image/png', 'image/x-png'], true)) {
        json_response(['error' => 'Only PNG overlays are supported'], 422);
    }

    $stmt = $pdo->prepare(
        'SELECT style_name, style_code FROM hairstyles WHERE hairstyle_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $hairstyleID]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $styleName = (string)($row['style_name'] ?? '');
    $styleCode = (string)($row['style_code'] ?? '');
    if ($styleName === '' && $styleCode === '') {
        json_response(['error' => 'Hairstyle not found'], 404);
    }

    $target = overlay_target_for_view($styleName, $view, $styleCode);
    if ($target === null && $folderOverride === '') {
        json_response([
            'error' => 'No overlay mapping for this style. Set overlayFolder when uploading a new style.',
        ], 422);
    }

    $folder = $target['folder'] ?? slugify_overlay_folder($folderOverride !== '' ? $folderOverride : $styleName);
    $filename = $target['filename'] ?? sprintf(
        '%s_%s.png',
        slugify_overlay_folder($styleName),
        match (strtolower($view)) {
            'front' => 'front',
            'left', 'side' => 'left',
            'right', 'back' => 'right',
            default => 'front',
        }
    );

    $bytes = file_get_contents($file['tmp_name']);
    if ($bytes === false || $bytes === '') {
        json_response(['error' => 'Could not read overlay file'], 500);
    }

    $dir = mobile_app_overlay_root() . '/' . $folder;
    $dest = $dir . '/' . $filename;
    $assetPath = 'assets/images/overlays/' . $folder . '/' . $filename;
    $wroteLocal = false;
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        if (storage_driver() !== 'supabase') {
            json_response(['error' => 'Could not create overlay directory'], 500);
        }
    } else {
        $wroteLocal = file_put_contents($dest, $bytes) !== false;
        if (!$wroteLocal && storage_driver() !== 'supabase') {
            json_response(['error' => 'Could not save overlay file'], 500);
        }
    }

    if (storage_driver() === 'supabase') {
        storage_put_bytes($assetPath, $bytes, 'image/png');
    } elseif (!$wroteLocal) {
        json_response(['error' => 'Could not save overlay file'], 500);
    }
    $column = match (strtolower($view)) {
        'front' => 'front_view_url',
        'left', 'side' => 'side_view_url',
        'right', 'back' => 'back_view_url',
        default => null,
    };

    if ($column !== null) {
        $allowedColumns = [
            'front_view_url' => 'front_view_url',
            'side_view_url' => 'side_view_url',
            'back_view_url' => 'back_view_url',
        ];
        $safeColumn = $allowedColumns[$column] ?? null;
        if ($safeColumn !== null) {
            $pdo->prepare(
                "UPDATE hairstyle_variants SET {$safeColumn} = :path WHERE hairstyle_id = :hairstyle_id"
            )->execute([
                ':path' => $assetPath,
                ':hairstyle_id' => $hairstyleID,
            ]);
        }
    }

    json_response([
        'message' => 'Overlay uploaded',
        'path' => $assetPath,
        'folder' => $folder,
        'filename' => $filename,
    ]);
}
