<?php
// Ranking scenarios for smart appointment suggestions (no database).

declare(strict_types=1);

require_once __DIR__ . '/../api/slot_recommendation.php';

$failures = 0;
$reports = [];

function slot(int $barberId, string $name, string $date, string $time, int $available = 4): array
{
    return [
        'barber_id' => $barberId,
        'barber_name' => $name,
        'slot_date' => $date,
        'slot_time' => $time,
        'available_count' => $available,
        'specialty' => null,
    ];
}

function history(int $barberId, string $date, string $time, string $name = ''): array
{
    return [
        'barber_id' => $barberId,
        'barber_name' => $name,
        'appointment_date' => $date,
        'start_time' => $time,
    ];
}

function hours_index(array $candidates): array
{
    return slot_recommendation_index_available_hours($candidates);
}

function assert_scenario(
    string $name,
    array $result,
    callable $check
): void {
    global $failures, $reports;
    $primary = $result['primary'];
    $alts = $result['alternatives'];
    $ok = true;
    $messages = [];
    try {
        $check($primary, $alts, $result);
    } catch (Throwable $e) {
        $ok = false;
        $messages[] = $e->getMessage();
        $failures++;
    }
    $reports[] = [
        'name' => $name,
        'ok' => $ok,
        'primary' => $primary,
        'alternatives' => $alts,
        'messages' => $messages,
    ];
}

function expect(bool $cond, string $message): void
{
    if (!$cond) {
        throw new RuntimeException($message);
    }
}

function summarize_slot(?array $slot): string
{
    if ($slot === null) {
        return '(none)';
    }
    $who = $slot['barber_name'] ?? ('#' . ($slot['barber_id'] ?? '?'));
    return ($slot['slot_date'] ?? '') . ' ' . substr((string)($slot['slot_time'] ?? ''), 0, 5)
        . ' ' . $who
        . ' [' . ($slot['reason_code'] ?? '') . ' / ' . ($slot['rank_score'] ?? 0) . ']';
}

function reason_claims_usual(?array $slot): bool
{
    $code = (string)($slot['reason_code'] ?? '');
    return str_starts_with($code, 'usual_');
}

$today = '2026-08-26'; // Wednesday
$thu = '2026-08-27';
$fri = '2026-08-28';
$sat = '2026-08-29';
$sun = '2026-08-30';
$nextWed = '2026-09-02';

$alex = 2;
$miguel = 7;
$sharedPool = [
    slot($alex, 'Alex', $today, '13:00:00'),
    slot($alex, 'Alex', $today, '14:00:00'),
    slot($miguel, 'Miguel', $today, '17:00:00'),
    slot($alex, 'Alex', $today, '18:00:00'),
    slot($alex, 'Alex', $thu, '10:00:00'),
    slot($miguel, 'Miguel', $thu, '18:00:00'),
    slot($alex, 'Alex', $fri, '18:00:00'),
    slot($miguel, 'Miguel', $fri, '18:00:00'),
    slot($alex, 'Alex', $sat, '10:00:00'),
    slot($miguel, 'Miguel', $sat, '14:00:00'),
    slot($alex, 'Alex', $sun, '10:00:00'),
    slot($miguel, 'Miguel', $nextWed, '17:00:00'),
];

// 1. New customer
$p1 = slot_recommendation_build_profile([]);
$r1 = slot_recommendation_rank($sharedPool, $p1, hours_index($sharedPool), $today);
assert_scenario('1. New customer, no history', $r1, function ($primary, $alts) use ($today, $alex) {
    expect($primary !== null, 'Need a primary slot');
    expect($primary['slot_date'] === $today && $primary['slot_time'] === '13:00:00', 'Primary should be earliest 13:00 today, got ' . summarize_slot($primary));
    expect((int)$primary['barber_id'] === $alex, 'Earliest barber should be Alex');
    expect($primary['reason_code'] === 'earliest', 'Must not claim a preference, got ' . $primary['reason_code']);
    expect(!reason_claims_usual($primary), 'New customer must not see "usual"');
    expect(count($alts) === 2, 'Need 2 alternatives, got ' . count($alts));
    foreach ($alts as $alt) {
        expect(!reason_claims_usual($alt), 'Alternative must not claim usual: ' . ($alt['reason_code'] ?? ''));
    }
});

