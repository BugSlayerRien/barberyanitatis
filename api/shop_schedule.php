<?php
// Shared shop hours, slot generation, and appointment lifecycle helpers.

declare(strict_types=1);

require_once __DIR__ . '/payment_recording.php';

function shop_timezone(): string
{
    return 'Asia/Manila';
}

function shop_now(): DateTimeImmutable
{
    return new DateTimeImmutable('now', new DateTimeZone(shop_timezone()));
}

function shop_today(): string
{
    return shop_now()->format('Y-m-d');
}

function shop_current_time(): string
{
    return shop_now()->format('H:i:s');
}

function shop_open_time(): string
{
    return '09:00:00';
}

function shop_close_time(): string
{
    return '20:00:00';
}

function shop_slot_duration_minutes(): int
{
    return 60;
}

function shop_appointment_duration_minutes(): int
{
    return 60;
}

/** Reservation/payment hold length for unpaid appointments (minutes). */
function shop_reservation_hold_minutes(): int
{
    return 10;
}

function format_time_12h(string $time): string
{
    $normalized = shop_normalize_slot_time($time);
    if ($normalized === null) {
        $parts = explode(':', trim($time));
        if (count($parts) < 2) {
            return $time;
        }
        $hour = (int)$parts[0];
        $minute = (int)$parts[1];
    } else {
        $hour = (int)substr($normalized, 0, 2);
        $minute = (int)substr($normalized, 3, 2);
    }

    $suffix = $hour >= 12 ? 'PM' : 'AM';
    $hour12 = $hour % 12 === 0 ? 12 : $hour % 12;

    return sprintf('%d:%02d %s', $hour12, $minute, $suffix);
}

function format_time_range_12h(string $startTime, string $endTime): string
{
    return format_time_12h($startTime) . ' – ' . format_time_12h($endTime);
}

/**
 * Hourly slots from 9:00 AM through 7:00 PM start (each 1-hour block ends by 8:00 PM close).
 *
 * @return string[]
 */
/** Lunch break — no bookable slots at this hour. */
function shop_break_hours(): array
{
    return [12];
}

function shop_is_break_slot_time(string $time): bool
{
    $normalized = shop_normalize_slot_time($time);
    if ($normalized === null) {
        return false;
    }

    return in_array((int)substr($normalized, 0, 2), shop_break_hours(), true);
}

function shop_default_slot_times(): array
{
    $times = [];
    for ($hour = 9; $hour <= 19; $hour++) {
        if (in_array($hour, shop_break_hours(), true)) {
            continue;
        }
        $times[] = sprintf('%02d:00:00', $hour);
    }

    return $times;
}

/**
 * Normalize to on-the-hour shop slot (09:00–19:00) or null when invalid.
 */
function shop_normalize_slot_time(string $time): ?string
{
    $parts = explode(':', trim($time));
    if (count($parts) < 2) {
        return null;
    }

    $hour = (int)$parts[0];
    $minute = (int)$parts[1];
    if ($minute !== 0 || $hour < 9 || $hour > 19) {
        return null;
    }

    return sprintf('%02d:00:00', $hour);
}

function shop_is_allowed_slot_time(string $time): bool
{
    return shop_normalize_slot_time($time) !== null;
}

/** Minimum notice before a suggested “best” slot (earliest pick). */
function shop_booking_lead_hours(): int
{
    return 2;
}

/** Minimum notice to allow booking a slot in the calendar (1 hour gap). */
function shop_minimum_booking_lead_minutes(): int
{
    return 60;
}

/**
 * Earliest slot start used for suggestions (at least shop_booking_lead_hours from now).
 */
function shop_next_bookable_slot_start(): DateTimeImmutable
{
    $minimum = shop_now()->modify('+' . shop_booking_lead_hours() . ' hours');
    $minute = (int)$minimum->format('i');
    $second = (int)$minimum->format('s');
    if ($minute > 0 || $second > 0) {
        $minimum = $minimum->setTime((int)$minimum->format('H'), 0)->modify('+1 hour');
    }

    $hour = (int)$minimum->format('H');
    if ($hour < 9) {
        return $minimum->setTime(9, 0);
    }
    if ($hour > 19) {
        return $minimum->modify('+1 day')->setTime(9, 0);
    }

    return $minimum;
}

function shop_slot_start_datetime(string $slotDate, string $slotTime): ?DateTimeImmutable
{
    $normalized = shop_normalize_slot_time($slotTime);
    if ($normalized === null || shop_is_break_slot_time($normalized)) {
        return null;
    }

    $slotDateTime = DateTimeImmutable::createFromFormat(
        'Y-m-d H:i:s',
        $slotDate . ' ' . $normalized,
        new DateTimeZone(shop_timezone())
    );

    return $slotDateTime === false ? null : $slotDateTime;
}

