<?php

declare(strict_types=1);

/**
 * Every barber works both queues, and the two screens agree about it.
 *
 * Two defects, one root. The shop split barbers into "walk-in only" and
 * "appointment only", and barber_channel_filter_sql() decided which side a
 * query saw by asking queue_merge_enabled() -- which returned false whenever
 * nobody had handed it a connection. time_slots.php primed it on every
 * suggest; booking.php primed it inside schema_ensure_once(), which skips
 * after the first deploy. So the suggestion screen offered a walk-in barber as
 * "your usual barber" and the booking screen then answered "This barber is not
 * available for appointments."
 *
 * The split itself is retired: with four barbers it took one off the board for
 * half the shop's work. barber_channel is still stored and still shown, but
 * nothing filters on it.
 *
 * The probes run from a cold process, which is the state booking.php was
 * always in.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/barber_channel.php';

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

echo "Queue: every barber, both queues\n";

$pdo = get_db_connection();

// Written to a file rather than passed to php -r: the shell mangles the
// quoting on Windows and the probe silently fails to parse.
$probe = static function (string $body): int {
    $file = sys_get_temp_dir() . '/qm_probe_' . bin2hex(random_bytes(4)) . '.php';
    file_put_contents(
        $file,
        "<?php require " . var_export(__DIR__ . '/../api/db.php', true) . ";\n"
        . "require " . var_export(__DIR__ . '/../api/barber_channel.php', true) . ";\n"
        . $body
    );
    try {
        return (int)trim((string)shell_exec('php ' . escapeshellarg($file)));
    } finally {
        @unlink($file);
    }
};

// --- nothing filters on channel any more -------------------------------------
check('the filter adds no clause', barber_channel_filter_sql('appointment') === '');
check('nor for the walk-in side', barber_channel_filter_sql('walk_in') === '');
check('nor with an aliased column',
    barber_channel_filter_sql('appointment', 'b.barber_channel') === '');
check('an unknown channel is harmless too',
    barber_channel_filter_sql('nonsense') === '');

// --- and a stale setting cannot re-split it ----------------------------------
// The old toggle is gone from the portal, but a shop that had it switched on or
// off still carries the row. It must make no difference either way.
$settingRow = $pdo->query(
    "SELECT setting_value FROM system_settings WHERE setting_key = 'queue_merge_enabled' LIMIT 1"
)->fetch(PDO::FETCH_ASSOC);
$original = $settingRow === false ? null : (string)$settingRow['setting_value'];

$write = $pdo->prepare(
    "INSERT INTO system_settings (setting_key, setting_value)
     VALUES ('queue_merge_enabled', :v)
     ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value"
);

/** Barbers suggestable for appointments whom the booking check would refuse. */
$refusedUnder = static function (string $value) use ($write, $probe): int {
    $write->execute([':v' => $value]);

    return $probe(
        '$pdo = get_db_connection();'
        . '$f = barber_channel_filter_sql("appointment", "b.barber_channel");'
        . '$sql = "SELECT DISTINCT b.barber_id FROM time_slots ts"'
        . ' . " JOIN barbers b ON b.barber_id = ts.barber_id"'
        . ' . " WHERE b.is_active = TRUE" . $f'
        . ' . " AND ts.status = " . $pdo->quote("Available");'
        . '$rows = $pdo->query($sql)->fetchAll(PDO::FETCH_COLUMN);'
        . '$check = $pdo->prepare("SELECT COUNT(*) FROM barbers WHERE barber_id = :id"'
        . ' . " AND is_active = TRUE" . barber_channel_filter_sql("appointment"));'
        . '$bad = 0;'
        . 'foreach ($rows as $id) { $check->execute([":id" => (int)$id]);'
        . ' if ((int)$check->fetchColumn() === 0) { $bad++; } }'
        . 'echo $bad;'
    );
};

try {
    check('with the old setting on, nobody suggested is refused',
        $refusedUnder('1') === 0);
    check('with the old setting off, nobody suggested is refused',
        $refusedUnder('0') === 0);
    check('a cold process still reads the queue as merged',
        $probe('echo queue_merge_enabled() ? 1 : 0;') === 1);
} finally {
    // Put the shop back exactly as it was, whatever happened above.
    if ($original === null) {
        $pdo->prepare("DELETE FROM system_settings WHERE setting_key = 'queue_merge_enabled'")
            ->execute();
    } else {
        $write->execute([':v' => $original]);
    }
}

$restored = $pdo->query(
    "SELECT setting_value FROM system_settings WHERE setting_key = 'queue_merge_enabled' LIMIT 1"
)->fetchColumn();
check('the shop setting was put back',
    ($restored === false ? null : (string)$restored) === $original);

// --- every active barber is reachable from both sides ------------------------
$active = $pdo->query(
    'SELECT barber_id, full_name, barber_channel FROM barbers
      WHERE is_active = TRUE ORDER BY barber_id'
)->fetchAll(PDO::FETCH_ASSOC);
check('the shop has active barbers', $active !== []);

$bookable = $pdo->prepare(
    'SELECT COUNT(*) FROM barbers WHERE barber_id = :id AND is_active = TRUE'
    . barber_channel_filter_sql('appointment')
);
$walkIn = $pdo->prepare(
    'SELECT COUNT(*) FROM barbers WHERE barber_id = :id AND is_active = TRUE'
    . barber_channel_filter_sql('walk_in')
);

$missingAppointment = [];
$missingWalkIn = [];
foreach ($active as $barber) {
    $bookable->execute([':id' => (int)$barber['barber_id']]);
    if ((int)$bookable->fetchColumn() === 0) {
        $missingAppointment[] = $barber['full_name'];
    }
    $walkIn->execute([':id' => (int)$barber['barber_id']]);
    if ((int)$walkIn->fetchColumn() === 0) {
        $missingWalkIn[] = $barber['full_name'];
    }
}

check('every active barber can take an appointment'
    . ($missingAppointment === [] ? '' : ' -- missing: ' . implode(', ', $missingAppointment)),
    $missingAppointment === []);
check('every active barber can take a walk-in'
    . ($missingWalkIn === [] ? '' : ' -- missing: ' . implode(', ', $missingWalkIn)),
    $missingWalkIn === []);

// Including the ones the old split would have hidden -- the case that produced
// the contradiction in the first place.
$walkInOnly = array_values(array_filter(
    $active,
    static fn(array $b): bool => $b['barber_channel'] === 'walk_in'
));
if ($walkInOnly !== []) {
    $names = implode(', ', array_column($walkInOnly, 'full_name'));
    check("a barber marked walk-in is still bookable ({$names})",
        $missingAppointment === []);
}

// --- the portal no longer offers a switch that does nothing ------------------
$portal = (string)file_get_contents(__DIR__ . '/../web-admin/admin/index.html');
$portalJs = (string)file_get_contents(__DIR__ . '/../web-admin/admin/app.js');
check('the merge toggle is gone from the settings page',
    !str_contains($portal, 'setting-queue-merge'));
check('and nothing posts it any more',
    !str_contains($portalJs, 'setting-queue-merge'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
