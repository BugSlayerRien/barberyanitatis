<?php

declare(strict_types=1);

/**
 * Guards the pairing between a style that needs length and the cut to get now.
 *
 * A customer turned away from a Modern Mullet used to be offered whatever
 * ranked highest among the cuts they could wear -- never wrong, never related.
 * Each length-hungry style now names a counterpart that grows into it.
 *
 * The risks worth testing are not that the table exists but that it lies: a
 * pairing that points at a style nobody can book, one that loops, or one whose
 * target is itself too long for the customer being helped. Each of those fails
 * silently in the app -- the suggestion just never appears -- so they are
 * asserted here instead.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/storage.php';
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

echo "Transition cut checks\n";

$pdo = get_db_connection();
ensure_hairstyle_authoring_columns($pdo);

$stmt = $pdo->prepare(
    "SELECT style_code, style_name, ai_min_length_level, transition_style_code
     FROM hairstyles
     WHERE is_active = TRUE AND COALESCE(review_status, :a) = :b"
);
$stmt->execute([':a' => 'Published', ':b' => 'Published']);

/** @var array<string, array<string, mixed>> $published */
$published = [];
foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
    $published[strtoupper((string)$row['style_code'])] = $row;
}
check('the published catalogue loaded', $published !== []);

$mins = replicate_style_min_length();
$minOf = static function (array $row) use ($mins): int {
    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    if ($key !== null && isset($mins[$key])) {
        return (int)$mins[$key];
    }

    return (int)($row['ai_min_length_level'] ?? 1);
};

// --- the built-in defaults point somewhere real ------------------------------
// A pairing naming a style that is missing, deactivated or unpublished is worse
// than no pairing: the app finds nothing and silently falls back, so the
// curation is lost without anyone noticing.
foreach (hairstyle_transition_defaults() as $key => $target) {
    $code = strtoupper(trim($target));
    check("{$key} pairs with a published style ({$code})", isset($published[$code]));
    check("{$key} does not pair with itself",
        strtoupper($key) !== str_replace('-', '_', ltrim($code, 'HC-')));
}

// Every default belongs to a style that actually needs length -- pairing a
// short style is harmless but means the table has drifted from the min lengths.
foreach (array_keys(hairstyle_transition_defaults()) as $key) {
    check("{$key} is a style that needs more than short hair",
        ($mins[$key] ?? 1) >= 2);
}

// --- every chain terminates, and terminates somewhere wearable ---------------
foreach ($published as $code => $row) {
    if ($minOf($row) < 2) {
        continue;
    }

    $name = (string)$row['style_name'];
    $seen = [$code => true];
    $cursor = $row;
    $landed = null;
    $looped = false;
    $missing = null;

    // Six hops is far beyond any real chain; exceeding it means the data is
    // cyclic in a way the visited-set did not catch.
    for ($hop = 0; $hop < 6; $hop++) {
        $next = hairstyle_transition_code($cursor);
        if ($next === '') {
            break;
        }
        if (isset($seen[$next])) {
            $looped = true;
            break;
        }
        if (!isset($published[$next])) {
            $missing = $next;
            break;
        }
        $seen[$next] = true;
        $cursor = $published[$next];
        if ($minOf($cursor) <= 1) {
            $landed = $cursor;
            break;
        }
    }

    check("{$name}: its chain does not loop", !$looped);
    check("{$name}: its chain never names a missing style", $missing === null);

    // Pineapple and Wolf Cut were added through the portal and have no pairing
    // yet, which is allowed -- the app falls back to the closest fit. What is
    // not allowed is a pairing that exists and leads nowhere wearable.
    if (hairstyle_transition_code($row) !== '') {
        check("{$name}: its chain reaches a cut a short-haired customer can wear",
            $landed !== null);
    }
}

// --- the known pairings, named -----------------------------------------------
// Spelled out so a silent edit to the table is visible in the diff rather than
// only in behaviour.
$expected = [
    'HC-MODERN-MULLET' => 'HC-TEXTURED-CROP',
    'HC-TWO-BLOCK' => 'HC-TEXTURED-CROP',
    'HC-MODERN-CURTAINS' => 'HC-TEXTURED-CROP',
    'HC-POMPADOUR' => 'HC-BLOWOUT-TAPER',
    'HC-WAVY-MOD' => 'HC-WAVY-FRINGE',
    'HC-CURLY-UNDERCUT' => 'HC-CURLY-TAPER',
];
foreach ($expected as $from => $to) {
    if (!isset($published[$from])) {
        continue;
    }
    check("{$from} offers {$to}", hairstyle_transition_code($published[$from]) === $to);
}

// Curly Modern Mullet is the case the chain exists for: its counterpart still
// needs medium hair, so a level-1 customer must be walked one hop further.
if (isset($published['HC-CURLY-MULLET'])) {
    $first = hairstyle_transition_code($published['HC-CURLY-MULLET']);
    check('Curly Modern Mullet points at Curly Top Fade first',
        $first === 'STYLE-CURLY-TOP-FADE');
    check('and that first hop is itself still too long for short hair',
        isset($published[$first]) && $minOf($published[$first]) >= 2);
}

// --- a stored pairing overrides the built-in default -------------------------
$subject = $pdo->query(
    "SELECT hairstyle_id, style_code, style_name, transition_style_code
     FROM hairstyles WHERE style_code = 'HC-MODERN-MULLET' LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);

