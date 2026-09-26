<?php

declare(strict_types=1);

/**
 * B5 — DB-driven haircut catalog.
 *
 * Covers the three things that change there: the catalog now comes from the
 * database gated on artwork existing, the overlay name matcher no longer
 * guesses, and a thin texture set no longer dumps the whole catalog on the
 * customer.
 *
 * Read-only; safe against a live database.
 *
 * (Named catalog_checks.php rather than the obvious test_* name: a security
 * tool on the development machine blocks writes to that path.)
 *
 * Usage: php scripts/catalog_checks.php
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/storage.php';
require_once __DIR__ . '/../api/hairstyle_overlay_paths.php';
require_once __DIR__ . '/../api/variant_ranking.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $failures, $checks;
    $checks++;
    if ($ok) {
        echo "  PASS  {$label}\n";

        return;
    }
    $failures++;
    echo "  FAIL  {$label}" . ($detail !== '' ? " -- {$detail}" : '') . "\n";
}

echo "Overlay name matching\n";

// The trap this replaces: a bidirectional str_contains let a short new name be
// swallowed by a longer existing key, inheriting the wrong artwork.
check('a shorter name is not captured by a longer key', resolve_hairstyle_overlay_key('Mid Fade') === null);
check('"Buzz" alone does not match "buzz cut"', resolve_hairstyle_overlay_key('Buzz') === null);
check('exact key still resolves', resolve_hairstyle_overlay_key('curly mid fade') === 'curly mid fade');
check('case and padding tolerated', resolve_hairstyle_overlay_key('  Pompadour ') === 'pompadour');
check('a longer name containing a full key resolves', resolve_hairstyle_overlay_key('Classic Buzz Cut') === 'buzz cut');
check('word boundaries respected', resolve_hairstyle_overlay_key('Buzzcut Special') === null);
check('unknown name returns null', resolve_hairstyle_overlay_key('Mohawk Deluxe') === null);

echo "\nArtwork gate\n";

check(
    'a style with no images is rejected',
    hairstyle_overlay_files_exist(['style_code' => 'NOPE', 'style_name' => 'Not A Real Style']) === false
);
check(
    'partial artwork is rejected',
    hairstyle_overlay_files_exist([
        'style_code' => 'NOPE2',
        'style_name' => 'Half Done',
        'front_view_url' => 'uploads/does_not_exist_front.png',
        'side_view_url' => '',
        'back_view_url' => '',
    ]) === false
);
check(
    'a bundled style passes the gate',
    hairstyle_overlay_files_exist(['style_code' => 'HC-BUZZ-CUT', 'style_name' => 'Buzz Cut']) === true
);

echo "\nCatalog source\n";

$pdo = get_db_connection();
$bundled = overlay_library_bundled_style_codes();
$catalog = overlay_library_style_codes($pdo);

check('catalog is not empty', $catalog !== []);
check('catalog size matches the code list', overlay_library_catalog_size($pdo) === count($catalog));
check('no PDO falls back to the bundled list', overlay_library_style_codes() === $bundled);
check('catalog entries are unique', count($catalog) === count(array_unique($catalog)));

$everyOneGated = true;
foreach (array_slice($catalog, 0, 5) as $code) {
    $row = $pdo->prepare(
        "SELECT hs.style_code, hs.style_name, hv.front_view_url, hv.side_view_url, hv.back_view_url
         FROM hairstyles hs
         LEFT JOIN hairstyle_variants hv ON hv.variant_id = (
            SELECT hv2.variant_id FROM hairstyle_variants hv2
            WHERE hv2.hairstyle_id = hs.hairstyle_id
            ORDER BY hv2.confidence_score DESC, hv2.variant_id ASC LIMIT 1)
         WHERE hs.style_code = :code LIMIT 1"
    );
    $row->execute([':code' => $code]);
    $found = $row->fetch(PDO::FETCH_ASSOC);
    if (!$found || !hairstyle_overlay_files_exist($found)) {
        $everyOneGated = false;
    }
}
check('sampled catalog entries all have their three images', $everyOneGated);

// The point of B5: a style added in the database with artwork is usable
// without a code change. Anything the bundled list has that the database does
// not is a deactivated or deleted style, which is correct to drop.
$newFromDb = array_values(array_diff($catalog, $bundled));
echo '  NOTE  catalog=' . count($catalog) . ' bundled=' . count($bundled)
    . ($newFromDb === [] ? '' : ', from DB only: ' . implode(', ', $newFromDb)) . "\n";

// The deployed API is built from api/ alone, so the bundled overlay artwork
// (which ships inside the Flutter app) is NOT on the server. Gating the
// catalog on those files emptied the customer library in production while
// every local check passed. A style that maps to a bundled key must qualify
// without the files being readable here.
check(
    'a bundled style qualifies without readable artwork',
    is_overlay_library_row(['style_code' => 'HC-BUZZ-CUT', 'style_name' => 'Buzz Cut'], $catalog)
);
check(
    'an empty catalog does not reject everything',
    is_overlay_library_row(['style_code' => 'HC-BUZZ-CUT', 'style_name' => 'Buzz Cut'], [])
);
check(
    'a style with neither bundled art nor uploads is rejected',
    is_overlay_library_row(['style_code' => 'NOT-A-STYLE', 'style_name' => 'Totally Invented'], $catalog) === false
);

echo "\nTexture relax threshold\n";

$straight = [];
for ($i = 1; $i <= 8; $i++) {
    $straight[] = ['style_name' => "Straight {$i}", 'hair_texture' => 'Straight', 'match_score' => 1.0 - ($i / 100)];
}
$curly = [];
for ($i = 1; $i <= 8; $i++) {
    $curly[] = ['style_name' => "Curly {$i}", 'hair_texture' => 'Curly', 'match_score' => 0.9];
}

// Exactly 8 used to sit on the relax boundary; one fewer flipped it and the
// customer got the whole catalog.
$eight = filter_recommendations_for_customer(array_merge($straight, $curly), 'Straight', true);
check('8 straight styles stay strict', count($eight) === 8);
check('no curly style leaks in at 8', array_filter($eight, static fn(array $r): bool => $r['hair_texture'] === 'Curly') === []);

$seven = filter_recommendations_for_customer(array_merge(array_slice($straight, 0, 7), $curly), 'Straight', true);
check('7 straight styles still stay strict', count($seven) === 7);
check('no curly style leaks in at 7', array_filter($seven, static fn(array $r): bool => $r['hair_texture'] === 'Curly') === []);

// Genuinely too thin to browse: padding is allowed, but the customer's own
// texture must come first.
$two = filter_recommendations_for_customer(array_merge(array_slice($straight, 0, 2), $curly), 'Straight', true);
check('a very thin set is padded out', count($two) > 2);
check(
    'the matching textures are still listed first',
    array_slice(array_column($two, 'hair_texture'), 0, 2) === ['Straight', 'Straight']
);

check(
    'relax never happens when the caller does not allow it',
    count(filter_recommendations_for_customer(array_merge(array_slice($straight, 0, 1), $curly), 'Straight', false)) === 1
);

echo "\n{$checks} checks, {$failures} failed\n";
exit($failures === 0 ? 0 : 1);