// 2. Usual evening
$eveningHistory = [
    history($alex, '2026-07-03', '18:00:00', 'Alex'), // Fri
    history($miguel, '2026-07-10', '17:00:00', 'Miguel'),
    history($alex, '2026-07-22', '18:00:00', 'Alex'),
    history($miguel, '2026-08-05', '19:00:00', 'Miguel'),
    history($alex, '2026-08-12', '18:00:00', 'Alex'),
];
$p2 = slot_recommendation_build_profile($eveningHistory);
$r2 = slot_recommendation_rank($sharedPool, $p2, hours_index($sharedPool), $today);
assert_scenario('2. Usual evening bookings', $r2, function ($primary, $alts) use ($p2, $today) {
    expect($p2['preferred_bucket'] === 'evening' && $p2['preferred_bucket_usual'] === true, 'Profile should mark evening as usual');
    expect($primary['time_bucket'] === 'evening', 'Primary should be evening, got ' . summarize_slot($primary));
    expect($primary['slot_date'] === $today, 'Prefer this evening over later evenings: ' . summarize_slot($primary));
    expect($primary['reason_code'] === 'usual_time' || $primary['reason_code'] === 'usual_barber_and_time', 'Expect usual time reason, got ' . $primary['reason_code']);
    expect(!str_contains($primary['suggestionReason'], 'weekend'), 'Should not invent weekend preference');
});

// 3. Usual weekend
$weekendHistory = [
    history($alex, '2026-07-04', '10:00:00', 'Alex'), // Sat
    history($alex, '2026-07-11', '10:00:00', 'Alex'),
    history($miguel, '2026-07-19', '10:00:00', 'Miguel'), // Sun
    history($alex, '2026-07-25', '10:00:00', 'Alex'),
    history($alex, '2026-08-01', '10:00:00', 'Alex'),
    history($miguel, '2026-08-08', '10:00:00', 'Miguel'),
];
$p3 = slot_recommendation_build_profile($weekendHistory);
$r3 = slot_recommendation_rank($sharedPool, $p3, hours_index($sharedPool), $today);
assert_scenario('3. Usual weekend bookings', $r3, function ($primary, $alts) use ($p3, $sat, $sun) {
    expect($p3['preferred_weekday_usual'] === true, 'Saturday should be usual weekday');
    expect($p3['preferred_weekday'] === 6, 'Mode weekday should be Saturday, got ' . json_encode($p3['preferred_weekday']));
    expect(in_array($primary['slot_date'], [$sat, $sun], true), 'Primary should be weekend, got ' . summarize_slot($primary));
    expect($primary['reason_code'] === 'usual_day' || $primary['reason_code'] === 'usual_time' || $primary['reason_code'] === 'usual_barber_and_time', 'Weekend/time reason, got ' . $primary['reason_code']);
    expect($primary['reason_code'] !== 'earliest', 'Should not fall back to earliest weekday slot');
});

// 4. Preferred barber
$barberHistory = [
    history($miguel, '2026-07-01', '10:00:00', 'Miguel'), // Wed morning
    history($miguel, '2026-07-10', '18:00:00', 'Miguel'), // Fri evening
    history($miguel, '2026-07-21', '11:00:00', 'Miguel'), // Tue morning
    history($miguel, '2026-08-08', '17:00:00', 'Miguel'), // Sat evening
];
$p4 = slot_recommendation_build_profile($barberHistory);
$r4 = slot_recommendation_rank($sharedPool, $p4, hours_index($sharedPool), $today);
assert_scenario('4. Preferred / frequent barber', $r4, function ($primary, $alts) use ($p4, $miguel, $today) {
    expect($p4['preferred_barber_id'] === $miguel && $p4['preferred_barber_usual'] === true, 'Miguel should be usual barber');
    expect((int)$primary['barber_id'] === $miguel, 'Primary should be Miguel, got ' . summarize_slot($primary));
    expect($primary['slot_date'] === $today, 'Use Miguel today rather than later: ' . summarize_slot($primary));
    expect($primary['reason_code'] === 'usual_barber' || $primary['reason_code'] === 'usual_barber_and_time', 'Usual barber reason, got ' . $primary['reason_code']);
});

// 5. Preferred barber unavailable
$noMiguel = array_values(array_filter($sharedPool, static fn(array $s): bool => (int)$s['barber_id'] !== 7));
$p5 = slot_recommendation_build_profile($barberHistory);
$r5 = slot_recommendation_rank($noMiguel, $p5, hours_index($noMiguel), $today);
assert_scenario('5. Preferred barber unavailable', $r5, function ($primary, $alts) use ($miguel) {
    expect((int)$primary['barber_id'] !== $miguel, 'Must not invent Miguel slots');
    expect($primary['reason_code'] !== 'usual_barber' && $primary['reason_code'] !== 'usual_barber_and_time', 'Must not claim usual barber when they have no slot, got ' . $primary['reason_code']);
    expect($primary['reason_code'] === 'earliest', 'Fall back to earliest, got ' . $primary['reason_code']);
    expect($primary['slot_time'] === '13:00:00', 'Earliest remaining should be 13:00, got ' . summarize_slot($primary));
});

