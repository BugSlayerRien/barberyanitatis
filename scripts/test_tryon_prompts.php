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

// --- the short-hair variants -------------------------------------------------
// A customer with short hair who accepted the "this needs longer hair" warning
// was still shown a full long-backed mullet. The cause was not a weak warning
// but a self-contradicting prompt: the description said the back was
// "deliberately kept long" and a generic "do not add length" was appended
// after it. An image model follows the vivid description, not the disclaimer.
// These checks assert the contradiction can no longer be built.
$shortVariants = replicate_style_short_variant();
$minLengths = replicate_style_min_length();

foreach ($minLengths as $key => $level) {
    if ($level < 2) {
        continue;
    }
    check("{$key} needs length, so it has a short-hair variant",
        isset($shortVariants[$key]) && trim($shortVariants[$key]) !== '');
}

foreach ($shortVariants as $key => $text) {
    check("{$key} short variant states the back",
        preg_match('/\b(back|nape|collar)\b/i', $text) === 1);

    // Only *positive* length claims are a problem. "nothing over the collar"
    // is the negation we want, so the negated forms are removed before the
    // check rather than matched by a blunter pattern.
    $positive = preg_replace(
        '/\b(?:nothing|no|without)\b[^,.]*?\b(?:collar|nape|length|longer)\b/i',
        '',
        $text
    ) ?? $text;
    $assertsLength = preg_match(
        '/\b(kept long|long back|deliberately kept|grown out|past the collar|falling to the nape)\b/i',
        $positive
    ) === 1;
    check("{$key} short variant never promises length it cannot deliver", !$assertsLength);

    // And it must say so outright: this is the clause that replaced the
    // contradiction, so its absence means the variant is merely vague.
    check("{$key} short variant states the hair is not lengthened",
        preg_match('/\b(no length added|not by added length|as short as it already is|exactly (?:as long as|their current length)|current length|already present|existing length|already are)\b/i', $text) === 1);

    $words = str_word_count($text);
    check("{$key} short variant sits in the word budget ({$words})",
        $words >= 20 && $words <= 70);
}

// The real case from the device: short hair, Modern Mullet, warning accepted.
$adapted = replicate_style_brief('Modern Mullet', 'HC-MODERN-MULLET', 1, '', true);
check('an adapted brief builds', $adapted['ok'] === true);
check('and is marked as adapted', $adapted['adaptedToCurrentLength'] === true);
check('the long-back description is gone from the prompt',
    !str_contains($adapted['basePrompt'], 'deliberately kept long'));
check('and so is the other long-back phrase',
    !str_contains($adapted['basePrompt'], 'long back section'));
check('the prompt insists the back stays short',
    str_contains($adapted['basePrompt'], 'back must stay as short'));

// A customer who actually has the length must still get the real cut.
$full = replicate_style_brief('Modern Mullet', 'HC-MODERN-MULLET', 3, '', false);
check('a long-haired customer still gets the full cut',
    str_contains($full['styleDesc'], 'deliberately kept long'));
check('and their brief is not marked adapted',
    $full['adaptedToCurrentLength'] === false);

// Accepting the warning is what triggers adaptation -- not short hair alone,
// since a customer may decline and simply pick something else.
$declined = replicate_style_brief('Modern Mullet', 'HC-MODERN-MULLET', 1, '', false);
check('without accepting the warning nothing is adapted',
    $declined['adaptedToCurrentLength'] === false);

// A style with no authored variant is rewritten, not merely hedged. Appending
// a denial after "long flowing layers" was the original bug -- the model reads
// the description and ignores the disclaimer trailing it.
$fallback = replicate_short_hair_style_desc(
    'no_such_style',
    'some cut: long flowing layers reaching the collar',
    'Some Cut'
);
check('an unauthored style is rewritten rather than left asserting',
    !str_contains($fallback, 'long flowing layers'));
check('and the rewrite is what the model receives',
    str_contains($fallback, 'adapted to shorter hair'));

// --- the automatic short-hair rewriter ---------------------------------------
// Only eight styles have a hand-written short version. Everything added through
// the barber app or the admin portal has one free-text prompt and nothing else,
// and the old fallback simply appended "without adding length anywhere" after a
// description that had just asked for a long back -- the same contradiction
// that drew a long-backed mullet. These assert the derived text makes no claim
// to length the customer does not have.
//
// The two stored prompts are inlined rather than read from the database, so the
// test says the same thing on any machine and keeps saying it after someone
// edits a row.
$authoredSamples = [
    'Wolf Cut' => 'wolf cut: sides left long and scissor-cut into soft wispy layers, '
        . 'two to three inches on top in short choppy layers, heavily point-cut, '
        . 'a wispy curtain fringe parted in the middle, the back left longest, '
        . 'in soft tapered layers just past the nape onto the collar, '
        . 'natural neckline, left untrimmed, texture spray, finger-dried for movement',
    'Pineapple' => 'pineapple: sides and back clipped short with a clean taper from the '
        . 'temple down to the skin, clipper guards a #1 at the bottom blending to a #3, '
        . 'the top left about 4 inches long and gathered upward into a tall rounded '
        . 'pineapple shape above the crown, no fringe, the front swept up and back off '
        . 'the forehead, the back tapered short to the nape with nothing left over the '
        . 'collar, a rounded neckline',
];

