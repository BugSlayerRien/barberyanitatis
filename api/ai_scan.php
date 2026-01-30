<?php
// AI Face Scan API (image upload -> haircuts)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
    json_response(['error' => 'Image is required'], 422);
}

$provider = getenv('AI_PROVIDER') ?: '';
$apiKey = getenv('AI_API_KEY') ?: '';

if ($provider === '' || $apiKey === '') {
    json_response(['error' => 'AI provider not configured'], 503);
}

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

function analyze_with_openai(string $apiKey, string $imagePath, string $mimeType): array
{
    $imageData = base64_encode((string)file_get_contents($imagePath));
    $payload = [
        'model' => 'gpt-4o-mini',
        'input' => [
            [
                'role' => 'user',
                'content' => [
                    [
                        'type' => 'input_text',
                        'text' => 'Analyze the hairstyle scan image and return ONLY valid JSON with keys: face_shape (Oval/Round/Square/Heart/Diamond/Oblong), hair_texture (Straight/Wavy/Curly/Coily), hair_density (Thin/Medium/Thick).',
                    ],
                    [
                        'type' => 'input_image',
                        'image_url' => 'data:' . $mimeType . ';base64,' . $imageData,
                    ],
                ],
            ],
        ],
        'temperature' => 0.2,
    ];

    $ch = curl_init('https://api.openai.com/v1/responses');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $apiKey,
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
    $outputText = $data['output_text'] ?? '';
    $json = json_decode((string)$outputText, true);

    if (!is_array($json)) {
        return [];
    }

    return $json;
}

try {
    $pdo = get_db_connection();

    $uploadDir = __DIR__ . '/../uploads/kiosk';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0775, true);
    }

    $fileInfo = pathinfo((string)$_FILES['image']['name']);
    $extension = strtolower($fileInfo['extension'] ?? 'jpg');
    $safeExtension = in_array($extension, ['jpg', 'jpeg', 'png'], true) ? $extension : 'jpg';
    $filename = 'kiosk_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $safeExtension;
    $targetPath = $uploadDir . '/' . $filename;

    if (!move_uploaded_file($_FILES['image']['tmp_name'], $targetPath)) {
        json_response(['error' => 'Failed to store image'], 500);
    }

    $baseUrl = getenv('PUBLIC_BASE_URL') ?: '';
    $publicUrl = $baseUrl !== ''
        ? rtrim($baseUrl, '/') . '/uploads/kiosk/' . $filename
        : '/uploads/kiosk/' . $filename;

    if ($provider === 'openai') {
        $analysis = analyze_with_openai($apiKey, $targetPath, $_FILES['image']['type'] ?? 'image/jpeg');
        $faceShape = normalize_face_shape((string)($analysis['face_shape'] ?? $faceShape));
        $hairTexture = normalize_hair_texture((string)($analysis['hair_texture'] ?? $hairTexture));
        $hairDensity = normalize_hair_density((string)($analysis['hair_density'] ?? $hairDensity));
    }

    $query =
        'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                hv.confidence_score, hs.style_name, hs.style_code
         FROM hairstyle_variants hv
         JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
         WHERE hs.is_active = 1
           AND (:face_shape = \'\' OR hv.face_shape = :face_shape)
           AND (:hair_texture = \'\' OR hv.hair_texture = :hair_texture)
         ORDER BY hv.confidence_score DESC, hs.style_name ASC
         LIMIT 5';
    $stmt = $pdo->prepare($query);
    $stmt->execute([
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
    ]);

    $variants = $stmt->fetchAll();

    $sessionId = bin2hex(random_bytes(16));
    $expiresAt = (new DateTimeImmutable('+2 hours'))->format('Y-m-d H:i:s');

    $sessionStmt = $pdo->prepare(
        'INSERT INTO kiosk_sessions (session_id, original_image_url, face_shape, hair_texture, hair_density, expires_at, is_processed)
         VALUES (:session_id, :original_image_url, :face_shape, :hair_texture, :hair_density, :expires_at, :is_processed)'
    );
    $sessionStmt->execute([
        ':session_id' => $sessionId,
        ':original_image_url' => $publicUrl,
        ':face_shape' => $faceShape !== '' ? $faceShape : null,
        ':hair_texture' => $hairTexture !== '' ? $hairTexture : null,
        ':hair_density' => $hairDensity !== '' ? $hairDensity : null,
        ':expires_at' => $expiresAt,
        ':is_processed' => 1,
    ]);

    $recStmt = $pdo->prepare(
        'INSERT INTO kiosk_recommendations (session_id, variant_id, rank_position, match_score)
         VALUES (:session_id, :variant_id, :rank_position, :match_score)'
    );

    $rank = 1;
    foreach ($variants as $row) {
        $recStmt->execute([
            ':session_id' => $sessionId,
            ':variant_id' => (int)$row['variant_id'],
            ':rank_position' => $rank,
            ':match_score' => (float)$row['confidence_score'],
        ]);
        $rank++;
    }

    json_response([
        'message' => 'Scan received',
        'sessionID' => $sessionId,
        'imageUrl' => $publicUrl,
        'faceShape' => $faceShape,
        'hairTexture' => $hairTexture,
        'hairDensity' => $hairDensity,
        'recommendations' => $variants,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
