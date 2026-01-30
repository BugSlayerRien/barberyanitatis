<?php
// Haircuts API (list + variants + create)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['list', 'variants', 'create'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'list') {
        $stmt = $pdo->prepare('SELECT haircutID, haircutName, description, referenceImage FROM haircuts ORDER BY haircutName');
        $stmt->execute();
        json_response(['haircuts' => $stmt->fetchAll()]);
    }

    if ($action === 'variants') {
        $haircutID = (int)($input['haircutID'] ?? 0);
        $faceShape = trim((string)($input['faceShape'] ?? ''));
        $hairType = trim((string)($input['hairType'] ?? ''));

        if ($haircutID <= 0) {
            json_response(['error' => 'Invalid haircutID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT variantID, haircutID, faceShape, hairType, imagePath
             FROM hairstyleVariants
             WHERE haircutID = :haircutID
               AND (:faceShape = "" OR faceShape = :faceShape)
               AND (:hairType = "" OR hairType = :hairType)
             ORDER BY variantID DESC'
        );
        $stmt->execute([
            ':haircutID' => $haircutID,
            ':faceShape' => $faceShape,
            ':hairType' => $hairType,
        ]);

        json_response(['variants' => $stmt->fetchAll()]);
    }

    if ($action === 'create') {
        // TODO: enforce admin role
        $haircutName = trim((string)($input['haircutName'] ?? ''));
        $description = trim((string)($input['description'] ?? ''));
        $referenceImage = trim((string)($input['referenceImage'] ?? ''));

        if ($haircutName === '') {
            json_response(['error' => 'haircutName is required'], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO haircuts (haircutName, description, referenceImage)
             VALUES (:haircutName, :description, :referenceImage)'
        );
        $stmt->execute([
            ':haircutName' => $haircutName,
            ':description' => $description !== '' ? $description : null,
            ':referenceImage' => $referenceImage !== '' ? $referenceImage : null,
        ]);

        json_response(['message' => 'Haircut created', 'haircutID' => (int)$pdo->lastInsertId()], 201);
    }
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
