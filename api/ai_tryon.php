<?php
// AI Try-on API (library-based; returns selected haircut image)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$variantID = (int)($input['variantID'] ?? 0);

if ($variantID <= 0) {
    json_response(['error' => 'Invalid variantID'], 422);
}

try {
    $pdo = get_db_connection();

    $stmt = $pdo->prepare(
        'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes,
                hs.style_name, hs.style_code
         FROM hairstyle_variants hv
         JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
         WHERE hv.variant_id = :variant_id AND hs.is_active = 1'
    );
    $stmt->execute([':variant_id' => $variantID]);
    $variant = $stmt->fetch();

    if (!$variant) {
        json_response([
            'message' => 'Variant not found.',
            'variant' => null,
        ], 404);
    }

    json_response([
        'message' => 'Variant found',
        'variant' => $variant,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
