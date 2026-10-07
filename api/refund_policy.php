<?php
// When a cancelled booking earns its money back, and when it does not.
//
// Two separate rules live here:
//
//   1. Notice. A booking cancelled inside the notice window still cancels --
//      the chair is freed for someone else, which is the outcome the shop
//      wants -- but it raises no refund.
//
//   2. Abuse. Nothing counted how often one account did book-pay-cancel, so a
//      customer could run the loop indefinitely and the desk paid out by hand
//      every time. There is no gateway refund in this system; every one of
//      these costs a person at the counter real money and real time.
//
// Both are read through refund_policy_decision(), so the cancel endpoint, the
// quote endpoint and the appointment list cannot drift apart on the answer.

declare(strict_types=1);

require_once __DIR__ . '/shop_schedule.php';

/**
 * Hours of notice required for a refund.
 *
 * Cancelling later than this still releases the slot; it just is not refunded.
 */
function shop_refund_notice_hours(): int
{
    return 24;
}

/**
 * Burst rule: this many refunds inside REFUND_BURST_WINDOW_HOURS trips a
 * cooldown. Three paid cancellations in a day is not a customer having a bad
 * week, and a genuine one essentially never does it -- so this can block
 * confidently.
 */
const REFUND_BURST_LIMIT = 3;
const REFUND_BURST_WINDOW_HOURS = 24;
const REFUND_BURST_COOLDOWN_DAYS = 7;

/**
 * Sustained rule: the burst rule alone is evaded by spacing attempts out --
 * two a day, forever, never trips it. This is the backstop.
 */
const REFUND_SUSTAINED_LIMIT = 5;
const REFUND_SUSTAINED_WINDOW_DAYS = 30;
const REFUND_SUSTAINED_COOLDOWN_DAYS = 30;

/**
 * How many refunds this customer has had, and whether that puts them in a
 * cooldown right now.
 *
 * Counts Pending as well as Completed: a Pending row is money already owed,
 * and waiting for the desk to pay out would let someone fire off ten
 * cancellations before the first one settled.
 *
 * @return array{used24h:int, used30d:int, blocked:bool, cooldownUntil:?string,
 *                reason:?string, limitBurst:int, limitSustained:int}
 */
