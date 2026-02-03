<?php
// Favorites API (listByUser)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['listByUser', 'add', 'remove', 'status'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    $userID = (int)($input['userID'] ?? 0);
    if ($userID <= 0) {
        json_response(['error' => 'Invalid userID'], 422);
    }

    if ($action === 'listByUser') {
        $stmt = $pdo->prepare(
            'SELECT uf.favorite_id, hv.variant_id, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hv.face_shape, hv.hair_texture, hs.style_name, hs.description
             FROM user_favorites uf
             JOIN hairstyle_variants hv ON uf.variant_id = hv.variant_id
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE uf.user_id = :user_id
             ORDER BY uf.created_at DESC'
        );
        $stmt->execute([':user_id' => $userID]);

        json_response(['favorites' => $stmt->fetchAll()]);
    }

    $variantID = (int)($input['variantID'] ?? 0);
    if ($variantID <= 0) {
        json_response(['error' => 'Invalid variantID'], 422);
    }

    if ($action === 'status') {
        $stmt = $pdo->prepare(
            'SELECT uf.favorite_id
             FROM user_favorites uf
             WHERE uf.user_id = :user_id AND uf.variant_id = :variant_id AND uf.barber_id IS NULL
             LIMIT 1'
        );
        $stmt->execute([':user_id' => $userID, ':variant_id' => $variantID]);
        $row = $stmt->fetch();
        json_response(['isFavorite' => $row ? true : false, 'favoriteID' => $row['favorite_id'] ?? null]);
    }

    if ($action === 'add') {
        $checkStmt = $pdo->prepare(
            'SELECT uf.favorite_id
             FROM user_favorites uf
             WHERE uf.user_id = :user_id AND uf.variant_id = :variant_id AND uf.barber_id IS NULL
             LIMIT 1'
        );
        $checkStmt->execute([':user_id' => $userID, ':variant_id' => $variantID]);
        $existing = $checkStmt->fetch();
        if ($existing) {
            json_response(['message' => 'Already saved', 'favoriteID' => $existing['favorite_id']]);
        }

        $insertStmt = $pdo->prepare(
            'INSERT INTO user_favorites (user_id, variant_id, barber_id)
             VALUES (:user_id, :variant_id, NULL)'
        );
        $insertStmt->execute([':user_id' => $userID, ':variant_id' => $variantID]);
        json_response(['message' => 'Saved', 'favoriteID' => (int)$pdo->lastInsertId()], 201);
    }

    if ($action === 'remove') {
        $deleteStmt = $pdo->prepare(
            'DELETE FROM user_favorites
             WHERE user_id = :user_id AND variant_id = :variant_id AND barber_id IS NULL'
        );
        $deleteStmt->execute([':user_id' => $userID, ':variant_id' => $variantID]);
        json_response(['message' => 'Removed']);
    }
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
