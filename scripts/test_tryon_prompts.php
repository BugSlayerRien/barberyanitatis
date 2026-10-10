<?php

declare(strict_types=1);

/**
 * Guards the AI try-on style prompts.
 *
 * Seven catalog styles -- Afro Taper, Crew Cut, Curly Fringe, Curly Top Fade,
 * Curly Undercut, Mid Fade and Pompadour -- had no prompt entry and silently
 * rendered as a generic barbers cut, because the resolver fell back to
 * 'barbers_cut' instead of admitting it had no match. Nothing failed, nothing
 * logged; the customer simply got the wrong haircut, and only on the styles
 * they picked second or third.
 *
 * The first check below is the one that would have caught it: every style in
 * the live catalog must resolve to a prompt of its own.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/replicate_helper.php';
require_once __DIR__ . '/../api/hairstyle_authoring.php';

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

echo "AI try-on prompt checks\n";

$prompts = replicate_style_prompts();
$minLengths = replicate_style_min_length();

// --- every catalog style has its own prompt ---------------------------------
$pdo = get_db_connection();
ensure_hairstyle_authoring_columns($pdo);
$catalog = $pdo->query(
    'SELECT DISTINCT style_code, style_name, ai_prompt FROM hairstyles ORDER BY style_name'
)->fetchAll(PDO::FETCH_ASSOC);

check('the catalog is readable', count($catalog) > 0);

$unmatched = [];
$fellBack = [];
$authoredStyles = [];
foreach ($catalog as $row) {
    $name = (string)$row['style_name'];

    // A prompt stored with the style is as good as a built-in one -- that is
    // the whole point of the authoring flow. Without this, every haircut added
    // through the portal would fail a test that exists to catch styles nobody
    // can preview, which is precisely the state it is no longer in.
    if (trim((string)($row['ai_prompt'] ?? '')) !== '') {
        $authoredStyles[] = $row;
        continue;
    }

    $key = replicate_resolve_style_key($name, (string)$row['style_code']);
    if ($key === null) {
        $unmatched[] = $name;
        continue;
    }
    // 'barbers_cut' is a real style, but nothing in the catalog is named that;
    // anything landing there got the old silent fallback.
    if ($key === 'barbers_cut' && stripos($name, 'barber') === false) {
        $fellBack[] = $name . ' -> barbers_cut';
    }
}

check('every catalog style resolves to a prompt' . ($unmatched ? ' (' . implode(', ', $unmatched) . ')' : ''),
    $unmatched === []);
check('no catalog style silently becomes a barbers cut' . ($fellBack ? ' (' . implode(', ', $fellBack) . ')' : ''),
    $fellBack === []);

// The curl must survive resolution: 'Curly Low Fade' contains 'low fade', so a
// shortest-first scan would hand it the straight-hair prompt.
foreach ([
    ['Curly Low Fade', 'curly_low_fade'],
    ['Curly Top Fade', 'curly_top_fade'],
    ['Curly Taper Fade', 'curly_taper_fade'],
    ['Mid Fade', 'mid_fade'],
    ['Low Fade', 'low_fade'],
] as [$name, $expected]) {
    check("'{$name}' resolves to {$expected}", replicate_resolve_style_key($name) === $expected);
}

// --- authored prompts are held to the same standard -------------------------
// Composed from a barber's answers rather than hand-written, so the rules that
// matter are the ones a composer could get wrong: saying what happens at the
// back, and not running so long that the detail competes with itself.
$authoredNoBack = [];
$authoredTooLong = [];
$authoredTooShort = [];
foreach ($authoredStyles as $row) {
    $text = (string)$row['ai_prompt'];
    if (preg_match('/\b(back|nape|neckline|collar)\b/i', $text) !== 1) {
        $authoredNoBack[] = (string)$row['style_name'];
    }
    // Looser than the 60 of the built-ins: a composed prompt carries more
    // fields by construction, and the barber's own wording is worth keeping.
    if (str_word_count($text) > 80) {
        $authoredTooLong[] = (string)$row['style_name'];
    }
    if (str_word_count($text) < 15) {
        $authoredTooShort[] = (string)$row['style_name'];
    }
}

check('authored prompts say what happens at the back'
    . ($authoredNoBack ? ' (' . implode(', ', $authoredNoBack) . ')' : ''),
    $authoredNoBack === []);
check('authored prompts stay under 80 words'
    . ($authoredTooLong ? ' (' . implode(', ', $authoredTooLong) . ')' : ''),
    $authoredTooLong === []);
check('authored prompts are not stubs'
    . ($authoredTooShort ? ' (' . implode(', ', $authoredTooShort) . ')' : ''),
    $authoredTooShort === []);

// --- the composer produces something that passes those rules ----------------
$composed = compose_hairstyle_prompt('Test Style', [
    'sides' => 'sides faded short from the temple',
    'top' => 'two inches left on top',
]);
check('the composer always states the back, even when not asked',
    preg_match('/\b(back|nape|neckline|collar)\b/i', $composed) === 1);
check('the composer leads with the style name',
    str_starts_with($composed, 'test style:'));

// --- the resolver admits defeat ---------------------------------------------
check('an unknown style resolves to null, not a guess',
    replicate_resolve_style_key('Mohawk With Lightning Bolts', 'HC-NOPE') === null);
check('an empty style resolves to null', replicate_resolve_style_key('', '') === null);

$brief = replicate_style_brief('Mohawk With Lightning Bolts', null, 1, '');
check('the shared brief refuses an unknown style', $brief['ok'] === false);
check('and says which style it was', str_contains($brief['error'], 'Mohawk With Lightning Bolts'));

// --- the prompts are specifications, not labels ------------------------------
$tooShort = [];
$noDetail = [];
$noBack = [];
$tooLong = [];
foreach ($prompts as $key => $text) {
    if (str_word_count($text) < 25) {
        $tooShort[] = $key;
    }
    // A prompt padded past this competes with itself: every extra clause
    // dilutes the fade and guard-number detail doing the real work.
    if (str_word_count($text) > 60) {
        $tooLong[] = $key;
    }
    // A haircut is defined by what happens to the sides and how much length is
    // left. "low fade hairstyle, gradual fade on sides, natural top" answered
    // neither in any usable way, which is the vagueness this guards against.
    $saysSides = preg_match('/\b(side|sides|back|nape|neckline|temple|temples)\b/i', $text) === 1;
    $saysLength = preg_match('/\b(inch|inches|length|long|short|tall|deep)\b/i', $text) === 1;
    if (!$saysSides || !$saysLength) {
        $noDetail[] = $key;
    }

    // Two Block generated long hair at the back because the prompt described
    // the top and the sides and left the back unsaid -- and an image model
    // fills whatever you do not specify from its own prior. Eleven of the
    // thirty-four prompts had the same hole.
    if (preg_match('/\b(back|nape|neckline|collar)\b/i', $text) !== 1) {
        $noBack[] = $key;
    }
}

check('no prompt exceeds 60 words' . ($tooLong ? ' (' . implode(', ', $tooLong) . ')' : ''),
    $tooLong === []);
check('every prompt is at least 25 words' . ($tooShort ? ' (' . implode(', ', $tooShort) . ')' : ''),
    $tooShort === []);
check('every prompt says what happens to the sides, and a length'
    . ($noDetail ? ' (' . implode(', ', $noDetail) . ')' : ''),
    $noDetail === []);
check('every prompt says what happens at the back of the head'
    . ($noBack ? ' (' . implode(', ', $noBack) . ')' : ''),
    $noBack === []);

// --- the lookup tables agree with each other ---------------------------------
$missingLength = array_diff(array_keys($prompts), array_keys($minLengths));
check('every prompt has a minimum length' . ($missingLength ? ' (' . implode(', ', $missingLength) . ')' : ''),
    $missingLength === []);

$orphanLength = array_diff(array_keys($minLengths), array_keys($prompts));
check('no minimum length without a prompt' . ($orphanLength ? ' (' . implode(', ', $orphanLength) . ')' : ''),
    $orphanLength === []);

$badLevels = array_filter($minLengths, static fn(int $v): bool => $v < 0 || $v > 3);
check('every minimum length is a real hair-length level', $badLevels === []);

check('keys are normalised the way the resolver normalises names',
    array_keys($prompts) === array_map('replicate_normalize_style_key', array_keys($prompts)));

// --- the Python sidecar holds the same table --------------------------------
$syncScript = __DIR__ . '/sync_tryon_prompts.php';
$output = [];
$exitCode = 0;
exec('php ' . escapeshellarg($syncScript) . ' --check 2>&1', $output, $exitCode);
check('ai-service/api.py is in sync (run sync_tryon_prompts.php if this fails)', $exitCode === 0);

// --- the adapted "achievable today" path is gone ----------------------------
// Five attempts tried to make the generator render a length-hungry cut on
// short hair: an honest replacement description, the constraint front-loaded,
// the clause that was literally ordering weight at the nape removed, the whole
// prompt reframed as removal-only, and the style name stripped so there was no
// famous haircut to reproduce. Each was verified in the assembled prompt; each
// came back with the same long back.
//
// The cause is structural -- xAI's edits endpoint takes no mask, so no region
// can be protected, and an image model follows a strong learned concept over a
// negative. Those customers now see the full render labelled as a grow-out
// goal instead, so the machinery was deleted rather than left dormant.
foreach ([
    'replicate_style_short_variant',
    'replicate_derive_short_variant',
    'replicate_shorten_prompt_clause',
    'replicate_achievable_today_clause',
    'replicate_short_hair_style_desc',
] as $retired) {
    check("{$retired}() is gone, not merely unused", !function_exists($retired));
}

// The flag survives on the signature so an older APK still posting it does not
// break. It must change nothing at all.
foreach (replicate_style_min_length() as $key => $level) {
    if ($level < 2) {
        continue;
    }
    $name = ucwords(str_replace('_', ' ', $key));
    $withFlag = replicate_style_brief($name, null, 1, 'black', true);
    $without = replicate_style_brief($name, null, 1, 'black', false);

    check("{$key}: achievableToday changes nothing in the prompt",
        $withFlag['basePrompt'] === $without['basePrompt']);
    check("{$key}: and nothing is reported as adapted",
        ($withFlag['adaptedToCurrentLength'] ?? true) === false);
}

// A short-haired customer and a long-haired one get the same description --
// the difference is now the label the app puts on the result, not the prompt.
$short = replicate_style_brief('Modern Mullet', 'HC-MODERN-MULLET', 1, '', true);
$long = replicate_style_brief('Modern Mullet', 'HC-MODERN-MULLET', 3, '', false);
check('both customers get the real style description',
    $short['styleDesc'] === $long['styleDesc']
        && str_contains($short['styleDesc'], 'deliberately kept long'));

// None of the five attempts may leave wording behind.
foreach ([
    'HARD CONSTRAINT',
    'You may only REMOVE hair',
    'performing exactly this cutting',
    'adapted to shorter hair',
    'not part of this cut',
    'an unchanged back is the correct result',
    'FINAL CHECK BEFORE YOU RENDER',
] as $ghost) {
    check("no leftover from the adapted path: \"{$ghost}\"",
        !str_contains($short['basePrompt'], $ghost));
}

// The full instruction has to be intact again, since every customer now gets
// it. These are the parts the adapted path used to withhold.
foreach ([
    'to this exact haircut',
    'back hairline',
    'clearly different from the original',
] as $restored) {
    check("the full prompt still says \"{$restored}\"",
        str_contains($short['basePrompt'], $restored));
}

// --- the file itself ---------------------------------------------------------
// A patch once wrote a literal backspace byte where a regex word boundary was
// meant, which silently disabled the check it was guarding. Cheap to assert,
// and the failure mode is invisible by eye.
$helperSource = (string)file_get_contents(__DIR__ . '/../api/replicate_helper.php');
check('the prompt helper contains no stray control characters',
    preg_match('/[\x00-\x08\x0B\x0C\x0E-\x1F]/', $helperSource) !== 1);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
