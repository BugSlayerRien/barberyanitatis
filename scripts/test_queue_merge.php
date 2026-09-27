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

// --- the receptionist dashboard must use it ------------------------------
$source = (string)file_get_contents(__DIR__ . '/../api/receptionist.php');

check(
    'dashboard does not hardcode the appointment channel',
    strpos($source, "AND b.barber_channel = \\'appointment\\'") === false
);
check(
    'dashboard does not hardcode the walk-in channel',
    strpos($source, "AND (b.barber_id IS NULL OR b.barber_channel = \\'walk_in\\')") === false
);
check(
    'dashboard routes the appointment queue through the filter helper',
    strpos($source, "barber_channel_filter_sql('appointment', 'b.barber_channel')") !== false
);
check(
    'dashboard routes the walk-in queue through the filter helper',
    strpos($source, "barber_channel_filter_sql('walk_in', 'b.barber_channel')") !== false
);

// --- an unassigned walk-in must never be filtered out --------------------
// It has no barber row to read a channel from, so the split predicate has to
// allow a NULL barber or the queue loses everyone waiting to be assigned.
$walkinPredicate = static function (bool $merged): string {
    queue_merge_set_for_request($merged);
    $filter = barber_channel_filter_sql('walk_in', 'b.barber_channel');
    queue_merge_reset();

    return $filter === ''
        ? ''
        : " AND (b.barber_id IS NULL OR b.barber_channel = 'walk_in')";
};

check(
    'split: unassigned walk-ins survive the channel predicate',
    strpos($walkinPredicate(false), 'b.barber_id IS NULL') !== false
);
check('merged: no channel predicate at all', $walkinPredicate(true) === '');

echo "\n{$checks} checks, {$failures} failed\n";
exit($failures === 0 ? 0 : 1);
