<?php

declare(strict_types=1);

/**
 * Guards when a group booking is considered finished.
 *
 * auto_complete_due_appointments() used to add up every member's service time,
 * so a four-way split -- four barbers cutting at once, done in an hour -- was
 * not due until four hours after check-in and sat in "Completing" all
 * afternoon. A group is finished when its last member is, which is wall clock:
 * how far the last member starts after the first, plus that member's own
 * service time.
 *
 * Every scenario writes check-in times inside a transaction that is always
 * rolled back; nothing here changes real bookings.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/shop_schedule.php';

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

echo "Group auto-complete checks\n";

$pdo = get_db_connection();
$slot = shop_appointment_duration_minutes();

/** A group whose members all start at the same time: a split across barbers. */
$concurrent = (int)$pdo->query(
    "SELECT booking_group_id FROM appointments
     WHERE booking_group_id IS NOT NULL
     GROUP BY booking_group_id
     HAVING COUNT(*) > 2 AND COUNT(DISTINCT start_time) = 1
     ORDER BY booking_group_id DESC LIMIT 1"
)->fetchColumn();

/** A group booked back to back with one barber. */
$consecutive = (int)$pdo->query(
    "SELECT booking_group_id FROM appointments
     WHERE booking_group_id IS NOT NULL
     GROUP BY booking_group_id
     HAVING COUNT(*) > 2 AND COUNT(DISTINCT start_time) > 2
     ORDER BY booking_group_id DESC LIMIT 1"
)->fetchColumn();

check('a concurrent split group exists to test against', $concurrent > 0);
check('a consecutive group exists to test against', $consecutive > 0);

/**
 * Puts one group in progress, checked in $minutesAgo ago, and reports whether
 * the automation then completes it. Always rolled back.
 */
function completes_after(PDO $pdo, int $groupId, int $minutesAgo): bool
{
    $pdo->beginTransaction();
    try {
        // Isolate the subject: every other in-progress group is parked so the
        // run cannot be satisfied by somebody else's booking.
        $pdo->exec("UPDATE appointments SET status = 'Scheduled' WHERE status = 'InProgress'");

        $pdo->prepare(
            "UPDATE appointments
             SET status = 'InProgress',
                 checkin_time = NOW() - make_interval(mins => :mins),
                 paused_at = NULL,
                 paused_seconds = 0
             WHERE booking_group_id = :gid"
        )->execute([':mins' => $minutesAgo, ':gid' => $groupId]);

        auto_complete_due_appointments($pdo, true);

        $remaining = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE booking_group_id = :gid AND status <> 'Completed'"
        );
        $remaining->execute([':gid' => $groupId]);

        return (int)$remaining->fetchColumn() === 0;
    } finally {
        $pdo->rollBack();
    }
}

if ($concurrent > 0) {
    $members = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointments WHERE booking_group_id = {$concurrent}"
    )->fetchColumn();

    echo "\n  concurrent split: group {$concurrent}, {$members} members at one start time\n";

    check(
        'still running ' . ($slot - 10) . ' minutes in',
        !completes_after($pdo, $concurrent, $slot - 10)
    );
    // The whole point: one hour, not members x one hour.
    check(
        'completes ' . ($slot + 10) . ' minutes in, not ' . ($members * $slot),
        completes_after($pdo, $concurrent, $slot + 10)
    );
    check(
        'would have been stuck under the old sum rule',
        $members * $slot > $slot + 10
    );
}

if ($consecutive > 0) {
    $spread = (int)$pdo->query(
        "SELECT EXTRACT(EPOCH FROM (MAX(start_time) - MIN(start_time))) / 60
         FROM appointments WHERE booking_group_id = {$consecutive}"
    )->fetchColumn();
    $span = $spread + $slot;

    echo "\n  consecutive block: group {$consecutive}, spans {$span} minutes\n";

    check(
        'a back-to-back group is NOT finished after one slot',
        !completes_after($pdo, $consecutive, $slot + 10)
    );
    check(
        'it is not finished ten minutes before its span either',
        !completes_after($pdo, $consecutive, $span - 10)
    );
    check(
        'it completes once the whole span has passed',
        completes_after($pdo, $consecutive, $span + 10)
    );
}

// --- a paused group is never swept -----------------------------------------
if ($concurrent > 0) {
    $pdo->beginTransaction();
    try {
        $pdo->exec("UPDATE appointments SET status = 'Scheduled' WHERE status = 'InProgress'");
        $pdo->prepare(
            "UPDATE appointments
             SET status = 'InProgress',
                 checkin_time = NOW() - make_interval(hours => 6),
                 paused_at = NOW()
             WHERE booking_group_id = :gid"
        )->execute([':gid' => $concurrent]);

        auto_complete_due_appointments($pdo, true);

        $stmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE booking_group_id = :gid AND status = 'Completed'"
        );
        $stmt->execute([':gid' => $concurrent]);
        check('a paused group is left alone however long it has run', (int)$stmt->fetchColumn() === 0);
    } finally {
        $pdo->rollBack();
    }
}

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
