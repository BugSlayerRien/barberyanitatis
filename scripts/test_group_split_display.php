<?php

declare(strict_types=1);

/**
 * Guards how a split group is measured and displayed.
 *
 * A group booked across several barbers is stored correctly -- one appointments
 * row per member, each with its own barber_id -- but the receptionist card
 * collapsed it to the sequence-1 row and printed that barber alone, so a
 * four-way split looked like an ordinary single-barber booking. The same
 * collapse reported the duration as members x 60, which for a concurrent split
 * was four times the truth and made the tracking progress bar crawl.
 *
 * Also covers the wave option, which seats a party larger than the barber
 * count across two or more start times.
 *
 * Reads the live database. Everything runs inside a transaction that is always
 * rolled back, because the collapse may promote a paid booking unit.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/shop_schedule.php';
require_once __DIR__ . '/../api/group_booking.php';
require_once __DIR__ . '/../api/slot_locking.php';

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

echo "Group split display checks\n";

$pdo = get_db_connection();

/**
 * The member rows in the shape the receptionist dashboard query produces.
 *
 * @return list<array<string, mixed>>
 */
function group_rows(PDO $pdo, int $groupId): array
{
    $stmt = $pdo->prepare(
        "SELECT a.appointment_id, a.barber_id, a.booking_group_id,
                a.group_member_name, a.group_sequence,
                u.full_name AS name, u.full_name AS booker_name,
                'Haircut' AS service,
                a.appointment_date::text AS appointment_date,
                a.start_time::text AS time, a.end_time::text AS end_time,
                '60 min' AS duration, 60 AS estimated_minutes,
                a.checkin_time, 300 AS price, a.status,
                b.full_name AS barber,
                NULL AS payment_status, NULL AS intent_status
         FROM appointments a
         JOIN barbers b ON b.barber_id = a.barber_id
         JOIN users u ON u.user_id = a.user_id
         WHERE a.booking_group_id = :gid
         ORDER BY a.group_sequence"
    );
    $stmt->execute([':gid' => $groupId]);

    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

// A concurrent split: several barbers, one start time.
$splitGroupId = (int)$pdo->query(
    "SELECT booking_group_id
     FROM appointments
     WHERE booking_group_id IS NOT NULL
     GROUP BY booking_group_id
     HAVING COUNT(DISTINCT barber_id) > 1 AND COUNT(DISTINCT start_time) = 1
     ORDER BY booking_group_id DESC
     LIMIT 1"
)->fetchColumn();

// A consecutive block: one barber, several start times.
$blockGroupId = (int)$pdo->query(
    "SELECT booking_group_id
     FROM appointments
     WHERE booking_group_id IS NOT NULL
     GROUP BY booking_group_id
     HAVING COUNT(DISTINCT barber_id) = 1 AND COUNT(DISTINCT start_time) > 1
     ORDER BY booking_group_id DESC
     LIMIT 1"
)->fetchColumn();

$pdo->beginTransaction();
try {
    // --- the split group ----------------------------------------------------
    if ($splitGroupId > 0) {
        $rows = group_rows($pdo, $splitGroupId);
        $expectedBarbers = count(array_unique(array_column($rows, 'barber')));
        $collapsed = collapse_receptionist_appointments($pdo, $rows);

        check('a split group collapses to one card', count($collapsed) === 1);
        $card = $collapsed[0];

        check('the card is flagged as a split', ($card['is_split'] ?? false) === true);
        check(
            'every barber is named (' . $expectedBarbers . ' of them)',
            count($card['barbers'] ?? []) === $expectedBarbers
        );
        check(
            'the barber ids travel with the names',
            count($card['barber_ids'] ?? []) === $expectedBarbers
        );
        check(
            'the scalar barber is still the primary, for older readers',
            (string)($card['barber'] ?? '') === (string)$rows[0]['barber']
        );
        check(
            'no barber is listed twice',
            count(array_unique($card['barbers'] ?? [])) === count($card['barbers'] ?? [])
        );

        // The whole point: four people seen at once take one slot, not four.
        $slot = shop_appointment_duration_minutes();
        check(
            'a concurrent split lasts one appointment, not members x one',
            (int)($card['estimated_minutes'] ?? 0) === $slot
        );
        check(
            'the duration label agrees',
            (string)($card['duration'] ?? '') === $slot . ' min'
        );
        check(
            'it is no longer the old members x 60',
            (int)($card['estimated_minutes'] ?? 0) !== count($rows) * 60 || count($rows) === 1
        );
    } else {
        echo "  SKIP  no concurrent split group in the database\n";
    }

    // --- the consecutive group ---------------------------------------------
    if ($blockGroupId > 0) {
        $rows = group_rows($pdo, $blockGroupId);
        $card = collapse_receptionist_appointments($pdo, $rows)[0];

        check('a single-barber block is not flagged as a split', ($card['is_split'] ?? true) === false);
        check('a single-barber block names one barber', count($card['barbers'] ?? []) === 1);

        // Wall clock, start of the first to the end of the last -- which counts
        // any lunch break the block spans, because the group really is still
        // there at that hour.
        $last = $rows[count($rows) - 1];
        $expectedSpan = booking_group_span_minutes(
            (string)$rows[0]['time'],
            shop_add_minutes_to_time((string)$last['time'], shop_appointment_duration_minutes())
        );
        check(
            'a consecutive block reports its real span (' . $expectedSpan . ' min)',
            (int)($card['estimated_minutes'] ?? 0) === $expectedSpan
        );
        check('the span covers more than one appointment', $expectedSpan > shop_appointment_duration_minutes());
    } else {
        echo "  SKIP  no consecutive single-barber group in the database\n";
    }

    // --- the span helper itself --------------------------------------------
    check('span of 09:00 to 10:00 is 60', booking_group_span_minutes('09:00:00', '10:00:00') === 60);
    check('span across a break is wall clock', booking_group_span_minutes('09:00:00', '15:00:00') === 360);
    check('a backwards span is rejected', booking_group_span_minutes('10:00:00', '09:00:00') === 0);
    check('an empty span is rejected', booking_group_span_minutes('', '') === 0);
} finally {
    $pdo->rollBack();
}

// --- the wave option --------------------------------------------------------
echo "\nWave option checks\n";

// A near, open day: Sunday is closed, so a Sunday would have no slots at all.
$day = new DateTimeImmutable('today', new DateTimeZone(shop_timezone()));
for ($i = 1; $i <= 8; $i++) {
    $candidate = $day->modify('+' . $i . ' days');
    if ((int)$candidate->format('w') !== 0) {
        $day = $candidate;
        break;
    }
}
$slotDate = $day->format('Y-m-d');
$freeMaps = [1 => [], 2 => [], 3 => [], 4 => []];
$names = [1 => 'One', 2 => 'Two', 3 => 'Three', 4 => 'Four'];

$waves = find_wave_barber_option($freeMaps, $slotDate, 5, $names);
check('5 people across 4 free barbers produces an option', $waves !== null);

if ($waves !== null) {
    $slots = $waves['slots'];
    check('every person gets a slot', count($slots) === 5);
    check('it is labelled as a wave booking', $waves['type'] === 'split_waves');

    $times = array_column($slots, 'slotTime');
    check('the party is seated in exactly two rounds', count(array_unique($times)) === 2);
    check('four go in the first round', count(array_keys($times, $times[0], true)) === 4);

    $pairs = array_map(
        static fn(array $slot): string => $slot['slotTime'] . '|' . $slot['barberID'],
        $slots
    );
    // The bug that would matter most: the same barber taking two people in the
    // same hour would double-book them.
    check('no barber is used twice in one round', count(array_unique($pairs)) === count($pairs));

    $sequences = array_column($slots, 'sequence');
    check('slots are numbered 1..n for the write path', $sequences === [1, 2, 3, 4, 5]);
    check('the waves summary matches the slots', array_sum(array_column($waves['waves'], 'count')) === 5);
}

check(
    'a party that fits in one round is left to the plain split',
    find_wave_barber_option($freeMaps, $slotDate, 3, $names) === null
);
check(
    'a party exactly the size of the roster is left to the plain split',
    find_wave_barber_option($freeMaps, $slotDate, 4, $names) === null
);

$nine = find_wave_barber_option($freeMaps, $slotDate, 9, $names);
check('nine people need three rounds', $nine !== null
    && count(array_unique(array_column($nine['slots'], 'slotTime'))) === 3);

// One barber booked solid still leaves three, so 5 people need two rounds of
// three and a half -- which is two rounds, not one.
$busy = $freeMaps;
foreach (group_slot_time_order($slotDate) as $time) {
    $busy[1][$time] = 'booked';
}
$withBusy = find_wave_barber_option($busy, $slotDate, 5, $names);
check('a fully booked barber is never assigned', $withBusy !== null
    && !in_array(1, array_column($withBusy['slots'], 'barberID'), true));
check('the rest of the party still fits', $withBusy !== null && count($withBusy['slots']) === 5);

check('no barbers at all yields nothing', find_wave_barber_option([], $slotDate, 5, []) === null);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