function refund_policy_status(PDO $pdo, int $userId): array
{
    $status = [
        'used24h' => 0,
        'used30d' => 0,
        'blocked' => false,
        'cooldownUntil' => null,
        'reason' => null,
        'limitBurst' => REFUND_BURST_LIMIT,
        'limitSustained' => REFUND_SUSTAINED_LIMIT,
    ];

    if ($userId <= 0) {
        return $status;
    }

    // The newest refund in each window is what the cooldown counts from, so
    // the clock starts at the offence rather than at the moment of asking.
    $stmt = $pdo->prepare(
        "SELECT
            COUNT(*) FILTER (
                WHERE created_at >= NOW() - make_interval(hours => :burst_hours)
            )::int AS used_burst,
            COUNT(*) FILTER (
                WHERE created_at >= NOW() - make_interval(days => :sustained_days)
            )::int AS used_sustained,
            MAX(created_at) FILTER (
                WHERE created_at >= NOW() - make_interval(hours => :burst_hours2)
            ) AS latest_burst,
            MAX(created_at) FILTER (
                WHERE created_at >= NOW() - make_interval(days => :sustained_days2)
            ) AS latest_sustained
         FROM appointment_refunds
         WHERE user_id = :user_id
           AND status IN ('Pending', 'Completed')"
    );
    $stmt->execute([
        ':user_id' => $userId,
        ':burst_hours' => REFUND_BURST_WINDOW_HOURS,
        ':burst_hours2' => REFUND_BURST_WINDOW_HOURS,
        ':sustained_days' => REFUND_SUSTAINED_WINDOW_DAYS,
        ':sustained_days2' => REFUND_SUSTAINED_WINDOW_DAYS,
    ]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $status['used24h'] = (int)($row['used_burst'] ?? 0);
    $status['used30d'] = (int)($row['used_sustained'] ?? 0);

    $tz = new DateTimeZone(shop_timezone());

    if ($status['used24h'] >= REFUND_BURST_LIMIT && !empty($row['latest_burst'])) {
        $until = (new DateTimeImmutable((string)$row['latest_burst']))
            ->setTimezone($tz)
            ->modify('+' . REFUND_BURST_COOLDOWN_DAYS . ' days');
        $status['blocked'] = true;
        $status['cooldownUntil'] = $until->format(DateTimeInterface::ATOM);
        $status['reason'] = 'You have had ' . $status['used24h'] . ' refunds in the last '
            . REFUND_BURST_WINDOW_HOURS . ' hours. Refunds pause until '
            . $until->format('j M Y') . '. You can still book and still cancel.';

        return $status;
    }

    if ($status['used30d'] >= REFUND_SUSTAINED_LIMIT && !empty($row['latest_sustained'])) {
        $until = (new DateTimeImmutable((string)$row['latest_sustained']))
            ->setTimezone($tz)
            ->modify('+' . REFUND_SUSTAINED_COOLDOWN_DAYS . ' days');
        $status['blocked'] = true;
        $status['cooldownUntil'] = $until->format(DateTimeInterface::ATOM);
        $status['reason'] = 'You have had ' . $status['used30d'] . ' refunds in the last '
            . REFUND_SUSTAINED_WINDOW_DAYS . ' days. Refunds pause until '
            . $until->format('j M Y') . '. You can still book and still cancel.';

        return $status;
    }

    return $status;
}

/**
 * When this appointment actually starts, in shop time.
 *
 * shop_slot_start_datetime() returns null for anything it does not consider a
 * bookable slot -- a break hour, or a time outside opening hours. That is the
 * right answer when picking a slot to book and the wrong one here: a null made
 * the notice check skip entirely and the booking came back refundable. A row
 * whose hour looks odd is exactly the row that should not fail open, so this
 * falls back to reading the stored date and time literally.
 */
function refund_appointment_start(array $appt): ?DateTimeImmutable
{
    $date = shop_pdo_date_ymd($appt['appointment_date'] ?? '');
    $time = shop_pdo_time_hms($appt['start_time'] ?? '');
    if ($date === '' || $time === '') {
        return null;
    }

    $slot = shop_slot_start_datetime($date, $time);
    if ($slot !== null) {
        return $slot;
    }

    $literal = DateTimeImmutable::createFromFormat(
        'Y-m-d H:i:s',
        $date . ' ' . $time,
        new DateTimeZone(shop_timezone())
    );

    return $literal === false ? null : $literal;
}

/**
 * Whether this appointment, cancelled now, earns a refund.
 *
 * @param array<string, mixed> $appt a row carrying appointment_date + start_time
 * @return array{refundable:bool, reason:?string, deadline:?string,
 *                hoursRemaining:?float, policy:string}
 */
function refund_policy_decision(PDO $pdo, array $appt, int $userId): array
{
    $noticeHours = shop_refund_notice_hours();
    $start = refund_appointment_start($appt);

    $decision = [
        'refundable' => true,
        'reason' => null,
        'deadline' => null,
        'hoursRemaining' => null,
        'policy' => 'ok',
    ];

    if ($start !== null && $noticeHours > 0) {
        $deadline = $start->modify('-' . $noticeHours . ' hours');
        $now = shop_now();
        $decision['deadline'] = $deadline->format(DateTimeInterface::ATOM);
        $decision['hoursRemaining'] = round(($deadline->getTimestamp() - $now->getTimestamp()) / 3600, 1);

        if ($now > $deadline) {
            $decision['refundable'] = false;
            $decision['policy'] = 'late';
            $decision['reason'] = 'Refunds close ' . $noticeHours
                . ' hours before the appointment. You can still cancel to free the slot, '
                . 'but this booking is no longer refundable.';

            return $decision;
        }
    }

    $abuse = refund_policy_status($pdo, $userId);
    if ($abuse['blocked']) {
        $decision['refundable'] = false;
        $decision['policy'] = 'cooldown';
        $decision['reason'] = $abuse['reason'];
    }

    return $decision;
}
