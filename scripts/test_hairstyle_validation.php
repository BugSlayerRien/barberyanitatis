<?php

declare(strict_types=1);

/**
 * Guards the checks that run before a haircut is written.
 *
 * There were none. The UNIQUE constraint on style_code was the only thing
 * stopping a duplicate, and it answered with a raw Postgres message and an
 * HTTP 500 -- unreadable to the admin who hit it, and leaking table and
 * constraint names to the browser. It was easiest to trigger from the barber
 * app, where codes are generated from the name: two barbers submitting
 * "Wolf Cut" both produced HC-WOLF-CUT.
 *
 * Writes run inside a transaction that is always rolled back.
 */

require_once __DIR__ . '/../api/db.php';
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

echo "Hairstyle validation checks\n";

$pdo = get_db_connection();
ensure_hairstyle_authoring_columns($pdo);

// --- generating a code from a name -------------------------------------------
check('a name becomes an uppercase hyphenated code',
    hairstyle_code_from_name('Two Block') === 'HC-TWO-BLOCK');
// The bug this replaced: substituting before the case fold deleted every
// lowercase letter, so "Mid Fade" became HC-M-F-.
check('lowercase letters survive the slug',
    hairstyle_code_from_name('Mid Fade') === 'HC-MID-FADE');
check('punctuation collapses to single hyphens',
    hairstyle_code_from_name("Dao Ming Si's  Cut!!") === 'HC-DAO-MING-SI-S-CUT');
check('a very long name is cut to the column width',
    strlen(hairstyle_code_from_name(str_repeat('Long Name ', 6))) <= 20);
check('a name with nothing usable still yields a code',
    hairstyle_code_from_name('!!!') === 'HC-STYLE');

// --- a typed code is checked before the insert -------------------------------
check('a well-formed unused code is accepted',
    hairstyle_code_problem($pdo, 'HC-NOT-TAKEN-YET') === '');
check('an empty code is left to the generator',
    hairstyle_code_problem($pdo, '') === '');
check('spaces are rejected',
    str_contains(hairstyle_code_problem($pdo, 'HC PINEAPPLE'), 'letters, numbers and hyphens'));
check('punctuation is rejected',
    hairstyle_code_problem($pdo, 'HC_PINE@PPLE') !== '');
check('an over-long code is rejected',
    str_contains(hairstyle_code_problem($pdo, str_repeat('A', 21)), 'too long'));

// The case that produced the raw 500.
// Deliberately a style whose name nothing else shares: the catalogue carries
// deactivated STYLE-* seeds that duplicate live names, and picking one of
// those would test the duplicate case while pretending to test the unique one.
$taken = $pdo->query(
    "SELECT h.style_code, h.style_name, h.hairstyle_id
     FROM hairstyles h
     WHERE h.is_active = TRUE
       AND (SELECT COUNT(*) FROM hairstyles d
            WHERE d.is_active = TRUE
              AND LOWER(TRIM(d.style_name)) = LOWER(TRIM(h.style_name))) = 1
     ORDER BY h.hairstyle_id LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);
check('a style exists to collide with', (bool)$taken);

if ($taken) {
    $problem = hairstyle_code_problem($pdo, (string)$taken['style_code']);
    check('a code already in use is rejected', $problem !== '');
    check('and the message names the style holding it',
        str_contains($problem, (string)$taken['style_name']));
    check('case does not let a duplicate through',
        hairstyle_code_problem($pdo, strtolower((string)$taken['style_code'])) !== '');

    // Editing a style must not trip over its own code.
    check('a style keeps its own code when edited',
        hairstyle_code_problem($pdo, (string)$taken['style_code'], (int)$taken['hairstyle_id']) === '');

    // --- names -----------------------------------------------------------------
    $nameProblem = hairstyle_name_problem($pdo, (string)$taken['style_name']);
    check('a name already in use is rejected', $nameProblem !== '');
    check('and the message says which code holds it',
        str_contains($nameProblem, (string)$taken['style_code']));
    check('a duplicate name is caught regardless of case and spacing',
        hairstyle_name_problem($pdo, '  ' . strtoupper((string)$taken['style_name']) . ' ') !== '');
    check('a style keeps its own name when edited',
        hairstyle_name_problem($pdo, (string)$taken['style_name'], (int)$taken['hairstyle_id']) === '');
}

check('an empty name is rejected',
    str_contains(hairstyle_name_problem($pdo, '   '), 'required'));
check('an over-long name is rejected',
    str_contains(hairstyle_name_problem($pdo, str_repeat('x', 81)), 'too long'));
check('an unused name is accepted',
    hairstyle_name_problem($pdo, 'Totally Unused Style ' . bin2hex(random_bytes(4))) === '');

// --- generated codes step aside instead of colliding -------------------------
if ($taken) {
    $unique = hairstyle_unique_code($pdo, (string)$taken['style_code']);
    check('a taken code is suffixed rather than reused',
        $unique !== strtoupper((string)$taken['style_code']));
    check('and the suffixed code is itself free',
        hairstyle_code_problem($pdo, $unique) === '');
    check('and still fits the column', strlen($unique) <= 20);
}

$fresh = hairstyle_unique_code($pdo, 'HC-UNUSED-' . strtoupper(bin2hex(random_bytes(3))));
check('an unused code is handed back unchanged', hairstyle_code_problem($pdo, $fresh) === '');

// Two submissions of the same name must not produce the same code -- the
// exact case two barbers hit with "Wolf Cut".
$pdo->beginTransaction();
try {
    $name = 'Collision Test ' . bin2hex(random_bytes(3));
    $first = hairstyle_unique_code($pdo, hairstyle_code_from_name($name));
    $pdo->prepare(
        "INSERT INTO hairstyles (style_code, style_name, gender, difficulty, maintenance,
                                 category, is_active)
         VALUES (:code, :name, 'Unisex', 'Medium', 'Medium', 'alternative', TRUE)"
    )->execute([':code' => $first, ':name' => $name]);

    $second = hairstyle_unique_code($pdo, hairstyle_code_from_name($name));
    check('a second submission of the same name gets a different code',
        $second !== $first);
    check('and the duplicate name is caught outright',
        hairstyle_name_problem($pdo, $name) !== '');
} finally {
    $pdo->rollBack();
}

// --- database errors are summarised, never forwarded -------------------------
$duplicate = new PDOException(
    'SQLSTATE[23505]: Unique violation: 7 ERROR:  duplicate key value violates '
    . 'unique constraint "hairstyles_style_code_key"'
);
$friendly = hairstyle_friendly_db_error($duplicate);
check('a uniqueness failure is explained in plain words',
    str_contains($friendly, 'already in use'));
check('and the constraint name never reaches the client',
    !str_contains($friendly, 'hairstyles_style_code_key'));
check('and neither does SQLSTATE', !str_contains($friendly, 'SQLSTATE'));

$unknown = hairstyle_friendly_db_error(new PDOException('something nobody anticipated'));
check('an unrecognised failure still says something useful',
    $unknown !== '' && !str_contains($unknown, 'nobody anticipated'));

// The endpoints must use it rather than echoing the exception.
foreach (['api/admin_hairstyles.php', 'api/barber_hairstyles.php'] as $file) {
    $source = (string)file_get_contents(__DIR__ . '/../' . $file);
    check("{$file} summarises database errors",
        str_contains($source, 'hairstyle_friendly_db_error'));
    check("{$file} no longer forwards the raw message",
        !str_contains($source, "'details' => \$e->getMessage()")
            && !str_contains($source, 'db_error_response_payload($e)'));
}

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