$derivable = $authoredSamples;
foreach (replicate_style_prompts() as $key => $text) {
    if ((replicate_style_min_length()[$key] ?? 1) >= 2) {
        $derivable[ucwords(str_replace('_', ' ', $key))] = $text;
    }
}

foreach ($derivable as $name => $prompt) {
    $derived = replicate_derive_short_variant($name, $prompt);

    check("{$name}: derived variant states the back",
        preg_match('/\b(back|nape|collar)\b/i', $derived) === 1);

    // Same rule the hand-written variants are held to: strip the negated
    // phrasings first, so "nothing over the collar" is not mistaken for a claim.
    $positive = preg_replace(
        '/\b(?:nothing|no|without)\b[^,.]*?\b(?:collar|nape|length|longer|long)\b/i',
        '',
        $derived
    ) ?? $derived;
    check("{$name}: derived variant claims no length",
        preg_match('/\b(kept long|left long|longest|long back|long full|deliberately kept|'
            . 'falling to the nape|reaching the nape|past the collar|inches)\b/i', $positive) !== 1);

    // Several rules can land on one phrase; the output must still read as
    // English rather than "the top at at its current length".
    check("{$name}: derived variant has no doubled substitution",
        preg_match('/\b(?:at|of|in|to)\s+at its current length\b/i', $derived) !== 1
            && !str_contains($derived, 'lengthat')
            && preg_match('/\s{2,}/', $derived) !== 1);

    check("{$name}: derived variant is labelled as adapted",
        str_contains(strtolower($derived), 'adapted to shorter hair'));
}

// The two cases that motivated this, named explicitly.
$wolf = replicate_derive_short_variant('Wolf Cut', $authoredSamples['Wolf Cut']);
check('Wolf Cut no longer asks for the longest back',
    !str_contains($wolf, 'the back left longest'));
check('Wolf Cut no longer reaches past the nape onto the collar',
    !str_contains($wolf, 'past the nape onto the collar'));

// Shape must survive the length being removed -- dropping the whole clause
// would throw away the part that makes it that haircut.
$pine = replicate_derive_short_variant('Pineapple', $authoredSamples['Pineapple']);
check('Pineapple keeps the shape that names it',
    str_contains($pine, 'tall rounded pineapple shape'));
check('Pineapple loses the four inches',
    !str_contains($pine, '4 inches'));

// A prompt with nothing to strip must come back intact.
$neutral = 'buzz cut: clipped to one even short length all over with a #2 guard, '
    . 'the back and sides tapered to the nape';
$neutralOut = replicate_derive_short_variant('Buzz Cut', $neutral);
check('a prompt with no length claims is not mangled',
    str_contains($neutralOut, 'clipped to one even short length all over with a #2 guard'));
check('and it still gains the closing clause',
    str_contains($neutralOut, 'no length added anywhere'));

check('an empty prompt derives nothing rather than a bare label',
    replicate_derive_short_variant('Anything', '') === '');

// A hand-written variant is better than a derived one, so it must win.
$handWritten = replicate_style_short_variant()['modern_mullet'];
check('a hand-written variant takes precedence over the derived one',
    replicate_short_hair_style_desc('modern_mullet', 'ignored', 'Modern Mullet') === $handWritten);
check('and a style without one falls through to the rewriter',
    str_contains(
        replicate_short_hair_style_desc('wolf_cut', $authoredSamples['Wolf Cut'], 'Wolf Cut'),
        'adapted to shorter hair'
    ));

// End to end: the stored prompt, a short-haired customer, warning accepted.
$dbBrief = replicate_style_brief(
    'Wolf Cut', 'HC-WOLF-CUT', 1, '', true, $authoredSamples['Wolf Cut'], 3
);
check('a database style adapts for a short-haired customer',
    ($dbBrief['adaptedToCurrentLength'] ?? false) === true);
check('and its long-back wording never reaches the model',
    !str_contains($dbBrief['basePrompt'], 'the back left longest'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