function shop_earliest_bookable_slot_start(): DateTimeImmutable
{
    $minimum = shop_now()->modify('+' . shop_minimum_booking_lead_minutes() . ' minutes');
    $minute = (int)$minimum->format('i');
    $second = (int)$minimum->format('s');
    if ($minute > 0 || $second > 0) {
        $minimum = $minimum->setTime((int)$minimum->format('H'), 0)->modify('+1 hour');
    }

    if ((int)$minimum->format('H') === 12) {
        $minimum = $minimum->setTime(13, 0);
    }

    return $minimum;
}

/** True when the slot is in the future and at least 1 hour from now (calendar booking). */
function shop_is_future_slot(string $slotDate, string $slotTime): bool
{
    $slotDateTime = shop_slot_start_datetime($slotDate, $slotTime);
    if ($slotDateTime === null) {
        return false;
    }

    return $slotDateTime >= shop_earliest_bookable_slot_start();
}

/** True when the slot meets suggestion lead time (2+ hours from now). */
function shop_is_suggestable_slot(string $slotDate, string $slotTime): bool
{
    $slotDateTime = shop_slot_start_datetime($slotDate, $slotTime);
    if ($slotDateTime === null) {
        return false;
    }

    return $slotDateTime >= shop_next_bookable_slot_start();
}

function shop_window_end_date(int $windowDays = 7): string
{
    $days = max(1, $windowDays);
    return shop_now()->setTime(0, 0)->modify('+' . ($days - 1) . ' day')->format('Y-m-d');
}

function shop_add_minutes_to_time(string $time, int $minutes): string
{
    $parts = explode(':', $time);
    $hour = (int)($parts[0] ?? 0);
    $minute = (int)($parts[1] ?? 0);
    $second = isset($parts[2]) ? (int)$parts[2] : 0;
    $total = ($hour * 3600) + ($minute * 60) + $second + ($minutes * 60);
    $endHour = intdiv($total, 3600) % 24;
    $endMinute = intdiv($total % 3600, 60);
    $endSecond = $total % 60;

    return sprintf('%02d:%02d:%02d', $endHour, $endMinute, $endSecond);
}

function shop_is_time_within_hours(string $time): bool
{
    $normalized = strlen($time) === 5 ? $time . ':00' : $time;
    $open = shop_open_time();
    $close = shop_close_time();
    $lastStart = shop_add_minutes_to_time($close, -shop_appointment_duration_minutes());

    return $normalized >= $open && $normalized <= $lastStart;
}

/**
 * Mark appointments complete once their 1-hour service window has ended.
 */
function auto_complete_due_appointments(PDO $pdo): int
{
    static $done = false;
    if ($done) {
        return 0;
    }
    require_once __DIR__ . '/schema_cache.php';
    if (!schema_cache_should_run('auto_complete_due_appointments', 120)) {
        $done = true;

        return 0;
    }

    $duration = shop_appointment_duration_minutes();

    $selectStmt = $pdo->prepare(
        "SELECT appointment_id, user_id, barber_id, booking_code, appointment_date, start_time, end_time, status
         FROM appointments
         WHERE status IN ('Scheduled', 'CheckedIn', 'InProgress')
           AND (
                (appointment_date::timestamp + COALESCE(NULLIF(end_time, '00:00:00'::time), start_time)) <= NOW()
                OR (appointment_date::timestamp + start_time + make_interval(mins => :duration)) <= NOW()
           )"
    );
    $selectStmt->execute([':duration' => $duration]);
    $dueRows = $selectStmt->fetchAll(PDO::FETCH_ASSOC);

    if (!$dueRows) {
        schema_cache_done('auto_complete_due_appointments');
        $done = true;

        return 0;
    }

    $ids = array_map(static fn(array $row): int => (int)$row['appointment_id'], $dueRows);
    $placeholders = implode(',', array_fill(0, count($ids), '?'));

    $pdo->prepare(
        "UPDATE appointments
         SET status = 'Completed',
             completion_time = COALESCE(completion_time, NOW()),
             updated_at = CURRENT_TIMESTAMP
         WHERE appointment_id IN ($placeholders)"
    )->execute($ids);

    $releaseSlotStmt = $pdo->prepare(
        "UPDATE time_slots
         SET status = 'Available'
         WHERE barber_id = ?
           AND slot_date = ?
           AND slot_time = ?"
    );

    $notifyStmt = $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
         VALUES ('User', ?, 'Appointment', 'Appointment completed', ?, TRUE)"
    );

    foreach ($dueRows as $row) {
        $appointmentId = (int)$row['appointment_id'];
        record_completion_payment($pdo, $appointmentId, null);

        $releaseSlotStmt->execute([
            (int)$row['barber_id'],
            (string)$row['appointment_date'],
            (string)$row['start_time'],
        ]);

        $notifyStmt->execute([
            (int)$row['user_id'],
            'Your appointment ' . (string)$row['booking_code'] . ' has been marked completed.',
        ]);
    }

    schema_cache_done('auto_complete_due_appointments');
    $done = true;

    return count($dueRows);
}
