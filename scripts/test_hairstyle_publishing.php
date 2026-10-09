<?php

declare(strict_types=1);

/**
 * Guards the path from "a barber submits a haircut" to "a customer sees it".
 *
 * A style added through the portal used to write one hairstyles row and stop,
 * while four gates -- the overlay catalog, the AI prompt table, a Dart registry
 * and the Flutter asset bundle -- could only be satisfied by editing source and
 * shipping a new API deploy and a new app build. The panel added a haircut,
 * watched it save, and watched it never appear.
 *
 * These checks assert the two gates that are now data: a stored prompt makes a
 * style previewable, and review status decides whether customers see it.
 *
 * Every write runs inside a transaction that is always rolled back.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/hairstyle_authoring.php';
require_once __DIR__ . '/../api/replicate_helper.php';
require_once __DIR__ . '/../api/variant_ranking.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $condition): void
{
    global $failures, $checks;
    $checks++;
    if ($condition) {
        echo "  PASS  {$label}\n";
        return;
    }
    $failures++;
    echo "  FAIL  {$label}\n";
}

echo "Hairstyle publishing checks\n";

$pdo = get_db_connection();
ensure_hairstyle_authoring_columns($pdo);
$codes = overlay_library_style_codes($pdo);

// --- the composer ------------------------------------------------------------
$prompt = compose_hairstyle_prompt('Pineapple', [
    'sides' => 'sides and back clipped short with a clean taper from the temple down',
    'guards' => 'a #1 blending to a #3',
    'top' => 'four inches left on top gathered upward into a tall rounded shape',
    'back' => 'the back tapered short to the nape with nothing over the collar',
]);
check('the composer names the style', str_starts_with($prompt, 'pineapple:'));
check('the composer states the back', preg_match('/\b(back|nape|collar)\b/i', $prompt) === 1);
check('the composer keeps the barber\'s words', str_contains($prompt, 'tall rounded shape'));

$sparse = compose_hairstyle_prompt('Test', ['sides' => 'faded short', 'top' => 'two inches']);
// The back is the field a model invents length in when nothing is said, so the
// composer supplies a default rather than leaving it open.
check('a back clause appears even when the barber omitted it',
    preg_match('/\b(back|nape|collar)\b/i', $sparse) === 1);

// --- a stored prompt is enough to generate -----------------------------------
$brief = replicate_style_brief('Totally Made Up Style', 'HC-NOPE', 1, '', false, $prompt, 2);
check('a style absent from the built-in table can still be briefed', $brief['ok'] === true);
check('and the brief uses the stored text', str_contains($brief['basePrompt'], 'tall rounded shape'));
check('and honours its stored minimum length', $brief['needsMoreLength'] === true);

$noPrompt = replicate_style_brief('Totally Made Up Style', 'HC-NOPE', 1, '', false, null, null);
check('without a stored prompt it still refuses', $noPrompt['ok'] === false);
check('and the error tells the admin where to add one',
    str_contains($noPrompt['error'], 'admin portal'));

// --- readiness ---------------------------------------------------------------
$completeStyle = [
    'style_code' => 'HC-PINEAPPLE',
    'ai_prompt' => $prompt,
];
$completeVariants = [[
    'hair_texture' => 'Curly',
    'front_view_url' => 'uploads/hairstyles/a.jpg',
    'side_view_url' => 'uploads/hairstyles/b.jpg',
    'back_view_url' => 'uploads/hairstyles/c.jpg',
    'barber_instructions' => 'Taper the sides, leave the top long.',
]];
check('a complete style has no blockers',
    hairstyle_readiness_problems($completeStyle, $completeVariants) === []);

check('no variants is a blocker',
    hairstyle_readiness_problems($completeStyle, []) !== []);
check('no prompt is a blocker',
    hairstyle_readiness_problems(['style_code' => 'HC-X', 'ai_prompt' => ''], $completeVariants) !== []);

$malformed = hairstyle_readiness_problems(['style_code' => 'HC-M-F-', 'ai_prompt' => $prompt], $completeVariants);
// The old generator produced exactly this shape by stripping lowercase letters.
check('a mangled style code is a blocker', $malformed !== []);

$missingImage = $completeVariants;
$missingImage[0]['back_view_url'] = '';
check('a missing image is a blocker',
    hairstyle_readiness_problems($completeStyle, $missingImage) !== []);

$noInstructions = $completeVariants;
$noInstructions[0]['barber_instructions'] = '';
check('missing barber instructions is a blocker',
    hairstyle_readiness_problems($completeStyle, $noInstructions) !== []);

// --- review status decides visibility ----------------------------------------
$subject = $pdo->query(
    "SELECT hairstyle_id, style_name FROM hairstyles
     WHERE is_active = TRUE AND COALESCE(review_status,'Published') = 'Published'
     ORDER BY hairstyle_id DESC LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);
check('a published style exists to test against', (bool)$subject);

if ($subject) {
    $id = (int)$subject['hairstyle_id'];
    $name = (string)$subject['style_name'];

    $visible = static function (PDO $pdo, string $name): bool {
        $rows = $pdo->query(
            "SELECT hs.style_name
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
             WHERE hs.is_active = TRUE
               AND COALESCE(hs.review_status, 'Published') = 'Published'"
        )->fetchAll(PDO::FETCH_COLUMN);

        return in_array($name, $rows, true);
    };

    $pdo->beginTransaction();
    try {
        check('it is visible while published', $visible($pdo, $name));

        $pdo->prepare("UPDATE hairstyles SET review_status = 'PendingReview' WHERE hairstyle_id = :id")
            ->execute([':id' => $id]);
        check('a pending submission is hidden from customers', !$visible($pdo, $name));

        $pdo->prepare("UPDATE hairstyles SET review_status = 'Rejected' WHERE hairstyle_id = :id")
            ->execute([':id' => $id]);
        check('a rejected submission is hidden too', !$visible($pdo, $name));

        $pdo->prepare("UPDATE hairstyles SET review_status = 'Published' WHERE hairstyle_id = :id")
            ->execute([':id' => $id]);
        check('publishing brings it back', $visible($pdo, $name));
    } finally {
        $pdo->rollBack();
    }

    check('the rollback left it published', $visible($pdo, $name));
}

// --- uploaded artwork is not overwritten -------------------------------------
$uploaded = apply_hairstyle_overlay_paths([
    'style_name' => 'Buzz Cut',
    'front_view_url' => 'uploads/hairstyles/mine_front.jpg',
    'side_view_url' => 'uploads/hairstyles/mine_side.jpg',
    'back_view_url' => 'uploads/hairstyles/mine_back.jpg',
]);
// A style whose name fuzzy-matches a bundled key used to lose its uploads to
// that key's artwork, so the admin's photo silently became someone else's cut.
check('an uploaded photo survives the overlay mapping',
    $uploaded['front_view_url'] === 'uploads/hairstyles/mine_front.jpg');

$bundled = apply_hairstyle_overlay_paths(['style_name' => 'Buzz Cut']);
check('a style with no artwork still gets the bundled set',
    str_starts_with((string)($bundled['front_view_url'] ?? ''), 'assets/'));

// --- a described style reaches the library without photographs ---------------
// This is the gate the panel's own addition died on. Its row saved, its prompt
// was there, and the catalog still rejected it because three images did not
// resolve -- so it never appeared in the library at all.
$described = [
    'style_code' => 'HC-TEST-DESCRIBED',
    'style_name' => 'Totally Made Up Style',
    'ai_prompt' => $prompt,
    'front_view_url' => '',
    'side_view_url' => '',
    'back_view_url' => '',
];
check('a described style with no artwork is previewable',
    hairstyle_is_previewable_without_artwork($described));
check('and the library admits it', is_overlay_library_row($described, $codes ?? []));

$bare = $described;
$bare['ai_prompt'] = '';
check('a style with neither prompt nor artwork is still rejected',
    !is_overlay_library_row($bare, ['HC-SOMETHING-ELSE']));

// Rows are stripped of the prompt once the flag is derived, because the
// customer has no business reading it. Every later stage reads the flag.
$annotated = $described;
unset($annotated['ai_prompt']);
$annotated['previewable'] = true;
check('previewability survives the prompt being stripped',
    hairstyle_is_previewable_without_artwork($annotated));
$annotatedFalse = $annotated;
$annotatedFalse['previewable'] = false;
check('and a false flag is respected rather than re-derived',
    !hairstyle_is_previewable_without_artwork($annotatedFalse));

// --- the catalog cache must not outlive a publish ----------------------------
require_once __DIR__ . '/../api/schema_cache.php';
$cachePath = schema_cache_marker_path('overlay_library_catalog') . '.json';
schema_cache_put_json('overlay_library_catalog', ['codes' => ['HC-STALE']]);
check('the catalog can be cached', is_file($cachePath));
schema_cache_invalidate('overlay_library_catalog');
check('and invalidating it removes the cache', !is_file($cachePath));

// --- uploads for a new style must not pose as bundled assets -----------------
// handle_upload_overlay() used to write assets/images/overlays/<new folder>/
// and store that as the URL. Anything starting with assets/ is a *bundled*
// Flutter asset: a folder created on the server is in neither the APK nor
// pubspec.yaml, so the upload succeeded and the picture could never load.
check('an unmapped style has no bundled overlay slot',
    overlay_target_for_view('Totally Made Up Style', 'front', 'HC-TEST-DESCRIBED') === null);
check('a bundled style still has one',
    overlay_target_for_view('Buzz Cut', 'front', 'HC-BUZZ-CUT') !== null);

$uploadSource = (string)file_get_contents(__DIR__ . '/../api/admin_hairstyles.php');
check('the upload handler writes unmapped styles to network storage',
    str_contains($uploadSource, 'uploads/hairstyles/style_%d_%s_%d.%s'));
check('and it accepts a photograph, not only a cut-out PNG',
    str_contains($uploadSource, 'image/jpeg'));

// --- the portal can see the review workflow ----------------------------------
// It could not: the list query selected neither review_status nor the prompt,
// so a barber could submit a style and the owner had no row to act on.
check('the admin list exposes review status',
    str_contains($uploadSource, 'AS review_status'));
check('and whether a prompt exists', str_contains($uploadSource, 'AS has_prompt'));
check('and who submitted it', str_contains($uploadSource, 'AS authored_by_name'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
