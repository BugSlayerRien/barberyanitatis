<?php
// AI Face Scan API (image upload -> haircuts)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$base64Payload = '';
$base64Mime = '';
if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
    $rawBody = file_get_contents('php://input');
    if (is_string($rawBody) && trim($rawBody) !== '') {
        $jsonBody = json_decode($rawBody, true);
        if (is_array($jsonBody)) {
            $base64Payload = (string)($jsonBody['imageBase64'] ?? $jsonBody['image'] ?? '');
        }
    }
    if ($base64Payload === '') {
        json_response(['error' => 'Image is required'], 422);
    }
    if (preg_match('/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/', $base64Payload, $matches)) {
        $base64Mime = $matches[1];
        $base64Payload = $matches[2];
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

$faceShape = isset($_POST['faceShape']) ? trim((string)$_POST['faceShape']) : '';
$hairTexture = isset($_POST['hairTexture']) ? trim((string)$_POST['hairTexture']) : '';
$hairDensity = isset($_POST['hairDensity']) ? trim((string)$_POST['hairDensity']) : '';

function normalize_face_shape(string $value): string
{
    $allowed = ['Oval', 'Round', 'Square', 'Heart', 'Diamond', 'Oblong'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return '';
}

function normalize_hair_texture(string $value): string
{
    $allowed = ['Straight', 'Wavy', 'Curly', 'Coily'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return '';
}

function normalize_hair_density(string $value): string
{
    $allowed = ['Thin', 'Medium', 'Thick'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return '';
}

function normalize_hair_length(string $value): string
{
    $allowed = ['Short', 'Medium', 'Long'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return '';
}

function normalize_hair_color(string $value): string
{
    $allowed = ['Black', 'Dark Brown', 'Brown', 'Blonde', 'Red', 'Gray', 'Unknown'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return '';
}

function build_scan_summary(array $cvPayload, bool $llmEnabled, int $count): string
{
    $parts = [];
    if (!empty($cvPayload['face_shape'])) {
        $parts[] = 'face shape: ' . $cvPayload['face_shape'];
    }
    if (!empty($cvPayload['hair_texture'])) {
        $parts[] = 'hair texture: ' . $cvPayload['hair_texture'];
    }
    if (!empty($cvPayload['hair_density'])) {
        $parts[] = 'hair density: ' . $cvPayload['hair_density'];
    }
    if (!empty($cvPayload['hair_length'])) {
        $parts[] = 'hair length: ' . $cvPayload['hair_length'];
    }
    if (!empty($cvPayload['color'])) {
        $parts[] = 'hair color: ' . $cvPayload['color'];
    }

    $basis = empty($parts)
        ? 'We used your scan to match styles with strong overall confidence.'
        : 'We detected ' . implode(', ', $parts) . ' and matched styles that best fit those features.';

    $rankNote = $llmEnabled
        ? 'AI ranking prioritized the closest face-shape and texture matches.'
        : 'Ranking is based on stored confidence scores and your detected features.';

    return $basis . ' ' . $rankNote . ' Showing top ' . $count . ' options.';
}

function build_variant_reason(array $row, array $cvPayload): string
{
    $reasons = [];
    if (!empty($cvPayload['face_shape']) && isset($row['face_shape']) && strcasecmp((string)$row['face_shape'], (string)$cvPayload['face_shape']) === 0) {
        $reasons[] = 'Matches your face shape.';
    }
    if (!empty($cvPayload['hair_texture']) && isset($row['hair_texture']) && strcasecmp((string)$row['hair_texture'], (string)$cvPayload['hair_texture']) === 0) {
        $reasons[] = 'Works well for your hair texture.';
    }
    if (empty($reasons)) {
        $reasons[] = 'Strong overall match based on confidence score.';
    }
    return implode(' ', $reasons);
}

function analyze_with_gemini(string $apiKey, string $imagePath, string $mimeType, string $model): array
{
    $imageData = base64_encode((string)file_get_contents($imagePath));
    $payload = [
        'contents' => [
            [
                'role' => 'user',
                'parts' => [
                    [
                        'text' => 'Analyze the hairstyle scan image and return ONLY valid JSON with keys: face_shape (Oval/Round/Square/Heart/Diamond/Oblong), hair_texture (Straight/Wavy/Curly/Coily), hair_density (Thin/Medium/Thick).',
                    ],
                    [
                        'inline_data' => [
                            'mime_type' => $mimeType,
                            'data' => $imageData,
                        ],
                    ],
                ],
            ],
        ],
        'generationConfig' => [
            'temperature' => 0.2,
        ],
    ];
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/' . rawurlencode($model) . ':generateContent?key=' . urlencode($apiKey);
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_TIMEOUT => 30,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
        return [];
    }

    $data = json_decode((string)$raw, true);
    $text = $data['candidates'][0]['content']['parts'][0]['text'] ?? '';
    $json = json_decode((string)$text, true);
    if (!is_array($json)) {
        return [];
    }
    return $json;
}

function run_cv_pipeline(string $imagePath): array
{
    $script = __DIR__ . '/cv_pipeline.py';
    if (!is_file($script)) {
        return [];
    }

    $python = getenv('CV_PIPELINE_PYTHON') ?: 'python';
    $cmd = escapeshellcmd($python) . ' ' . escapeshellarg($script) . ' ' . escapeshellarg($imagePath);
    $output = shell_exec($cmd);
    if (!is_string($output) || trim($output) === '') {
        return [];
    }

    $json = json_decode($output, true);
    if (!is_array($json)) {
        return [];
    }
    return $json;
}

function llm_rank_variants(string $provider, string $apiKey, string $model, array $cv, array $preferences, array $variants): array
{
    if ($provider === '' || $apiKey === '' || empty($variants)) {
        return [];
    }

    $payloadText = json_encode([
        'cv' => $cv,
        'preferences' => $preferences,
        'candidates' => array_map(static function ($row) {
            return [
                'variant_id' => (int)$row['variant_id'],
                'style_name' => (string)$row['style_name'],
                'style_code' => (string)$row['style_code'],
                'face_shape' => (string)$row['face_shape'],
                'hair_texture' => (string)$row['hair_texture'],
            ];
        }, $variants),
    ]);

    $prompt = "You are a hairstyle recommender. Given the JSON below, return ONLY valid JSON with key 'order' (array of variant_id) in best-to-worst order.\n" . $payloadText;

    $payload = [
        'contents' => [
            [
                'role' => 'user',
                'parts' => [
                    ['text' => $prompt],
                ],
            ],
        ],
        'generationConfig' => [
            'temperature' => 0.2,
        ],
    ];

    $url = 'https://generativelanguage.googleapis.com/v1beta/models/' . rawurlencode($model) . ':generateContent?key=' . urlencode($apiKey);
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_TIMEOUT => 30,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
        return [];
    }
    $data = json_decode((string)$raw, true);
    $text = $data['candidates'][0]['content']['parts'][0]['text'] ?? '';
    $json = json_decode((string)$text, true);
    return is_array($json) ? ($json['order'] ?? []) : [];
}

try {
    $pdo = get_db_connection();

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
             WHERE hs.is_active = 1
                 AND (:face_shape_1 = \'\' OR hv.face_shape = :face_shape_2)
                 AND (:hair_texture_1 = \'\' OR hv.hair_texture = :hair_texture_2)
             ORDER BY hv.confidence_score DESC, hs.style_name ASC
             LIMIT ' . $limit;
    $stmt = $pdo->prepare($query);
    $stmt->execute([
                ':face_shape_1' => $faceShape,
                ':face_shape_2' => $faceShape,
                ':hair_texture_1' => $hairTexture,
                ':hair_texture_2' => $hairTexture,
    ]);

    $variants = $stmt->fetchAll();

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
             WHERE hs.is_active = 1' . $excludeClause . '
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
            }
        }
    }

    $cvPayload = [
        'hair_length' => $hairLength,
        'hair_texture' => $hairTexture,
        'color' => $hairColor,
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
        'message' => 'Scan received',
        'imageUrl' => $publicUrl,
        'faceShape' => $faceShape,
        'hairTexture' => $hairTexture,
        'hairDensity' => $hairDensity,
        'hairLength' => $hairLength,
        'hairColor' => $hairColor,
        'cvAttributes' => $cvPayload,
        'llmEnabled' => $llmEnabled,
        'summary' => $summary,
        'recommendations' => $variants,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
