<?php
// Upsert all overlay-based hairstyles into the database.

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/hairstyle_overlay_paths.php';

function upsert_hairstyle(PDO $pdo, string $styleCode, string $styleName, string $description): int
{
    $stmt = $pdo->prepare(
        'INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, is_active)
         VALUES (:style_code, :style_name, :description, :gender, :difficulty, :maintenance, TRUE)
         ON CONFLICT (style_code)
         DO UPDATE SET
            style_name = EXCLUDED.style_name,
            description = EXCLUDED.description,
            is_active = TRUE
         RETURNING hairstyle_id'
    );
    $stmt->execute([
        ':style_code' => $styleCode,
        ':style_name' => $styleName,
        ':description' => $description,
        ':gender' => 'Unisex',
        ':difficulty' => 'Medium',
        ':maintenance' => 'Medium',
    ]);
    return (int)$stmt->fetchColumn();
}

function upsert_variant(PDO $pdo, int $hairstyleId, string $faceShape, string $hairTexture, array $paths): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO hairstyle_variants
            (hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
             barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score)
         VALUES
            (:hairstyle_id, :face_shape, :hair_texture, :front_view_url, :side_view_url, :back_view_url,
             :barber_instructions, :clipper_sizes, :styling_products, :estimated_minutes, :confidence_score)
         ON CONFLICT (hairstyle_id, face_shape, hair_texture)
         DO UPDATE SET
            front_view_url = EXCLUDED.front_view_url,
            side_view_url = EXCLUDED.side_view_url,
            back_view_url = EXCLUDED.back_view_url,
            confidence_score = EXCLUDED.confidence_score'
    );
    $stmt->execute([
        ':hairstyle_id' => $hairstyleId,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':front_view_url' => $paths['front'],
        ':side_view_url' => $paths['side'],
        ':back_view_url' => $paths['back'],
        ':barber_instructions' => 'Standard finish with clean blend and styled top.',
        ':clipper_sizes' => '0.5, 1, 2',
        ':styling_products' => 'Matte clay, light hold spray',
        ':estimated_minutes' => 40,
        ':confidence_score' => 0.88,
    ]);
}

$catalog = [
    ['HC-BLOWOUT-TAPER', 'Blowout Taper', 'High volume blowout with tapered sides.', 'Straight'],
    ['HC-BUZZ-CUT', 'Buzz Cut', 'Classic short haircut with uniform clipper size.', 'Straight'],
    ['HC-CAESAR', 'Caesar Cut', 'Short fringe with clean sides.', 'Straight'],
    ['HC-CREW', 'Crew Cut', 'Classic crew cut with short sides.', 'Straight'],
    ['HC-CURLY-BURST', 'Curly Burst Fade', 'Curly top with burst fade transition.', 'Curly'],
    ['HC-CURLY-CREW', 'Curly Crew Cut', 'Short curly crew with tapered sides.', 'Curly'],
    ['HC-CURLY-DROP', 'Curly Drop Fade', 'Drop fade with curly texture on top.', 'Curly'],
    ['HC-CURLY-MID', 'Curly Mid Fade', 'Mid fade with defined curly top.', 'Curly'],
    ['HC-CURLY-MULLET', 'Curly Modern Mullet', 'Modern mullet shape with curly texture.', 'Curly'],
    ['HC-CURLY-TAPER', 'Curly Taper Fade', 'Curly taper fade with blended sides.', 'Curly'],
    ['HC-EDGAR', 'Edgar Cut', 'Bold straight fringe with high fade.', 'Straight'],
    ['HC-FRENCH-CROP', 'French Crop', 'Modern French crop with textured top.', 'Wavy'],
    ['HC-LOW-FADE', 'Low Fade', 'Low fade with gradual taper.', 'Straight'],
    ['HC-MESSY-QUIFF', 'Messy Quiff', 'Textured quiff with messy volume.', 'Wavy'],
    ['HC-MODERN-CURTAINS', 'Modern Curtains', 'Center-part curtain bangs with fade.', 'Wavy'],
    ['HC-MODERN-MULLET', 'Modern Mullet', 'Contemporary mullet with textured top.', 'Wavy'],
    ['HC-POMPADOUR', 'Pompadour', 'Classic pompadour with volume and fade.', 'Straight'],
    ['HC-TEXTURED-CROP', 'Textured Crop', 'Textured crop with clean taper.', 'Wavy'],
    ['HC-TWO-BLOCK', 'Two Block', 'K-style two block with longer top.', 'Straight'],
    ['HC-WAVY-BURST', 'Wavy Burst Fade', 'Wavy burst fade with volume.', 'Wavy'],
    ['HC-WAVY-FRINGE', 'Wavy Fringe', 'Wavy fringe with tapered sides.', 'Wavy'],
    ['HC-WAVY-MESSY', 'Wavy Messy Top', 'Messy wavy top with short sides.', 'Wavy'],
    ['HC-WAVY-MOD', 'Wavy Mod Cut', 'Mod-inspired wavy cut.', 'Wavy'],
    ['HC-WAVY-SWEEP', 'Wavy Side Sweep', 'Side-swept wavy style with fade.', 'Wavy'],
];

try {
    $pdo = get_db_connection();
    $pdo->beginTransaction();

    $pathsMap = hairstyle_overlay_paths();
    $seeded = [];

    foreach ($catalog as [$code, $displayName, $description, $texture]) {
        $key = resolve_hairstyle_overlay_key($displayName);
        if ($key === null || !isset($pathsMap[$key])) {
            fwrite(STDERR, "Skipping {$displayName}: no overlay assets mapped.\n");
            continue;
        }

        $hairstyleId = upsert_hairstyle($pdo, $code, $displayName, $description);
        // All three shapes the classifier can return. Square was missing here,
        // so detect_face_shape() could return "square" for a user who then had
        // no variants to recommend at all.
        upsert_variant($pdo, $hairstyleId, 'Oval', $texture, $pathsMap[$key]);
        upsert_variant($pdo, $hairstyleId, 'Round', $texture, $pathsMap[$key]);
        upsert_variant($pdo, $hairstyleId, 'Square', $texture, $pathsMap[$key]);
        $seeded[] = $displayName;
    }

    $pdo->commit();

    echo json_encode([
        'message' => 'Overlay hairstyles seeded',
        'count' => count($seeded),
        'styles' => $seeded,
        'total_hairstyles' => (int)$pdo->query('SELECT COUNT(*) FROM hairstyles WHERE is_active = TRUE')->fetchColumn(),
    ], JSON_PRETTY_PRINT) . PHP_EOL;
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    fwrite(STDERR, 'Seed failed: ' . $e->getMessage() . PHP_EOL);
    exit(1);
}
