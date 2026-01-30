<?php
// Haircuts API (list + variants + create)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['list', 'listByFaceShape', 'create'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'list') {
        $stmt = $pdo->prepare('SELECT haircutID, haircutName, faceShape, imagePath, isActive FROM haircuts WHERE isActive = 1 ORDER BY haircutName');
        $stmt->execute();
        json_response(['haircuts' => $stmt->fetchAll()]);
    }

    if ($action === 'listByFaceShape') {
        $faceShape = trim((string)($input['faceShape'] ?? ''));

        $stmt = $pdo->prepare(
            'SELECT haircutID, haircutName, faceShape, imagePath, isActive
             FROM haircuts
             WHERE isActive = 1 AND (:faceShape = "" OR faceShape = :faceShape OR faceShape IS NULL)
             ORDER BY haircutName'
        );
        $stmt->execute([
            ':faceShape' => $faceShape,
        ]);

        json_response(['haircuts' => $stmt->fetchAll()]);
    }

    if ($action === 'create') {
        // TODO: enforce admin role
        $haircutName = trim((string)($input['haircutName'] ?? ''));
        $faceShape = trim((string)($input['faceShape'] ?? ''));
        $imagePath = trim((string)($input['imagePath'] ?? ''));
        $isActive = isset($input['isActive']) ? (int)$input['isActive'] : 1;

        if ($haircutName === '') {
            json_response(['error' => 'haircutName is required'], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO haircuts (haircutName, faceShape, imagePath, isActive)
             VALUES (:haircutName, :faceShape, :imagePath, :isActive)'
        );
        $stmt->execute([
            ':haircutName' => $haircutName,
            ':faceShape' => $faceShape !== '' ? $faceShape : null,
            ':imagePath' => $imagePath !== '' ? $imagePath : null,
            ':isActive' => $isActive,
        ]);

        json_response(['message' => 'Haircut created', 'haircutID' => (int)$pdo->lastInsertId()], 201);
    }
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
