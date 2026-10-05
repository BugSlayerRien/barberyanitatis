<?php

declare(strict_types=1);

/**
 * Guards the queue merge toggle's read side.
 *
 * The receptionist dashboard used to hardcode the channel split in its own two
 * queries instead of going through barber_channel_filter_sql(). With the
 * queues merged the kiosk offers every barber, so a walk-in served by an
 * Exclusive barber was filtered out of Live tracking and simply never
 * appeared -- while the Walk-ins stat card, which does not filter, counted it.
 *
 * These checks run without a database.
 */

require_once __DIR__ . '/../api/barber_channel.php';

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

echo "Queue merge read-side checks\n";

// --- the filter helper itself -------------------------------------------
queue_merge_set_for_request(false);
check(
    'split: walk-in filter restricts to the walk_in channel',
    barber_channel_filter_sql('walk_in', 'b.barber_channel') === " AND b.barber_channel = 'walk_in'"
);
check(
    'split: appointment filter restricts to the appointment channel',
    barber_channel_filter_sql('appointment', 'b.barber_channel') === " AND b.barber_channel = 'appointment'"
);

queue_merge_set_for_request(true);
check(
    'merged: walk-in filter drops away entirely',
    barber_channel_filter_sql('walk_in', 'b.barber_channel') === ''
);
check(
    'merged: appointment filter drops away entirely',
    barber_channel_filter_sql('appointment', 'b.barber_channel') === ''
);
queue_merge_reset();

// --- the receptionist dashboard must NOT filter by channel ---------------
// Channel decides which barbers a customer may pick. It must not decide what
// the floor can see: while merged, the kiosk offers every barber, so walk-ins
// land on Exclusive barbers -- and a channel predicate here made them vanish
// from Live tracking mid-haircut the moment merge was switched off.
$source = (string)file_get_contents(__DIR__ . '/../api/receptionist.php');
// Anchored on the two dashboard queries themselves rather than the action
// name, which is quoted in the source and awkward to match.
$queryStart = strpos($source, '$appointmentsStmt = $pdo->prepare(');
$queryEnd = strpos($source, '$walkinsStmt->execute()');
$dashboard = $queryStart !== false && $queryEnd !== false && $queryEnd > $queryStart
    ? substr($source, $queryStart, $queryEnd - $queryStart)
    : '';

check('both dashboard queries were located', $dashboard !== '');
check(
    'the dashboard reads carry no barber_channel predicate',
    strpos($dashboard, 'barber_channel') === false
);
check(
    'the dashboard reads do not call the channel filter helper',
    strpos($dashboard, 'barber_channel_filter_sql') === false
);

// An unassigned walk-in has no barber row at all, so any predicate reading a
// barber's channel would also have dropped everyone still waiting.
check(
    'nothing in the dashboard reads a barber channel',
    strpos($dashboard, 'b.barber_channel') === false
);

// The helper is still right everywhere a customer picks a barber.
foreach (['api/kiosk.php', 'api/booking.php'] as $pickSite) {
    check(
        $pickSite . ' still filters who can be picked',
        strpos((string)file_get_contents(__DIR__ . '/../' . $pickSite), 'barber_channel_filter_sql') !== false
    );
}

echo "\n{$checks} checks, {$failures} failed\n";
exit($failures === 0 ? 0 : 1);
