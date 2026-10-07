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
$catalog = $pdo->query(
    'SELECT DISTINCT style_code, style_name FROM hairstyles ORDER BY style_name'
)->fetchAll(PDO::FETCH_ASSOC);

check('the catalog is readable', count($catalog) > 0);

$unmatched = [];
$fellBack = [];
foreach ($catalog as $row) {
    $name = (string)$row['style_name'];
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

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
