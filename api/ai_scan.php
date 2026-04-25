<?php
// AI Face Scan API (image upload -> haircuts)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

<<<<<<< Updated upstream
if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
    json_response(['error' => 'Image is required'], 422);
}

$userID = isset($_POST['userID']) ? (int)$_POST['userID'] : 0;
$faceShape = isset($_POST['faceShape']) ? trim((string)$_POST['faceShape']) : '';
$hairType = isset($_POST['hairType']) ? trim((string)$_POST['hairType']) : '';
=======
$rawBody = file_get_contents('php://input');
$jsonBody = [];
if (is_string($rawBody) && trim($rawBody) !== '') {
    $decodedBody = json_decode($rawBody, true);
    if (is_array($decodedBody)) {
        $jsonBody = $decodedBody;
    }
}

$action = trim((string)($_POST['action'] ?? ($jsonBody['action'] ?? 'scanImage')));
$isFeatureRankingAction = strcasecmp($action, 'rankByFeatures') === 0;

$base64Payload = '';
$base64Mime = '';
if (!$isFeatureRankingAction) {
    if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
        $base64Payload = (string)($jsonBody['imageBase64'] ?? $jsonBody['image'] ?? '');
        if ($base64Payload === '') {
            json_response(['error' => 'Image is required'], 422);
        }
        if (preg_match('/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/', $base64Payload, $matches)) {
            $base64Mime = $matches[1];
            $base64Payload = $matches[2];
        }
    }
}

// Optional local overrides for dev (set here if your server doesn't expose env vars)
$providerConfig = 'gemini';
$apiKeyConfig = 'REPLACE_WITH_GEMINI_KEY';

$provider = strtolower(trim((string)(
    getenv('AI_PROVIDER') ?: ($_ENV['AI_PROVIDER'] ?? $_SERVER['AI_PROVIDER'] ?? $providerConfig)
)));
$geminiModel = (string)(
    getenv('GEMINI_MODEL') ?: ($_ENV['GEMINI_MODEL'] ?? $_SERVER['GEMINI_MODEL'] ?? 'gemini-2.5-flash-lite')
);
$apiKey = trim((string)(
    getenv('AI_API_KEY') ?: ($_ENV['AI_API_KEY'] ?? $_SERVER['AI_API_KEY'] ?? $apiKeyConfig)
));

if ($provider === '') {
    $provider = 'gemini';
}

if ($provider !== 'gemini') {
    json_response(['error' => 'Unsupported AI provider (use gemini)'], 400);
}

$llmEnabled = $apiKey !== '' && $apiKey !== 'REPLACE_WITH_GEMINI_KEY';

$faceShape = trim((string)($_POST['faceShape'] ?? ($jsonBody['faceShape'] ?? '')));
$hairTexture = trim((string)($_POST['hairTexture'] ?? ($jsonBody['hairTexture'] ?? '')));
$hairDensity = trim((string)($_POST['hairDensity'] ?? ($jsonBody['hairDensity'] ?? '')));
>>>>>>> Stashed changes

$provider = getenv('AI_PROVIDER') ?: '';
$apiKey = getenv('AI_API_KEY') ?: '';

if ($provider === '' || $apiKey === '') {
    json_response(['error' => 'AI provider not configured'], 503);
}

// Placeholder: integrate external AI provider here.
// Suggested flow:
// 1) Upload image to provider for face + hair analysis.
// 2) Receive faceShape.
// 3) Query haircuts by faceShape (or fallback to all).
// 4) Return a list of imagePath for client display.

