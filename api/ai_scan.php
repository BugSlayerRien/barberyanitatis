<?php
// AI Face Scan API (image upload -> hairstyle variants)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

if (!isset($_FILES['image']) || $_FILES['image']['error'] !== UPLOAD_ERR_OK) {
    json_response(['error' => 'Image is required'], 422);
}

$userID = isset($_POST['userID']) ? (int)$_POST['userID'] : 0;
$faceShape = isset($_POST['faceShape']) ? trim((string)$_POST['faceShape']) : '';
$hairType = isset($_POST['hairType']) ? trim((string)$_POST['hairType']) : '';

$provider = getenv('AI_PROVIDER') ?: '';
$apiKey = getenv('AI_API_KEY') ?: '';

if ($provider === '' || $apiKey === '') {
    json_response(['error' => 'AI provider not configured'], 503);
}

// Placeholder: integrate external AI provider here.
// Suggested flow:
// 1) Upload image to provider for face + hair analysis.
// 2) Receive faceShape + hairType.
// 3) Query hairstyleVariants by (haircutID, faceShape, hairType).
// 4) Return a list of imagePath for client display.

try {
    $pdo = get_db_connection();

    $query = 'SELECT hv.variantID, hv.imagePath, h.haircutName
              FROM hairstyleVariants hv
              JOIN haircuts h ON hv.haircutID = h.haircutID
              WHERE (hv.faceShape = :faceShape OR :faceShape = \'\')
                AND (hv.hairType = :hairType OR :hairType = \'\')
              LIMIT 12';
    $stmt = $pdo->prepare($query);
    $stmt->execute([
        ':faceShape' => $faceShape,
        ':hairType' => $hairType,
    ]);

    $variants = $stmt->fetchAll();

    json_response([
        'message' => 'Scan received',
        'userID' => $userID,
        'faceShape' => $faceShape,
        'hairType' => $hairType,
        'variants' => $variants,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
