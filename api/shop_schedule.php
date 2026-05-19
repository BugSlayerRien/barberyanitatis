<?php
// Shared shop hours, slot generation, and appointment lifecycle helpers.

declare(strict_types=1);

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

/**
 * Hourly slots from 9:00 AM through 7:00 PM start (each 1-hour block ends by 8:00 PM close).
 *
 * @return string[]
 */
function shop_default_slot_times(): array
{
    $times = [];
    for ($hour = 9; $hour <= 19; $hour++) {
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

function shop_booking_lead_hours(): int
{
    return 3;
}

/**
 * Earliest bookable slot start (on-the-hour, within shop hours, at least N hours from now).
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

function shop_is_future_slot(string $slotDate, string $slotTime): bool
{
    $normalized = shop_normalize_slot_time($slotTime);
    if ($normalized === null) {
        return false;
    }

    $slotDateTime = DateTimeImmutable::createFromFormat(
        'Y-m-d H:i:s',
        $slotDate . ' ' . $normalized,
        new DateTimeZone(shop_timezone())
    );
    if ($slotDateTime === false) {
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

    return count($dueRows);
}
