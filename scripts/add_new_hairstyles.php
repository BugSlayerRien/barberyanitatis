<?php

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';

function upsert_hairstyle(PDO $pdo, string $styleCode, string $styleName, string $description = ''): int
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

function upsert_variant(
    PDO $pdo,
    int $hairstyleId,
    string $faceShape,
    string $hairTexture,
    string $frontUrl,
    string $leftUrl,
    string $rightUrl,
    string $barberInstructions,
    float $confidenceScore = 0.90
): int {
    $stmt = $pdo->prepare(
        'INSERT INTO hairstyle_variants (hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url, barber_instructions, confidence_score)
         VALUES (:hairstyle_id, :face_shape, :hair_texture, :front_view_url, :side_view_url, :back_view_url, :barber_instructions, :confidence_score)
         RETURNING variant_id'
    );

    $stmt->execute([
        ':hairstyle_id' => $hairstyleId,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':front_view_url' => $frontUrl,
        ':side_view_url' => $leftUrl,
        ':back_view_url' => $rightUrl,
        ':barber_instructions' => $barberInstructions,
        ':confidence_score' => $confidenceScore,
    ]);

    return (int)$stmt->fetchColumn();
}

try {
    echo "Loading repository environment and connecting to Supabase..." . PHP_EOL;
    $pdo = get_db_connection();
    $pdo->beginTransaction();

    // Add 4 new hairstyles
    $buzzCut = upsert_hairstyle(
        $pdo,
        'HC-BUZZ-CUT',
        'Buzz Cut',
        'Classic short haircut with uniform clipper size'
    );

    $lowFade = upsert_hairstyle(
        $pdo,
        'HC-LOW-FADE',
        'Low Fade',
        'Low fade with gradual taper'
    );

    $frenchCrop = upsert_hairstyle(
        $pdo,
        'HC-FRENCH-CROP',
        'French Crop',
        'Modern French crop with textured top'
    );

    $blowoutTaper = upsert_hairstyle(
        $pdo,
        'HC-BLOWOUT-TAPER',
        'Blowout Taper',
        'High volume blowout with tapered sides'
    );

    // Add variants for Buzz Cut
    upsert_variant(
        $pdo,
        $buzzCut,
        'Oval',
        'Straight',
        'assets/images/overlays/buzz_cut/buzz_cut_front.png',
        'assets/images/overlays/buzz_cut/buzz_cut_left.png',
        'assets/images/overlays/buzz_cut/buzz_cut_right.png',
        'Keep the cut tight and even with a clean fade line.',
        0.90
    );

    // Add variants for Low Fade
    upsert_variant(
        $pdo,
        $lowFade,
        'Oval',
        'Straight',
        'assets/images/overlays/low_fade/low_fade_front.png',
        'assets/images/overlays/low_fade/low_fade_left.png',
        'assets/images/overlays/low_fade/low_fade_right.png',
        'Blend the fade softly and preserve weight near the top.',
        0.92
    );

    // Add variants for French Crop
    upsert_variant(
        $pdo,
        $frenchCrop,
        'Round',
        'Wavy',
        'assets/images/overlays/french_crop/french_crop_front.png',
        'assets/images/overlays/french_crop/french_crop_left.png',
        'assets/images/overlays/french_crop/french_crop_right.png',
        'Texturize the fringe and keep the edges sharp but natural.',
        0.91
    );

    // Add variants for Blowout Taper
    upsert_variant(
        $pdo,
        $blowoutTaper,
        'Oblong',
        'Straight',
        'assets/images/overlays/blowout_taper/blowout_taper_front.png',
        'assets/images/overlays/blowout_taper/blowout_taper_left.png',
        'assets/images/overlays/blowout_taper/blowout_taper_right.png',
        'Build volume on top and taper the sides cleanly.',
        0.88
    );

    $pdo->commit();

    $counts = [];
    foreach (['hairstyles', 'hairstyle_variants'] as $table) {
        $counts[$table] = (int)$pdo->query('SELECT COUNT(*) FROM ' . $table)->fetchColumn();
    }

    echo json_encode([
        'message' => 'New hairstyles added successfully',
        'hairstyles_added' => ['Buzz Cut', 'Low Fade', 'French Crop', 'Blowout Taper'],
        'counts' => $counts,
    ], JSON_PRETTY_PRINT) . PHP_EOL;
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    fwrite(STDERR, 'Script failed: ' . $e->getMessage() . PHP_EOL);
    exit(1);
}
