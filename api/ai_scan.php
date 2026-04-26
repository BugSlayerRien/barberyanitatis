<?php
// AI Face Scan API (live camera feature ranking)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ($_POST['action'] ?? 'rankByFeatures')));

if ($action !== 'rankByFeatures') {
    json_response(['error' => 'Invalid action'], 400);
}

$userID = isset($input['userID']) ? (int)$input['userID'] : (isset($_POST['userID']) ? (int)$_POST['userID'] : 0);
$faceShape = trim((string)($input['faceShape'] ?? ($_POST['faceShape'] ?? '')));
$hairTexture = trim((string)($input['hairTexture'] ?? ($_POST['hairTexture'] ?? '')));
$hairDensity = trim((string)($input['hairDensity'] ?? ($_POST['hairDensity'] ?? '')));

function fetch_live_recommendations(PDO $pdo, string $faceShape, string $hairTexture): array
{
    $query = <<<'SQL'
SELECT
    hv.variant_id,
    hv.face_shape,
    hv.hair_texture,
    hv.front_view_url,
    hv.side_view_url,
    hv.back_view_url,
    hv.confidence_score,
    hv.barber_instructions,
    hv.clipper_sizes,
    hv.styling_products,
    hv.estimated_minutes,
    hs.style_name,
    hs.style_code,
    hs.description,
    (
        hv.confidence_score
        + CASE
            WHEN :face_shape <> '' AND LOWER(hv.face_shape) = LOWER(:face_shape) THEN 0.45
            ELSE 0
          END
        + CASE
            WHEN :hair_texture <> '' AND LOWER(hv.hair_texture) = LOWER(:hair_texture) THEN 0.55
            ELSE 0
          END
        + CASE
            WHEN :hair_texture <> ''
                AND LOWER(:hair_texture) <> 'coily'
                AND (
                    LOWER(hs.style_name) LIKE '%afro%'
                    OR LOWER(hs.style_name) LIKE '%dread%'
                    OR LOWER(hs.style_name) LIKE '%twist%'
                )
            THEN -0.85
            ELSE 0
          END
    ) AS match_score
FROM hairstyle_variants hv
JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE hs.is_active = TRUE
    AND (
        :face_shape = ''
        OR LOWER(hv.face_shape) = LOWER(:face_shape)
        OR hv.face_shape IS NULL
        OR hv.face_shape = ''
    )
    AND (
        :hair_texture = ''
        OR LOWER(hv.hair_texture) = LOWER(:hair_texture)
        OR hv.hair_texture IS NULL
        OR hv.hair_texture = ''
    )
ORDER BY match_score DESC, hv.confidence_score DESC, hs.style_name
LIMIT 24
SQL;

    $stmt = $pdo->prepare($query);
    $stmt->execute([
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
    ]);

    return $stmt->fetchAll();
}

try {
    $pdo = get_db_connection();
    $recommendations = fetch_live_recommendations($pdo, $faceShape, $hairTexture);

    json_response([
        'message' => 'Live recommendations ready',
        'userID' => $userID,
        'faceShape' => $faceShape,
        'hairTexture' => $hairTexture,
        'hairDensity' => $hairDensity,
        'recommendations' => $recommendations,
        'variants' => $recommendations,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
