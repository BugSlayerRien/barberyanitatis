<?php
require_once __DIR__ . '/../api/db.php';

$pdo = get_db_connection();
$total = (int)$pdo->query(
    'SELECT COUNT(*) FROM hairstyle_variants hv
     JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
     WHERE hs.is_active = TRUE'
)->fetchColumn();

$stmt = $pdo->prepare(
    'SELECT COUNT(DISTINCT hv.variant_id)
     FROM hairstyle_variants hv
     JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
     WHERE hs.is_active = TRUE
       AND (
            LOWER(hv.face_shape) = LOWER(:face)
            OR hv.face_shape IS NULL
            OR hv.face_shape = \'\'
       )
       AND (
            LOWER(hv.hair_texture) = LOWER(:texture)
            OR hv.hair_texture IS NULL
            OR hv.hair_texture = \'\'
       )'
);
$stmt->execute([':face' => 'Oblong', ':texture' => 'Straight']);
$matched = (int)$stmt->fetchColumn();

echo "active_variants={$total}\n";
echo "oblong_straight_matched={$matched}\n";

$rows = $pdo->query(
    "SELECT hs.style_name, hv.variant_id, hv.face_shape, hv.hair_texture
     FROM hairstyle_variants hv
     JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
     WHERE hs.is_active = TRUE
     ORDER BY hs.style_name
     LIMIT 30"
)->fetchAll(PDO::FETCH_ASSOC);

foreach ($rows as $row) {
    echo "{$row['variant_id']}\t{$row['style_name']}\t{$row['face_shape']}\t{$row['hair_texture']}\n";
}
