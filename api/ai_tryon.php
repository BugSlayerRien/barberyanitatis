<?php
// AI Try-on API (library-based; returns variants for a selected haircut)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$haircutID = (int)($input['haircutID'] ?? 0);
$faceShape = trim((string)($input['faceShape'] ?? ''));
$hairType = trim((string)($input['hairType'] ?? ''));

if ($haircutID <= 0) {
    json_response(['error' => 'Invalid haircutID'], 422);
}

try {
    $pdo = get_db_connection();

    $stmt = $pdo->prepare(
        'SELECT variantID, haircutID, faceShape, hairType, imagePath
         FROM hairstyleVariants
         WHERE haircutID = :haircutID
           AND (:faceShape = "" OR faceShape = :faceShape)
           AND (:hairType = "" OR hairType = :hairType)
         ORDER BY variantID DESC
         LIMIT 12'
    );
    $stmt->execute([
        ':haircutID' => $haircutID,
        ':faceShape' => $faceShape,
        ':hairType' => $hairType,
    ]);

    $variants = $stmt->fetchAll();

    if (count($variants) === 0) {
        json_response([
            'message' => 'No variants found. Populate hairstyleVariants or enable AI generation.',
            'variants' => [],
        ]);
    }

    json_response([
        'message' => 'Variants found',
        'variants' => $variants,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