try {
    $pdo = get_db_connection();

<<<<<<< Updated upstream
        $query = 'SELECT haircutID, haircutName, faceShape, imagePath, isActive
                  FROM haircuts
                  WHERE isActive = 1 AND (:faceShape = \'\' OR faceShape = :faceShape OR faceShape IS NULL)
                  ORDER BY haircutName
                  LIMIT 12';
=======
    if ($isFeatureRankingAction) {
        $faceShape = normalize_face_shape($faceShape);
        $hairTexture = normalize_hair_texture($hairTexture);
        $hairDensity = normalize_hair_density($hairDensity);

        $limit = 8;
                $sql = <<<'SQL'
SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
             hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes,
             hs.style_name, hs.style_code, hs.description,
             (
                 hv.confidence_score
                 + CASE
                         WHEN :face_shape <> '' AND LOWER(hv.face_shape) = LOWER(:face_shape) THEN 0.45
                         ELSE 0
                     END
                 + CASE
                         WHEN :hair_texture <> '' AND LOWER(hv.hair_texture) = LOWER(:hair_texture) THEN 0.55
                         ELSE 0
                     END
                 + CASE
                         WHEN :hair_texture <> ''
                             AND LOWER(:hair_texture) <> 'coily'
                             AND (
                                 LOWER(hs.style_name) LIKE '%afro%'
                                 OR LOWER(hs.style_name) LIKE '%dread%'
                                 OR LOWER(hs.style_name) LIKE '%twist%'
                             )
                         THEN -0.85
                         ELSE 0
                     END
             ) AS match_score
FROM hairstyle_variants hv
JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE hs.is_active = TRUE
    AND (
             :face_shape = ''
             OR LOWER(hv.face_shape) = LOWER(:face_shape)
             OR hv.face_shape IS NULL
             OR hv.face_shape = ''
    )
    AND (
             :hair_texture = ''
             OR LOWER(hv.hair_texture) = LOWER(:hair_texture)
             OR hv.hair_texture IS NULL
             OR hv.hair_texture = ''
    )
ORDER BY match_score DESC, hv.confidence_score DESC, hs.style_name
SQL;
                $stmt = $pdo->prepare($sql . ' LIMIT ' . $limit);
        $stmt->execute([
            ':face_shape' => $faceShape,
            ':hair_texture' => $hairTexture,
        ]);

        $variants = $stmt->fetchAll();

        $preferences = [];
        $prefRaw = $_POST['preferences'] ?? ($jsonBody['preferences'] ?? null);
        if (is_string($prefRaw)) {
            $decoded = json_decode($prefRaw, true);
            if (is_array($decoded)) {
                $preferences = $decoded;
            }
        } elseif (is_array($prefRaw)) {
            $preferences = $prefRaw;
        }

        $cvPayload = [
            'hair_length' => '',
            'hair_texture' => $hairTexture,
            'color' => 'Unknown',
            'face_shape' => $faceShape,
            'hair_density' => $hairDensity,
        ];

        $order = $llmEnabled
            ? llm_rank_variants($provider, $apiKey, $geminiModel, $cvPayload, $preferences, $variants)
            : [];
        if (!empty($order)) {
            $byId = [];
            foreach ($variants as $row) {
                $byId[(int)$row['variant_id']] = $row;
            }
            $sorted = [];
            foreach ($order as $id) {
                $key = (int)$id;
                if (isset($byId[$key])) {
                    $sorted[] = $byId[$key];
                    unset($byId[$key]);
                }
            }
            foreach ($byId as $row) {
                $sorted[] = $row;
            }
            $variants = $sorted;
        }

        $summary = build_scan_summary($cvPayload, $llmEnabled, count($variants));
        $variants = array_map(static function ($row) use ($cvPayload) {
            if (!is_array($row)) {
                return $row;
            }
            $row['rank_reason'] = build_variant_reason($row, $cvPayload);
            return $row;
        }, $variants);

        json_response([
            'message' => 'Feature ranking complete',
            'faceShape' => $faceShape,
            'hairTexture' => $hairTexture,
            'hairDensity' => $hairDensity,
            'cvAttributes' => $cvPayload,
            'llmEnabled' => $llmEnabled,
            'summary' => $summary,
            'recommendations' => $variants,
            'variants' => $variants,
        ]);
    }

    $uploadDir = __DIR__ . '/../uploads/mobile';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0775, true);
    }

    $uploadedMime = 'image/jpeg';
    if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
        $fileInfo = pathinfo((string)$_FILES['image']['name']);
        $extension = strtolower($fileInfo['extension'] ?? 'jpg');
        $safeExtension = in_array($extension, ['jpg', 'jpeg', 'png'], true) ? $extension : 'jpg';
        $filename = 'scan_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExtension;
        $targetPath = $uploadDir . '/' . $filename;

        if (!move_uploaded_file($_FILES['image']['tmp_name'], $targetPath)) {
            json_response(['error' => 'Failed to store image'], 500);
        }
        $uploadedMime = $_FILES['image']['type'] ?? 'image/jpeg';
    } else {
        $decoded = base64_decode($base64Payload, true);
        if ($decoded === false) {
            json_response(['error' => 'Invalid image payload'], 422);
        }
        $safeExtension = 'jpg';
        if ($base64Mime === 'image/png') {
            $safeExtension = 'png';
        } elseif ($base64Mime === 'image/jpeg' || $base64Mime === 'image/jpg') {
            $safeExtension = 'jpg';
        }
        $filename = 'scan_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExtension;
        $targetPath = $uploadDir . '/' . $filename;
        if (file_put_contents($targetPath, $decoded) === false) {
            json_response(['error' => 'Failed to store image'], 500);
        }
        $uploadedMime = $base64Mime !== '' ? $base64Mime : 'image/jpeg';
    }

    $baseUrl = getenv('PUBLIC_BASE_URL') ?: '';
    $publicUrl = $baseUrl !== ''
        ? rtrim($baseUrl, '/') . '/uploads/mobile/' . $filename
        : '/uploads/mobile/' . $filename;

    $cv = run_cv_pipeline($targetPath);

    $faceShape = normalize_face_shape((string)($cv['face_shape'] ?? $faceShape));
    $hairTexture = normalize_hair_texture((string)($cv['hair_texture'] ?? $hairTexture));
    $hairDensity = normalize_hair_density((string)($cv['hair_density'] ?? $hairDensity));
    $hairLength = normalize_hair_length((string)($cv['hair_length'] ?? ''));
    $hairColor = normalize_hair_color((string)($cv['color'] ?? ''));

    if ($llmEnabled) {
        $analysis = analyze_with_gemini($apiKey, $targetPath, $uploadedMime ?? 'image/jpeg', $geminiModel);
        $faceShape = normalize_face_shape((string)($analysis['face_shape'] ?? $faceShape));
        $hairTexture = normalize_hair_texture((string)($analysis['hair_texture'] ?? $hairTexture));
        $hairDensity = normalize_hair_density((string)($analysis['hair_density'] ?? $hairDensity));
    }

    $limit = 4;
    $query =
            'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                            hv.confidence_score, hs.style_name, hs.style_code
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hs.is_active = TRUE
                 AND (:face_shape_1 = \'\' OR hv.face_shape = :face_shape_2)
                 AND (:hair_texture_1 = \'\' OR hv.hair_texture = :hair_texture_2)
             ORDER BY hv.confidence_score DESC, hs.style_name ASC
             LIMIT ' . $limit;
>>>>>>> Stashed changes
    $stmt = $pdo->prepare($query);
    $stmt->execute([
        ':faceShape' => $faceShape,
    ]);

        $haircuts = $stmt->fetchAll();

<<<<<<< Updated upstream
        if ($userID > 0) {
            $recStmt = $pdo->prepare(
                'INSERT INTO aiRecommendations (userID, haircutID, confidenceScore)
                 VALUES (:userID, :haircutID, :confidenceScore)'
            );
            foreach ($haircuts as $row) {
                $recStmt->execute([
                    ':userID' => $userID,
                    ':haircutID' => (int)$row['haircutID'],
                    ':confidenceScore' => 0.0,
                ]);
=======
    if (count($variants) < $limit) {
        $needed = $limit - count($variants);
        $excludeIds = array_values(array_filter(array_map(static function ($row) {
            return isset($row['variant_id']) ? (int)$row['variant_id'] : null;
        }, $variants), static function ($value) {
            return $value !== null;
        }));

        $excludeClause = '';
        $params = [];
        if (!empty($excludeIds)) {
            $placeholders = [];
            foreach ($excludeIds as $index => $id) {
                $key = ':exclude_' . $index;
                $placeholders[] = $key;
                $params[$key] = $id;
            }
            $excludeClause = ' AND hv.variant_id NOT IN (' . implode(',', $placeholders) . ')';
        }

        $fillQuery =
            'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hv.confidence_score, hs.style_name, hs.style_code
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hs.is_active = TRUE' . $excludeClause . '
             ORDER BY hv.confidence_score DESC, hs.style_name ASC
             LIMIT ' . (int)$needed;

        $fillStmt = $pdo->prepare($fillQuery);
        $fillStmt->execute($params);
        $fillRows = $fillStmt->fetchAll();
        if (!empty($fillRows)) {
            $variants = array_merge($variants, $fillRows);
        }
    }


    $preferences = [];
    if (isset($_POST['preferences'])) {
        $prefRaw = $_POST['preferences'];
        if (is_string($prefRaw)) {
            $decoded = json_decode($prefRaw, true);
            if (is_array($decoded)) {
                $preferences = $decoded;
>>>>>>> Stashed changes
            }
        }

    json_response([
        'message' => 'Scan received',
        'userID' => $userID,
        'faceShape' => $faceShape,
        'hairType' => $hairType,
        'haircuts' => $haircuts,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