// 6. Preferred barber only several days later vs sooner suitable slot
$p6 = slot_recommendation_build_profile(array_merge($eveningHistory, [
    history($miguel, '2026-07-01', '18:00:00', 'Miguel'),
    history($miguel, '2026-07-15', '18:00:00', 'Miguel'),
    history($miguel, '2026-08-01', '17:00:00', 'Miguel'),
]));
$pool6 = [
    slot($alex, 'Alex', $today, '17:00:00'),
    slot($alex, 'Alex', $today, '13:00:00'),
    slot($miguel, 'Miguel', $nextWed, '17:00:00'),
    slot($alex, 'Alex', $thu, '18:00:00'),
];
$r6 = slot_recommendation_rank($pool6, $p6, hours_index($pool6), $today);
assert_scenario('6. Preferred barber only much later', $r6, function ($primary, $alts) use ($miguel, $today, $nextWed) {
    expect((int)$primary['barber_id'] !== $miguel || $primary['slot_date'] !== $nextWed, 'Must not wait a week for usual barber when a sooner evening exists: ' . summarize_slot($primary));
    expect($primary['time_bucket'] === 'evening' && $primary['slot_date'] === $today, 'Sooner evening should win, got ' . summarize_slot($primary));
    $altHasLaterMiguel = false;
    foreach ($alts as $alt) {
        if ((int)$alt['barber_id'] === $miguel && $alt['slot_date'] === $nextWed) {
            $altHasLaterMiguel = true;
        }
    }
    expect($altHasLaterMiguel, 'Later Miguel slot should appear as an alternative');
    expect($primary['reason_code'] !== 'usual_barber', 'Primary should not be usual-barber-only');
});

// 7. Mixed / inconsistent history
$mixed = [
    history($alex, '2026-06-01', '10:00:00', 'Alex'), // Mon
    history($miguel, '2026-06-16', '18:00:00', 'Miguel'), // Tue
    history($alex, '2026-07-01', '14:00:00', 'Alex'), // Wed
    history($miguel, '2026-07-09', '10:00:00', 'Miguel'), // Thu
    history($alex, '2026-07-17', '17:00:00', 'Alex'), // Fri
    history($miguel, '2026-08-08', '13:00:00', 'Miguel'), // Sat
];
$p7 = slot_recommendation_build_profile($mixed);
$r7 = slot_recommendation_rank($sharedPool, $p7, hours_index($sharedPool), $today);
assert_scenario('7. Mixed inconsistent history', $r7, function ($primary, $alts) use ($p7) {
    expect($p7['preferred_bucket_usual'] === false, 'Must not mark a usual time bucket');
    expect($p7['preferred_weekday_usual'] === false, 'Must not mark a usual weekday');
    expect($p7['preferred_barber_usual'] === false, 'Must not mark a usual barber when tied/mixed');
    expect($primary['reason_code'] === 'earliest', 'Claim earliest, not a fabricated usual, got ' . $primary['reason_code']);
    expect(!reason_claims_usual($primary), 'Reason must not say usual');
    expect($primary['slot_time'] === '13:00:00', 'Fall back to earliest, got ' . summarize_slot($primary));
});

// 8. Single previous appointment
$p8 = slot_recommendation_build_profile([
    history($miguel, '2026-08-21', '18:00:00', 'Miguel'), // last Friday evening
]);
$r8 = slot_recommendation_rank($sharedPool, $p8, hours_index($sharedPool), $today);
assert_scenario('8. Only one previous appointment', $r8, function ($primary, $alts) use ($p8, $today) {
    expect($p8['visit_count'] === 1, 'One visit');
    expect($p8['preferred_bucket_usual'] === false, 'One visit is not "usual" time');
    expect($p8['preferred_barber_usual'] === false, 'One visit is not "usual" barber');
    expect($p8['preferred_weekday_usual'] === false, 'One visit is not "usual" day');
    expect(!reason_claims_usual($primary), 'Must not say usual, got ' . $primary['reason_code'] . ' / ' . $primary['suggestionReason']);
    expect($primary['time_bucket'] === 'evening', 'Should still lean toward last evening time, got ' . summarize_slot($primary));
    expect($primary['slot_date'] === $today, 'Should not wait until Friday for one past visit: ' . summarize_slot($primary));
    expect(in_array($primary['reason_code'], ['last_time', 'last_barber', 'earliest'], true), 'Weak last-appointment or earliest, got ' . $primary['reason_code']);
});

echo "Smart appointment ranking scenarios\n";
echo "Weights: " . json_encode(slot_recommendation_config(), JSON_UNESCAPED_SLASHES) . "\n\n";

foreach ($reports as $report) {
    $status = $report['ok'] ? 'PASS' : 'FAIL';
    echo "[{$status}] {$report['name']}\n";
    echo "  Primary: " . summarize_slot($report['primary']) . "\n";
    echo "  Reason:  " . ($report['primary']['suggestionReason'] ?? '') . "\n";
    foreach ($report['alternatives'] as $i => $alt) {
        echo "  Alt " . ($i + 1) . ":   " . summarize_slot($alt) . "\n";
    }
    foreach ($report['messages'] as $message) {
        echo "  ERROR: {$message}\n";
    }
    echo "\n";
}

if ($failures > 0) {
    fwrite(STDERR, "Failed {$failures} scenario(s).\n");
    exit(1);
}

echo "All 8 scenarios passed.\n";
exit(0);
