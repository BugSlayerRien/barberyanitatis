<?php

declare(strict_types=1);

/**
 * Hair length survives without a scan, the way hair texture already did.
 *
 * The scan has always written the length to user_profiles -- nothing ever read
 * it back. So a customer who had not scanned in this app run was judged
 * short-haired by a `?? 1` fallback and warned off every long style, although
 * their own profile held the answer.
 *
 * No schema change was needed: user_profiles.hair_length already existed and
 * was already populated.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/hair_length.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $condition): void
{
    global $failures, $checks;
    $checks++;
    echo ($condition ? '  PASS  ' : '  FAIL  ') . $label . "\n";
    if (!$condition) {
        $failures++;
    }
}

echo "Profile hair length\n";

$pdo = get_db_connection();

// --- the column is there and already holds data --------------------------
$column = $pdo->query(
    "SELECT data_type FROM information_schema.columns
      WHERE table_name = 'user_profiles' AND column_name = 'hair_length'"
)->fetchColumn();
check('user_profiles.hair_length exists', $column !== false);

$populated = (int)$pdo->query(
    'SELECT COUNT(*)::int FROM user_profiles WHERE hair_length IS NOT NULL'
)->fetchColumn();
check('and scans have been writing to it already', $populated > 0);

// Every stored value must be one this screen can show, or the dropdown falls
// back to "Short" and silently misreports the customer.
$unknown = [];
foreach ($pdo->query(
    'SELECT DISTINCT hair_length FROM user_profiles WHERE hair_length IS NOT NULL'
)->fetchAll(PDO::FETCH_COLUMN) as $value) {
    if (normalize_hair_length((string)$value) === null) {
        $unknown[] = (string)$value;
    }
}
check('every stored value is one the app understands'
    . ($unknown === [] ? '' : ' (' . implode(', ', $unknown) . ')'),
    $unknown === []);

// --- labels map to the levels the length check compares against ----------
check('very short is level 0', hair_length_label_to_level('Very short') === 0);
check('short is level 1', hair_length_label_to_level('short') === 1);
check('medium is level 2', hair_length_label_to_level('MEDIUM') === 2);
check('long is level 3', hair_length_label_to_level('Long') === 3);
check('an unknown label has no level', hair_length_label_to_level('bouffant') === null);
check('and neither does an empty one', hair_length_label_to_level('') === null);
check('nor null', hair_length_label_to_level(null) === null);

// Spellings the scan and the portal actually produce.
check('"mid" reads as medium', normalize_hair_length('mid') === 'Medium');
check('"buzzed" reads as very short', normalize_hair_length('buzzed') === 'Very short');
check('whitespace is tolerated', normalize_hair_length('  Long  ') === 'Long');

// --- the endpoint serves and accepts it ----------------------------------
$source = (string)file_get_contents(__DIR__ . '/../api/profile.php');
check('the profile payload carries the label', str_contains($source, "'hairLength' =>"));
check('and the level the check needs', str_contains($source, "'hairLengthLevel' =>"));
check('the update reads a submitted length', str_contains($source, "\$data['hairLength']"));
check('and writes it', str_contains($source, 'hair_length = COALESCE(EXCLUDED.hair_length'));

// A save that does not mention length must not wipe what the scan measured --
// the profile screen is not the only writer of this column.
check('an unmentioned length is kept, not cleared',
    str_contains($source, 'COALESCE(EXCLUDED.hair_length, user_profiles.hair_length)'));

// --- the app prefers a scan, then the profile, then "short" --------------
$session = (string)file_get_contents(__DIR__ . '/../mobile-app/lib/user/user_session.dart');
check('the app has one answer for "how long is their hair"',
    str_contains($session, 'effectiveHairLengthLevel'));
check('and it prefers this scan over the profile',
    str_contains($session, "(lastScan?['hairLengthLevel'] as num?)?.toInt() ??"));

$launcher = (string)file_get_contents(
    __DIR__ . '/../mobile-app/lib/user/services/style_booking_launcher.dart'
);
check('the booking check uses it',
    str_contains($launcher, 'UserSession.effectiveHairLengthLevel'));
check('and no longer defaults straight to short',
    !str_contains($launcher, "lastScan?['hairLengthLevel'] as num?)?.toInt() ?? 1"));

$profilePage = (string)file_get_contents(
    __DIR__ . '/../mobile-app/lib/user/profile_page.dart'
);
check('the customer can correct it themselves',
    str_contains($profilePage, "label: 'Hair Length'"));
check('and the correction is persisted for the next run',
    str_contains($profilePage, 'savePreferredHairLengthLevel'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
