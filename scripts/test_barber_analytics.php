<?php

declare(strict_types=1);

/**
 * Guards the barber Insights payload.
 *
 * The charts have no way of telling a wrong number from a right one, so the
 * invariants are asserted here instead: the day series covers the whole range
 * with no gaps, its totals agree with the headline figures, and the two numbers
 * that are easy to get quietly wrong -- completion rate and average service
 * time -- exclude what they are supposed to exclude.
 *
 * Reads the live database. The one write (a deliberately absurd service
 * duration) happens inside a transaction that is always rolled back.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/barber_analytics_lib.php';

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

echo "Barber analytics payload checks\n";

$pdo = get_db_connection();

// The busiest barber, so the assertions run against real volume rather than an
// empty set that would pass everything by default.
$busiest = (int)$pdo->query(
    'SELECT barber_id FROM appointments GROUP BY barber_id ORDER BY COUNT(*) DESC LIMIT 1'
)->fetchColumn();
check('a barber with appointments exists to test against', $busiest > 0);

$payload = barber_analytics_payload($pdo, $busiest, 30);
$totals = $payload['totals'];

// --- shape ------------------------------------------------------------------
foreach (['range', 'totals', 'statusMix', 'daily', 'hours', 'weekdays', 'topServices', 'ratings'] as $key) {
    check("payload carries '$key'", array_key_exists($key, $payload));
}

// --- the day series ---------------------------------------------------------
check('30-day range returns exactly 30 days', count($payload['daily']) === 30);

$dates = array_column($payload['daily'], 'date');
check('days are in ascending order', $dates === array_values(array_unique($dates)) && $dates[0] < $dates[29]);
check('the last day is the range end', end($dates) === $payload['range']['to']);

$gaps = 0;
for ($i = 1; $i < count($dates); $i++) {
    $expected = (new DateTimeImmutable($dates[$i - 1]))->modify('+1 day')->format('Y-m-d');
    if ($dates[$i] !== $expected) {
        $gaps++;
    }
}
// Quiet days must be present as zeros. Dropping them makes every chart read
// busier than the shop actually was.
check('no missing days in the series', $gaps === 0);

check(
    'daily booked sums to the headline booked count',
    array_sum(array_column($payload['daily'], 'booked')) === $totals['booked']
);
check(
    'daily completed sums to the headline completed count',
    array_sum(array_column($payload['daily'], 'completed')) === $totals['completed']
);
check(
    'daily walk-ins sum to the headline walk-in count',
    array_sum(array_column($payload['daily'], 'walkins')) === $totals['walkinsServed']
);
check('status mix sums to booked', array_sum($payload['statusMix']) === $totals['booked']);

// --- completion rate --------------------------------------------------------
$finished = $totals['completed'] + $totals['cancelled'] + $totals['noShow'];
$expectedRate = $finished > 0 ? (int)round(($totals['completed'] / $finished) * 100) : null;
check('completion rate is measured against finished bookings only', $totals['completionRate'] === $expectedRate);
check(
    'completion rate is null when nothing has finished, never 0%',
    $finished > 0 || $totals['completionRate'] === null
);
check(
    'open appointments are not counted as failures',
    $totals['open'] === 0 || $totals['completionRate'] !== (int)round(($totals['completed'] / max(1, $totals['booked'])) * 100)
    || $totals['completed'] + $totals['cancelled'] + $totals['noShow'] === $totals['booked']
);

// --- ratings ----------------------------------------------------------------
$ratings = $payload['ratings'];
check('rating distribution sums to the rating count', array_sum($ratings['distribution']) === $ratings['count']);
// PHP coerces numeric string keys to ints, so compare on the string form the
// JSON object actually carries to the app.
check('distribution covers 1 to 5', array_map('strval', array_keys($ratings['distribution'])) === ['1', '2', '3', '4', '5']);
check(
    'average is null when there are no ratings',
    $ratings['count'] > 0 ? is_float($ratings['average']) : $ratings['average'] === null
);
if ($ratings['count'] > 0) {
    check('average sits inside 1 to 5', $ratings['average'] >= 1 && $ratings['average'] <= 5);
}
check('every quoted comment is non-empty', !array_filter(
    $ratings['recent'],
    fn($r) => trim((string)$r['comment']) === ''
));

// --- range handling ---------------------------------------------------------
check('an unsupported range falls back to 30 days', barber_analytics_payload($pdo, $busiest, 999)['range']['days'] === 30);
check('a 7-day range returns 7 days', count(barber_analytics_payload($pdo, $busiest, 7)['daily']) === 7);
check('a 90-day range returns 90 days', count(barber_analytics_payload($pdo, $busiest, 90)['daily']) === 90);

// --- an unknown barber is empty, not an error -------------------------------
$empty = barber_analytics_payload($pdo, 0, 30);
check('unknown barber returns zero totals', $empty['totals']['booked'] === 0);
check('unknown barber still returns a full day series', count($empty['daily']) === 30);
check('unknown barber has no rating', $empty['ratings']['average'] === null);
check('unknown barber resolves to id 0', analytics_resolve_barber($pdo, 0, 'nobody@example.invalid')['id'] === 0);

// --- the average cut excludes impossible spans ------------------------------
// A session left open overnight produced a "12 hour average haircut" from real
// rows, which is why the query bounds the span.
$pdo->beginTransaction();
try {
    $target = $pdo->prepare(
        "SELECT appointment_id FROM appointments
         WHERE barber_id = :barber_id AND status = 'Completed'
           AND checkin_time IS NOT NULL AND completion_time IS NOT NULL
           AND appointment_date >= CURRENT_DATE - INTERVAL '29 days'
         LIMIT 1"
    );
    $target->execute([':barber_id' => $busiest]);
    $appointmentId = (int)($target->fetchColumn() ?: 0);

    if ($appointmentId > 0) {
        $before = barber_analytics_payload($pdo, $busiest, 30)['totals'];

        $pdo->prepare(
            "UPDATE appointments
             SET completion_time = checkin_time + INTERVAL '11 hours'
             WHERE appointment_id = :id"
        )->execute([':id' => $appointmentId]);

        $after = barber_analytics_payload($pdo, $busiest, 30)['totals'];

        check(
            'an 11-hour service is dropped from the average',
            $after['avgServiceSample'] === $before['avgServiceSample'] - 1
        );
        check(
            'the average itself does not blow up',
            $after['avgServiceMinutes'] === null
            || $after['avgServiceMinutes'] <= BARBER_ANALYTICS_MAX_SERVICE_MINUTES
        );
    } else {
        echo "  SKIP  no timed completed appointment in range to bound\n";
    }
} finally {
    $pdo->rollBack();
}

$restored = barber_analytics_payload($pdo, $busiest, 30)['totals'];
check('the rollback left the sample size as it was', $restored['avgServiceSample'] === $totals['avgServiceSample']);
check(
    'any reported average is inside the plausible band',
    $restored['avgServiceMinutes'] === null
    || ($restored['avgServiceMinutes'] > 0
        && $restored['avgServiceMinutes'] <= BARBER_ANALYTICS_MAX_SERVICE_MINUTES)
);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
