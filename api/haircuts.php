<?php
// Haircuts API (list + variants + create)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['list', 'listByFaceShape', 'listLibrary', 'create'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    with_pdo_retry(function (PDO $pdo) use ($input, $action): void {
    $normalizeHaircutRow = static function (array $row): array {
        $styleName = trim((string)($row['style_name'] ?? ''));
        if (strcasecmp($styleName, 'Curly Top Fade') === 0) {
            $row['style_name'] = 'Curly Taper Fade';
        }

        return apply_hairstyle_overlay_paths($row);
    };

    if ($action === 'list') {
        $stmt = $pdo->prepare(
            'SELECT hairstyle_id, style_code, style_name, description, gender, difficulty, maintenance, is_active
             FROM hairstyles
               WHERE is_active = TRUE
             ORDER BY style_name'
        );
        $stmt->execute();
        $haircuts = array_map($normalizeHaircutRow, $stmt->fetchAll());
        json_response(['haircuts' => $haircuts]);
    }

    if ($action === 'listByFaceShape') {
        $faceShape = trim((string)($input['faceShape'] ?? ''));
        $hairTexture = trim((string)($input['hairTexture'] ?? ''));

                $stmt = $pdo->prepare(<<<'SQL'
SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
             hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes,
             hs.style_name, hs.style_code, hs.description, hs.maintenance, hs.difficulty,
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
SQL
                );
                $stmt->execute([
                        ':face_shape' => $faceShape,
                        ':hair_texture' => $hairTexture,
                ]);

        $variants = array_map($normalizeHaircutRow, $stmt->fetchAll());
        json_response(['variants' => $variants]);
    }

    if ($action === 'listLibrary') {
        $stmt = $pdo->prepare(
            'SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description, hs.gender, hs.difficulty, hs.maintenance, hs.is_active,
                    hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes
             FROM hairstyles hs
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = (
                SELECT hv2.variant_id
                FROM hairstyle_variants hv2
                WHERE hv2.hairstyle_id = hs.hairstyle_id
                ORDER BY hv2.confidence_score DESC, hv2.variant_id ASC
                LIMIT 1
             )
                 WHERE hs.is_active = TRUE
             ORDER BY hs.style_name'
        );
        $stmt->execute();
        $hairstyles = array_map($normalizeHaircutRow, $stmt->fetchAll());
        json_response(['hairstyles' => $hairstyles]);
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
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
}
