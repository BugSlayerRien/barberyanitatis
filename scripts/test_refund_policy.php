<?php

declare(strict_types=1);

/**
 * Guards when a cancelled booking earns its money back.
 *
 * Before this there were no rules at all: a booking cancelled ten minutes
 * before the chair was due raised a full refund, and nothing counted how often
 * one account ran book-pay-cancel. Every refund costs a person at the counter
 * real money, by hand -- there is no gateway refund in this system.
 *
 * Every scenario writes refund rows inside a transaction that is always rolled
 * back; no real refund is created.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/refund_policy.php';

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

echo "Refund policy checks\n";

$pdo = get_db_connection();

/**
 * An appointment row shaped like the ones booking.php reads, N hours out.
 *
 * Minutes are kept rather than rounded to the hour: truncating moved the
 * appointment up to 59 minutes closer, so the 24.5-hour case fell inside the
 * window and the test failed depending on what time of day it ran.
 */
function appointment_in(float $hoursFromNow): array
{
    $when = shop_now()->modify(sprintf('%+d minutes', (int)round($hoursFromNow * 60)));

    return [
        'appointment_date' => $when->format('Y-m-d'),
        'start_time' => $when->format('H:i:00'),
    ];
}

// --- the 24-hour notice window ----------------------------------------------
check('the notice window is 24 hours', shop_refund_notice_hours() === 24);

$far = refund_policy_decision($pdo, appointment_in(48), 0);
check('a booking 48 hours out is refundable', $far['refundable'] === true);
check('and carries the deadline for the app to show', $far['deadline'] !== null);
check('and reports hours left to decide', ($far['hoursRemaining'] ?? 0) > 20);

$soon = refund_policy_decision($pdo, appointment_in(12), 0);
check('a booking 12 hours out is NOT refundable', $soon['refundable'] === false);
check('and says why', str_contains((string)$soon['reason'], '24'));
check('and is flagged as late, not as abuse', $soon['policy'] === 'late');
check(
    'the wording makes clear cancelling is still allowed',
    str_contains(strtolower((string)$soon['reason']), 'still cancel')
);

$edgeInside = refund_policy_decision($pdo, appointment_in(23.5), 0);
check('23.5 hours out is inside the window and refused', $edgeInside['refundable'] === false);
$edgeOutside = refund_policy_decision($pdo, appointment_in(24.5), 0);
check('24.5 hours out still qualifies', $edgeOutside['refundable'] === true);

$past = refund_policy_decision($pdo, appointment_in(-3), 0);
check('an appointment already in the past is not refundable', $past['refundable'] === false);

// --- the abuse rules --------------------------------------------------------
$userId = (int)$pdo->query(
    'SELECT user_id FROM users ORDER BY user_id LIMIT 1'
)->fetchColumn();
check('a customer exists to test against', $userId > 0);

$appointmentId = (int)$pdo->query(
    'SELECT appointment_id FROM appointments ORDER BY appointment_id DESC LIMIT 1'
)->fetchColumn();

/**
 * Stamps $count refund rows $agoHours in the past for this customer and
 * returns the resulting policy status. Always rolled back.
 */
function status_after(PDO $pdo, int $userId, int $appointmentId, int $count, float $agoHours): array
{
    $pdo->beginTransaction();
    try {
        // Clear the slate so an existing history cannot mask the result.
        $pdo->prepare('DELETE FROM appointment_refunds WHERE user_id = :u')
            ->execute([':u' => $userId]);

        $insert = $pdo->prepare(
            "INSERT INTO appointment_refunds
                (appointment_id, user_id, amount, reason, status, created_at)
             VALUES (:a, :u, 300, 'test', 'Pending',
                     NOW() - make_interval(mins => :mins))"
        );
        for ($i = 0; $i < $count; $i++) {
            $insert->execute([
                ':a' => $appointmentId,
                ':u' => $userId,
                // Spread them slightly so they are distinct events.
                ':mins' => (int)round($agoHours * 60) + $i,
            ]);
        }

        return refund_policy_status($pdo, $userId);
    } finally {
        $pdo->rollBack();
    }
}

if ($userId > 0 && $appointmentId > 0) {
    $two = status_after($pdo, $userId, $appointmentId, 2, 2);
    check('two refunds in a day is not abuse', $two['blocked'] === false);
    check('but they are counted', $two['used24h'] === 2);

    $three = status_after($pdo, $userId, $appointmentId, 3, 2);
    check('three refunds in a day trips the burst rule', $three['blocked'] === true);
    check('and a cooldown date is set', $three['cooldownUntil'] !== null);
    check('and the customer is told they can still cancel',
        str_contains(strtolower((string)$three['reason']), 'still book'));

    // 30 hours ago is outside the 24-hour burst window but inside 30 days.
    $spread = status_after($pdo, $userId, $appointmentId, 3, 30);
    check('three refunds spread beyond a day do NOT trip the burst rule', $spread['blocked'] === false);
    check('they still count towards the monthly total', $spread['used30d'] === 3);
    check('and not towards the daily one', $spread['used24h'] === 0);

    $sustained = status_after($pdo, $userId, $appointmentId, 5, 72);
    check('five refunds in a month trips the sustained rule', $sustained['blocked'] === true);

    // Older than both windows: a customer with history is not punished forever.
    $old = status_after($pdo, $userId, $appointmentId, 6, 24 * 45);
    check('refunds older than 30 days are forgotten', $old['blocked'] === false);
    check('and no longer counted', $old['used30d'] === 0);

    // The notice rule and the abuse rule must both be able to refuse.
    $pdo->beginTransaction();
    try {
        $pdo->prepare('DELETE FROM appointment_refunds WHERE user_id = :u')->execute([':u' => $userId]);
        $insert = $pdo->prepare(
            "INSERT INTO appointment_refunds (appointment_id, user_id, amount, reason, status, created_at)
             VALUES (:a, :u, 300, 'test', 'Pending', NOW() - make_interval(mins => :mins))"
        );
        for ($i = 0; $i < 3; $i++) {
            $insert->execute([':a' => $appointmentId, ':u' => $userId, ':mins' => 60 + $i]);
        }
        $blocked = refund_policy_decision($pdo, appointment_in(72), $userId);
        check('a cooldown refuses even a booking three days out', $blocked['refundable'] === false);
        check('and is flagged as a cooldown, not as late', $blocked['policy'] === 'cooldown');
    } finally {
        $pdo->rollBack();
    }
}

check('an anonymous user has no history to block on', refund_policy_status($pdo, 0)['blocked'] === false);

// --- nothing was actually written -------------------------------------------
$leaked = (int)$pdo->query(
    "SELECT COUNT(*) FROM appointment_refunds WHERE reason = 'test'"
)->fetchColumn();
check('no test refund survived the rollback', $leaked === 0);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
