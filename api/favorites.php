<?php
// Favorites API (listByUser)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if ($action !== 'listByUser') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    $userID = (int)($input['userID'] ?? 0);
    if ($userID <= 0) {
        json_response(['error' => 'Invalid userID'], 422);
    }

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
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
