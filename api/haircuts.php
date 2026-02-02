<?php
// Hairstyles API (list + variants + create)

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
        $stmt = $pdo->prepare(
            'SELECT hairstyle_id, style_code, style_name, description, gender, difficulty, maintenance, is_active
             FROM hairstyles
             WHERE is_active = 1
             ORDER BY style_name'
        );
        $stmt->execute();
        json_response(['hairstyles' => $stmt->fetchAll()]);
    }

    if ($action === 'listByFaceShape') {
        $faceShape = trim((string)($input['faceShape'] ?? ''));

        $hairTexture = trim((string)($input['hairTexture'] ?? ''));

                $stmt = $pdo->prepare(
                        'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                                        hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes,
                                        hs.style_name, hs.style_code, hs.description
                         FROM hairstyle_variants hv
                         JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
                         WHERE hs.is_active = 1
                             AND (:face_shape = "" OR hv.face_shape = :face_shape)
                             AND (:hair_texture = "" OR hv.hair_texture = :hair_texture)
                         ORDER BY hv.confidence_score DESC, hs.style_name'
                );
        $stmt->execute([
            ':face_shape' => $faceShape,
            ':hair_texture' => $hairTexture,
        ]);

        json_response(['variants' => $stmt->fetchAll()]);
    }

    if ($action === 'create') {
        // TODO: enforce admin role
        $styleName = trim((string)($input['styleName'] ?? ''));
        $styleCode = trim((string)($input['styleCode'] ?? ''));
        $description = trim((string)($input['description'] ?? ''));
        $gender = trim((string)($input['gender'] ?? 'Unisex'));
        $difficulty = trim((string)($input['difficulty'] ?? 'Medium'));
        $maintenance = trim((string)($input['maintenance'] ?? 'Medium'));
        $isActive = isset($input['isActive']) ? (int)$input['isActive'] : 1;

        if ($styleName === '' || $styleCode === '') {
            json_response(['error' => 'styleName and styleCode are required'], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, is_active)
             VALUES (:style_code, :style_name, :description, :gender, :difficulty, :maintenance, :is_active)'
        );
        $stmt->execute([
            ':style_code' => $styleCode,
            ':style_name' => $styleName,
            ':description' => $description !== '' ? $description : null,
            ':gender' => $gender !== '' ? $gender : 'Unisex',
            ':difficulty' => $difficulty !== '' ? $difficulty : 'Medium',
            ':maintenance' => $maintenance !== '' ? $maintenance : 'Medium',
            ':is_active' => $isActive,
        ]);

        json_response(['message' => 'Hairstyle created', 'hairstyleID' => (int)$pdo->lastInsertId()], 201);
    }
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