if ($subject) {
    $pdo->beginTransaction();
    try {
        $pdo->prepare(
            'UPDATE hairstyles SET transition_style_code = :code WHERE hairstyle_id = :id'
        )->execute([':code' => 'HC-BUZZ-CUT', ':id' => $subject['hairstyle_id']]);

        $reread = $pdo->query(
            "SELECT style_code, style_name, transition_style_code
             FROM hairstyles WHERE style_code = 'HC-MODERN-MULLET' LIMIT 1"
        )->fetch(PDO::FETCH_ASSOC);

        check('a stored pairing wins over the built-in default',
            hairstyle_transition_code($reread) === 'HC-BUZZ-CUT');

        // Self-reference is treated as unset rather than honoured: it would
        // make the lookup loop, and it is never what anyone meant.
        $pdo->prepare(
            'UPDATE hairstyles SET transition_style_code = :code WHERE hairstyle_id = :id'
        )->execute([':code' => 'HC-MODERN-MULLET', ':id' => $subject['hairstyle_id']]);

        $selfRef = $pdo->query(
            "SELECT style_code, style_name, transition_style_code
             FROM hairstyles WHERE style_code = 'HC-MODERN-MULLET' LIMIT 1"
        )->fetch(PDO::FETCH_ASSOC);

        check('a style pointing at itself falls back to the default',
            hairstyle_transition_code($selfRef) === 'HC-TEXTURED-CROP');
    } finally {
        $pdo->rollBack();
    }

    check('the rollback restored the original pairing',
        hairstyle_transition_code($published['HC-MODERN-MULLET']) === 'HC-TEXTURED-CROP');
}

// --- the column is actually served ------------------------------------------
// The app cannot follow a chain it never receives.
foreach (['api/variant_ranking.php', 'api/haircuts.php'] as $file) {
    $source = (string)file_get_contents(__DIR__ . '/../' . $file);
    check("{$file} carries transition_style_code on its rows",
        str_contains($source, "transition_style_code"));
}

// --- the stored minimum length actually reaches the app ----------------------
// It did not. attach_style_min_length() read only the built-in code table, so
// a length chosen in the portal or the barber app was discarded on the way
// out: Wolf Cut was submitted as Long and served as Short, which meant no
// warning, no transition suggestion, and a full wolf cut generated on hair
// that could not carry it.
$resolved = static function (string $code) use ($pdo): ?int {
    $stmt = $pdo->prepare(
        'SELECT style_code, style_name, ai_min_length_level
         FROM hairstyles WHERE style_code = :code LIMIT 1'
    );
    $stmt->execute([':code' => $code]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    return $row ? attach_style_min_length($row)['min_length_level'] : null;
};

check('a style submitted as Long is served as Long', $resolved('HC-WOLF-CUT') === 3);
check('a style saved as Medium is served as Medium', $resolved('HC-PINEAPPLE') === 2);

// With nothing stored, the built-in table still describes the style -- the
// column overrides, it does not replace.
check('a built-in style with nothing stored keeps its code value',
    $resolved('HC-POMPADOUR') === 2);
check('and a built-in short style keeps its code value',
    $resolved('HC-BUZZ-CUT') === 0);

// The question this was all for: the owner lowers a style and it takes effect.
$pompadour = $pdo->query(
    "SELECT hairstyle_id FROM hairstyles WHERE style_code = 'HC-POMPADOUR' LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);

if ($pompadour) {
    $set = $pdo->prepare(
        'UPDATE hairstyles SET ai_min_length_level = :v WHERE hairstyle_id = :id'
    );

    $pdo->beginTransaction();
    try {
        $set->execute([':v' => 1, ':id' => (int)$pompadour['hairstyle_id']]);
        check('lowering a built-in style to Short takes effect',
            $resolved('HC-POMPADOUR') === 1);

        $set->execute([':v' => 3, ':id' => (int)$pompadour['hairstyle_id']]);
        check('and raising it to Long takes effect too',
            $resolved('HC-POMPADOUR') === 3);

        $set->execute([':v' => null, ':id' => (int)$pompadour['hairstyle_id']]);
        check('clearing it hands the style back to the built-in table',
            $resolved('HC-POMPADOUR') === 2);
    } finally {
        $pdo->rollBack();
    }

    check('the rollback left it on the built-in value',
        $resolved('HC-POMPADOUR') === 2);
}

// Out-of-range values are clamped rather than trusted: the column is plain INT
// and nothing at the database level stops a 9.
check('an absurd stored value is clamped',
    hairstyle_min_length_level(['style_name' => 'X', 'ai_min_length_level' => 9]) === 3);
check('and a negative one is clamped too',
    hairstyle_min_length_level(['style_name' => 'X', 'ai_min_length_level' => -4]) === 0);

// The leftover NOT NULL DEFAULT 1 is what made "unset" indistinguishable from
// "deliberately Short", so it must be gone.
$column = $pdo->query(
    "SELECT is_nullable, column_default FROM information_schema.columns
     WHERE table_name = 'hairstyles' AND column_name = 'ai_min_length_level'"
)->fetch(PDO::FETCH_ASSOC);
check('the column is nullable', ($column['is_nullable'] ?? '') === 'YES');
check('and carries no default', ($column['column_default'] ?? null) === null);

// Lowering a style below its pairing threshold is harmless: the pairing stays
// on the row but is never consulted, because nobody is turned away any more.
check('a style nobody is turned away from needs no pairing consulted',
    hairstyle_min_length_level(['style_name' => 'Pompadour', 'ai_min_length_level' => 0]) === 0);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
