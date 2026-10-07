<?php

declare(strict_types=1);

/**
 * Guards the barber paid-leave cap.
 *
 * Leave was uncapped. Nothing in the codebase counted a barber's days, so one
 * could file unlimited paid days off and the receptionist approving them had
 * no figure in front of them.
 *
 * Leave is stored one row per day, so counting is a plain COUNT -- the subtle
 * parts are which statuses count (Pending does, Rejected and Expired do not),
 * and that re-submitting a day already held is an edit rather than a second
 * day. Both are covered below.
 *
 * Every scenario writes inside a transaction that is always rolled back.
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

echo "Barber paid-leave balance checks\n";

$pdo = get_db_connection();
$allowance = shop_barber_annual_leave_days();
check('the allowance is 24 days', $allowance === 24);

$barberId = (int)$pdo->query(
    'SELECT barber_id FROM barbers WHERE is_active = TRUE ORDER BY barber_id LIMIT 1'
)->fetchColumn();
check('an active barber exists to test against', $barberId > 0);

// Next year, so the fixtures cannot collide with real leave already filed.
$year = (int)shop_now()->format('Y') + 1;

/**
 * Files $count leave days in $year with the given status and returns the
 * resulting balance. Always rolled back.
 *
 * @param array<int, string> $extraStatuses status => how many more to file
 */
function balance_after(
    PDO $pdo,
    int $barberId,
    int $year,
    int $count,
    string $status = 'Approved',
    array $extra = [],
    string $excludeDate = ''
): array {
    $pdo->beginTransaction();
    try {
        $insert = $pdo->prepare(
            "INSERT INTO barber_unavailability_requests (barber_id, request_date, note, status)
             VALUES (:barber_id, :request_date, 'leave-cap test', :status)
             ON CONFLICT (barber_id, request_date)
             DO UPDATE SET status = EXCLUDED.status"
        );

        $day = 0;
        for ($i = 0; $i < $count; $i++) {
            $day++;
            $insert->execute([
                ':barber_id' => $barberId,
                ':request_date' => sprintf('%04d-01-%02d', $year, $day),
                ':status' => $status,
            ]);
        }
        foreach ($extra as $extraStatus => $extraCount) {
            for ($i = 0; $i < $extraCount; $i++) {
                $day++;
                $insert->execute([
                    ':barber_id' => $barberId,
                    ':request_date' => sprintf('%04d-01-%02d', $year, $day),
                    ':status' => $extraStatus,
                ]);
            }
        }

        return barber_leave_balance($pdo, $barberId, $year, $excludeDate);
    } finally {
        $pdo->rollBack();
    }
}

if ($barberId > 0) {
    $fresh = barber_leave_balance($pdo, $barberId, $year);
    check('a barber starts the year with the full allowance', $fresh['remaining'] === $allowance);
    check('and nothing used', $fresh['used'] === 0);

    $five = balance_after($pdo, $barberId, $year, 5);
    check('five approved days leave 19', $five['remaining'] === $allowance - 5);
    check('and are counted as approved', $five['approved'] === 5);

    // The decision you made: a request awaiting approval still spends the day,
    // so a barber cannot queue thirty pending days past the cap.
    $pending = balance_after($pdo, $barberId, $year, 5, 'Pending');
    check('a pending request reduces the balance', $pending['remaining'] === $allowance - 5);
    check('and is reported separately from approved', $pending['pending'] === 5);

    $mixed = balance_after($pdo, $barberId, $year, 3, 'Approved', ['Pending' => 2]);
    check('pending and approved add up together', $mixed['used'] === 5);

    $refused = balance_after($pdo, $barberId, $year, 0, 'Approved', ['Rejected' => 4, 'Expired' => 3]);
    check('rejected days do not count', $refused['used'] === 0);
    check('expired days do not count', $refused['remaining'] === $allowance);

    $full = balance_after($pdo, $barberId, $year, $allowance);
    check('the full allowance leaves nothing', $full['remaining'] === 0);
    check('and used equals the allowance', $full['used'] === $allowance);

    $over = balance_after($pdo, $barberId, $year, $allowance + 3);
    check('remaining never goes negative', $over['remaining'] === 0);

    // The upsert case: re-sending a day already held must not spend a second.
    $resubmit = balance_after(
        $pdo, $barberId, $year, $allowance, 'Approved', [], sprintf('%04d-01-01', $year)
    );
    check(
        're-submitting a day already held does not double-count',
        $resubmit['remaining'] === 1
    );

    // Year boundary: the cap is per calendar year.
    $nextYear = balance_after($pdo, $barberId, $year, 10);
    $otherYear = barber_leave_balance($pdo, $barberId, $year + 1);
    check('a different year is unaffected', $otherYear['remaining'] === $allowance);
    check('the balance reports the year it covers', $nextYear['year'] === $year);
}

// --- nothing leaked ---------------------------------------------------------
$leaked = (int)$pdo->query(
    "SELECT COUNT(*) FROM barber_unavailability_requests WHERE note = 'leave-cap test'"
)->fetchColumn();
check('no test leave row survived the rollback', $leaked === 0);

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
