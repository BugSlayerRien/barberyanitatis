<?php

declare(strict_types=1);

/**
 * The walk-in / appointment split is retired. This file guards that it stays
 * retired.
 *
 * It used to check both sides of the split, through a helper
 * (queue_merge_set_for_request) that had already been removed -- so it had been
 * dying on a fatal error rather than testing anything.
 *
 * The behaviour it covered now lives in test_queue_merge_agreement.php, which
 * checks the thing that actually broke: a barber the suggestion screen offered
 * and the booking screen then refused.
 */

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

echo "Queue split retired\n";

check('the appointment filter adds nothing',
    barber_channel_filter_sql('appointment') === '');
check('the walk-in filter adds nothing',
    barber_channel_filter_sql('walk_in') === '');
check('an aliased column makes no difference',
    barber_channel_filter_sql('walk_in', 'b.barber_channel') === '');
check('every barber is reported as working both queues',
    queue_merge_enabled() === true);

// The channel is still stored: it records where a barber mainly works, and the
// kiosk and the portal label them with it. Only the filtering is gone.
check('the channel is still a real value', normalize_barber_channel('walk_in') === 'walk_in');
check('and still normalised from its spellings',
    normalize_barber_channel('WalkIn') === 'walk_in'
    && normalize_barber_channel('appointments') === 'appointment');
check('and nonsense is still rejected', normalize_barber_channel('sideburns') === null);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
