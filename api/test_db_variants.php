<?php
// Database variants check
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();
    
    // Total variants
    $stmt = $pdo->query('SELECT COUNT(*) as cnt FROM hairstyle_variants');
    $total = $stmt->fetch()['cnt'];
    
    // Active hairstyles
    $stmt = $pdo->query('SELECT COUNT(*) as cnt FROM hairstyles WHERE is_active = TRUE');
    $active = $stmt->fetch()['cnt'];
    
    // Variants for Oval face
    $stmt = $pdo->prepare('SELECT COUNT(*) as cnt FROM hairstyle_variants hv JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id WHERE hs.is_active = TRUE AND (LOWER(hv.face_shape) = ? OR hv.face_shape IS NULL)');
    $stmt->execute(['oval']);
    $oval = $stmt->fetch()['cnt'];
    
    // Variants for Straight texture
    $stmt = $pdo->prepare('SELECT COUNT(*) as cnt FROM hairstyle_variants hv JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id WHERE hs.is_active = TRUE AND (LOWER(hv.hair_texture) = ? OR hv.hair_texture IS NULL)');
    $stmt->execute(['straight']);
    $straight = $stmt->fetch()['cnt'];
    
    // Variants for both Oval AND Straight
    $stmt = $pdo->prepare('SELECT COUNT(*) as cnt FROM hairstyle_variants hv JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id WHERE hs.is_active = TRUE AND (LOWER(hv.face_shape) = ? OR hv.face_shape IS NULL) AND (LOWER(hv.hair_texture) = ? OR hv.hair_texture IS NULL)');
    $stmt->execute(['oval', 'straight']);
    $both = $stmt->fetch()['cnt'];
    
    echo "=== Database Variant Stats ===\n";
    echo "Total variants: $total\n";
    echo "Active hairstyles: $active\n";
    echo "Variants for Oval face (or null): $oval\n";
    echo "Variants for Straight texture (or null): $straight\n";
    echo "Variants for both Oval AND Straight: $both\n\n";
    
    // Sample some variants
    echo "Sample variants:\n";
    $stmt = $pdo->query('SELECT hv.variant_id, hs.style_name, hv.face_shape, hv.hair_texture FROM hairstyle_variants hv JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id WHERE hs.is_active = TRUE LIMIT 10');
    foreach ($stmt->fetchAll() as $row) {
        echo "  - " . $row['style_name'] . " | Face: " . ($row['face_shape'] ?? 'NULL') . " | Texture: " . ($row['hair_texture'] ?? 'NULL') . "\n";
    }
    
} catch (Exception $e) {
    echo 'Error: ' . $e->getMessage();
}
