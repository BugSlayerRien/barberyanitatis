<?php
// AI Try-on API (library-based; returns selected haircut image)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$haircutID = (int)($input['haircutID'] ?? 0);

if ($haircutID <= 0) {
    json_response(['error' => 'Invalid haircutID'], 422);
}

try {
    $pdo = get_db_connection();

    $stmt = $pdo->prepare(
        'SELECT haircutID, haircutName, faceShape, imagePath, isActive
         FROM haircuts
         WHERE haircutID = :haircutID AND isActive = 1'
    );
    $stmt->execute([':haircutID' => $haircutID]);
    $haircut = $stmt->fetch();

    if (!$haircut) {
        json_response([
            'message' => 'Haircut not found.',
            'haircut' => null,
        ], 404);
    }

    json_response([
        'message' => 'Haircut found',
        'haircut' => $haircut,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
