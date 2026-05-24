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

/** Regular walk-in / kiosk service window (minutes). */
function shop_walkin_duration_minutes(): int
{
    return 35;
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
 * Notify all active receptionist staff of queue automation (tracking feed).
 */
function notify_receptionist_staff(PDO $pdo, string $title, string $message): void
{
    try {
        static $stmt = null;
        if ($stmt === null) {
            $stmt = $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
                 VALUES ('Admin', :recipient_id, 'Queue', :title, :message, TRUE)"
            );
        }

        $staffIds = [];
        $staffRows = $pdo->query(
            "SELECT staff_id FROM staff_users WHERE role = 'Receptionist' AND is_active = TRUE"
        )->fetchAll(PDO::FETCH_ASSOC);
        foreach ($staffRows as $row) {
            $id = (int)($row['staff_id'] ?? 0);
            if ($id > 0) {
                $staffIds[] = $id;
            }
        }

        if ($staffIds === []) {
            return;
        }

        foreach ($staffIds as $staffId) {
            $stmt->execute([
                ':recipient_id' => $staffId,
                ':title' => $title,
                ':message' => $message,
            ]);
        }
    } catch (Throwable $e) {
        error_log('Receptionist queue notification skipped: ' . $e->getMessage());
    }
}

/**
 * Estimated minutes until a walk-in barber can take the next client.
 * For first-available (null barber), returns the minimum across walk-in barbers.
 */
function shop_estimate_walkin_barber_wait_minutes(PDO $pdo, ?int $barberId): int
{
    require_once __DIR__ . '/db.php';
    require_once __DIR__ . '/barber_channel.php';

    $walkinMinutes = shop_walkin_duration_minutes();
    $appointmentMinutes = shop_appointment_duration_minutes();

    if ($barberId === null || $barberId <= 0) {
        ensure_barber_channel_column($pdo);
        $walkInFilter = barber_channel_filter_sql('walk_in');
        $stmt = $pdo->query(
            "SELECT barber_id FROM barbers WHERE is_active = TRUE{$walkInFilter}"
        );
        $best = PHP_INT_MAX;
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $wait = shop_estimate_walkin_barber_wait_minutes($pdo, (int)$row['barber_id']);
            if ($wait < $best) {
                $best = $wait;
            }
        }

        return $best === PHP_INT_MAX ? 0 : $best;
    }

    $wait = 0;

    $inProgressStmt = $pdo->prepare(
        "SELECT actual_start, created_at
         FROM walkin_queue
         WHERE barber_id = :barber_id
           AND DATE(created_at) = CURRENT_DATE
           AND status = 'InProgress'
         ORDER BY COALESCE(actual_start, created_at) ASC
         LIMIT 1"
    );
    $inProgressStmt->execute([':barber_id' => $barberId]);
    $inProgress = $inProgressStmt->fetch(PDO::FETCH_ASSOC);
    if ($inProgress) {
        $startRaw = $inProgress['actual_start'] ?? $inProgress['created_at'];
        if ($startRaw) {
            $startTs = strtotime((string)$startRaw);
            if ($startTs !== false) {
                $remainingSeconds = ($startTs + ($walkinMinutes * 60)) - time();
                $wait += max(0, (int)ceil($remainingSeconds / 60));
            } else {
                $wait += $walkinMinutes;
            }
        } else {
            $wait += $walkinMinutes;
        }
    }

    $aheadStmt = $pdo->prepare(
        "SELECT COUNT(*)::int
         FROM walkin_queue
         WHERE DATE(created_at) = CURRENT_DATE
           AND barber_id = :barber_id
           AND status IN ('Waiting', 'Assigned')"
    );
    $aheadStmt->execute([':barber_id' => $barberId]);
    $wait += (int)$aheadStmt->fetchColumn() * $walkinMinutes;

    $apptStmt = $pdo->prepare(
        "SELECT COUNT(*)::int
         FROM appointments
         WHERE appointment_date = CURRENT_DATE
           AND barber_id = :barber_id
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress')"
    );
    $apptStmt->execute([':barber_id' => $barberId]);
    $wait += (int)$apptStmt->fetchColumn() * $appointmentMinutes;

    return $wait;
}

/**
 * Pick the walk-in barber with the shortest estimated wait.
 */
function shop_pick_least_busy_walkin_barber_id(PDO $pdo): ?int
{
    require_once __DIR__ . '/barber_channel.php';
    ensure_barber_channel_column($pdo);
    $walkInFilter = barber_channel_filter_sql('walk_in');
    $stmt = $pdo->query(
        "SELECT barber_id FROM barbers WHERE is_active = TRUE{$walkInFilter} ORDER BY barber_id ASC"
    );

    $bestId = null;
    $bestWait = PHP_INT_MAX;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $id = (int)$row['barber_id'];
        $wait = shop_estimate_walkin_barber_wait_minutes($pdo, $id);
        if ($wait < $bestWait) {
            $bestWait = $wait;
            $bestId = $id;
        }
    }

    return $bestId;
}

/**
 * Assign unassigned walk-ins to the least busy walk-in barber.
 */
function shop_assign_unassigned_walkins(PDO $pdo): int
{
    $fetchStmt = $pdo->prepare(
        "SELECT queue_id
         FROM walkin_queue
         WHERE DATE(created_at) = CURRENT_DATE
           AND status IN ('Waiting', 'Assigned')
           AND barber_id IS NULL
         ORDER BY created_at ASC
         LIMIT 1"
    );
    $updateStmt = $pdo->prepare(
        "UPDATE walkin_queue
         SET barber_id = :barber_id,
             status = 'Assigned'
         WHERE queue_id = :queue_id"
    );

    $assigned = 0;
    while (true) {
        $fetchStmt->execute();
        $queueId = (int)$fetchStmt->fetchColumn();
        if ($queueId <= 0) {
            break;
        }

        $barberId = shop_pick_least_busy_walkin_barber_id($pdo);
        if ($barberId === null) {
            break;
        }

        $updateStmt->execute([
            ':barber_id' => $barberId,
            ':queue_id' => $queueId,
        ]);
        $assigned++;
    }

    return $assigned;
}

/**
 * Start grouped bookings when the first slot time begins (whole unit moves together).
 */
function auto_start_due_booking_groups(PDO $pdo): int
{
    require_once __DIR__ . '/group_booking.php';
    ensure_group_booking_schema($pdo);

    $selectStmt = $pdo->query(
        "SELECT booking_group_id
         FROM appointments
         WHERE booking_group_id IS NOT NULL
           AND status IN ('Scheduled', 'CheckedIn')
           AND (
                appointment_date < CURRENT_DATE
                OR (appointment_date = CURRENT_DATE AND start_time <= CURRENT_TIME)
           )
         GROUP BY booking_group_id"
    );
    $groupIds = array_map(
        static fn(array $row): int => (int)$row['booking_group_id'],
        $selectStmt->fetchAll(PDO::FETCH_ASSOC)
    );
    if ($groupIds === []) {
        return 0;
    }

    $started = 0;
    $updateStmt = $pdo->prepare(
        "UPDATE appointments
         SET status = 'InProgress',
             checkin_time = COALESCE(checkin_time, NOW()),
             updated_at = CURRENT_TIMESTAMP
         WHERE booking_group_id = :group_id
           AND status IN ('Scheduled', 'CheckedIn')"
    );
    foreach ($groupIds as $groupId) {
        $updateStmt->execute([':group_id' => $groupId]);
        if ($updateStmt->rowCount() > 0) {
            $started++;
        }
    }

    return $started;
}

/**
 * Start exclusive appointments when their slot time begins.
 */
function auto_start_due_appointments(PDO $pdo): int
{
    $duration = shop_appointment_duration_minutes();
    $startedGroups = auto_start_due_booking_groups($pdo);

    $selectStmt = $pdo->prepare(
        "SELECT appointment_id, booking_code, user_id
         FROM appointments
         WHERE booking_group_id IS NULL
           AND status IN ('Scheduled', 'CheckedIn')
           AND (
                appointment_date < CURRENT_DATE
                OR (appointment_date = CURRENT_DATE AND start_time <= CURRENT_TIME)
           )
           AND (
                appointment_date::timestamp + start_time + make_interval(mins => :duration) > NOW()
           )"
    );
    $selectStmt->execute([':duration' => $duration]);
    $rows = $selectStmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) {
        return $startedGroups;
    }

    $ids = array_map(static fn(array $row): int => (int)$row['appointment_id'], $rows);
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $pdo->prepare(
        "UPDATE appointments
         SET status = 'InProgress',
             checkin_time = COALESCE(checkin_time, NOW()),
             updated_at = CURRENT_TIMESTAMP
         WHERE appointment_id IN ($placeholders)"
    )->execute($ids);

    return $startedGroups + count($rows);
}

/**
 * Start the next regular walk-in per barber when no service is in progress.
 */
function auto_start_due_walkins(PDO $pdo): int
{
    require_once __DIR__ . '/db.php';
    ensure_walkin_queue_timestamp_columns($pdo);

    $selectStmt = $pdo->query(
        "SELECT DISTINCT ON (wq.barber_id)
                wq.queue_id, wq.barber_id, wq.queue_number
           FROM walkin_queue wq
           JOIN barbers b ON b.barber_id = wq.barber_id
          WHERE wq.status IN ('Waiting', 'Assigned')
            AND wq.barber_id IS NOT NULL
            AND b.is_active = TRUE
            AND NOT EXISTS (
                SELECT 1 FROM walkin_queue busy
                 WHERE busy.barber_id = wq.barber_id
                   AND busy.status = 'InProgress'
            )
          ORDER BY wq.barber_id,
                   CASE wq.status WHEN 'Assigned' THEN 0 ELSE 1 END,
                   wq.created_at ASC"
    );
    $rows = $selectStmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) {
        return 0;
    }

    $updateStmt = $pdo->prepare(
        "UPDATE walkin_queue
         SET status = 'InProgress',
             actual_start = COALESCE(actual_start, NOW())
         WHERE queue_id = :queue_id"
    );
    foreach ($rows as $row) {
        $updateStmt->execute([':queue_id' => (int)$row['queue_id']]);
    }

    return count($rows);
}

/**
 * Complete regular walk-ins once the service window has elapsed.
 */
function auto_complete_due_walkins(PDO $pdo): int
{
    require_once __DIR__ . '/db.php';
    ensure_walkin_queue_timestamp_columns($pdo);

    $duration = shop_walkin_duration_minutes();

    $selectStmt = $pdo->prepare(
        "SELECT queue_id
         FROM walkin_queue
         WHERE status = 'InProgress'
           AND (
                (actual_start IS NOT NULL AND actual_start + make_interval(mins => :duration) <= NOW())
                OR (actual_start IS NULL AND created_at + make_interval(mins => :duration) <= NOW())
           )"
    );
    $selectStmt->execute([':duration' => $duration]);
    $rows = $selectStmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) {
        return 0;
    }

    $updateStmt = $pdo->prepare(
        "UPDATE walkin_queue
         SET status = 'Completed',
             actual_end = COALESCE(actual_end, NOW())
         WHERE queue_id = :queue_id"
    );

    foreach ($rows as $row) {
        $queueId = (int)$row['queue_id'];
        $updateStmt->execute([':queue_id' => $queueId]);
        try {
            record_completion_payment($pdo, null, $queueId);
        } catch (Throwable $paymentError) {
            error_log('Walk-in auto-complete payment skipped: ' . $paymentError->getMessage());
        }
    }

    return count($rows);
}

/**
 * Receptionist tracking: auto start/complete queue items and return activity feed.
 *
 * @return array{events: list<array{action: string, kind: string, label: string}>, counts: array<string, int>}
 */
function run_tracking_automation(PDO $pdo, bool $force = true): array
{
    $assignedWalkins = shop_assign_unassigned_walkins($pdo);
    $startedAppointments = auto_start_due_appointments($pdo);
    $startedWalkins = auto_start_due_walkins($pdo);
    $completedAppointments = auto_complete_due_appointments($pdo, $force);
    $completedWalkins = auto_complete_due_walkins($pdo);

    $events = [];
    if ($startedAppointments > 0) {
        $label = $startedAppointments === 1
            ? '1 appointment started automatically'
            : "{$startedAppointments} appointments started automatically";
        notify_receptionist_staff($pdo, 'Queue update', $label);
        $events[] = ['action' => 'started', 'kind' => 'appointment', 'label' => $label];
    }
    if ($startedWalkins > 0) {
        $label = $startedWalkins === 1
            ? '1 walk-in started automatically'
            : "{$startedWalkins} walk-ins started automatically";
        notify_receptionist_staff($pdo, 'Queue update', $label);
        $events[] = ['action' => 'started', 'kind' => 'walkin', 'label' => $label];
    }
    if ($completedAppointments > 0) {
        $label = $completedAppointments === 1
            ? '1 appointment completed automatically'
            : "{$completedAppointments} appointments completed automatically";
        notify_receptionist_staff($pdo, 'Queue update', $label);
        $events[] = ['action' => 'completed', 'kind' => 'appointment', 'label' => $label];
    }
    if ($completedWalkins > 0) {
        $label = $completedWalkins === 1
            ? '1 walk-in completed automatically'
            : "{$completedWalkins} walk-ins completed automatically";
        notify_receptionist_staff($pdo, 'Queue update', $label);
        $events[] = ['action' => 'completed', 'kind' => 'walkin', 'label' => $label];
    }

    return [
        'events' => $events,
        'counts' => [
            'startedAppointments' => $startedAppointments,
            'startedWalkins' => $startedWalkins,
            'completedAppointments' => $completedAppointments,
            'completedWalkins' => $completedWalkins,
        ],
    ];
}

/**
 * Mark appointments complete once their 1-hour service window has ended.
 */
function auto_complete_due_appointments(PDO $pdo, bool $force = false): int
{
    static $done = false;
    if (!$force) {
        if ($done) {
            return 0;
        }
        require_once __DIR__ . '/schema_cache.php';
        if (!schema_cache_should_run('auto_complete_due_appointments', 30)) {
            $done = true;

            return 0;
        }
    }

    require_once __DIR__ . '/group_booking.php';
    require_once __DIR__ . '/slot_locking.php';
    ensure_group_booking_schema($pdo);
    $duration = shop_appointment_duration_minutes();
    $completedUnits = 0;

    $groupStmt = $pdo->prepare(
        "SELECT booking_group_id, MIN(appointment_id) AS lead_appointment_id,
                MAX(user_id) AS user_id, MAX(booking_code) AS booking_code
         FROM appointments
         WHERE booking_group_id IS NOT NULL
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
         GROUP BY booking_group_id
         HAVING MAX(
                appointment_date::timestamp + start_time + make_interval(mins => :duration)
            ) <= NOW()
            OR MAX(
                CASE
                    WHEN end_time IS NOT NULL
                         AND end_time <> '00:00:00'::time
                         AND end_time > start_time
                    THEN appointment_date::timestamp + end_time
                    ELSE NULL::timestamp
                END
            ) <= NOW()"
    );
    $groupStmt->execute([':duration' => $duration]);
    $dueGroups = $groupStmt->fetchAll(PDO::FETCH_ASSOC);

    $notifyStmt = $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
         VALUES ('User', ?, 'Appointment', 'Appointment completed', ?, TRUE)"
    );

    foreach ($dueGroups as $groupRow) {
        $leadId = (int)($groupRow['lead_appointment_id'] ?? 0);
        if ($leadId <= 0) {
            continue;
        }

        try {
            if (complete_booking_unit($pdo, $leadId) > 0) {
                $completedUnits++;
                $notifyStmt->execute([
                    (int)$groupRow['user_id'],
                    'Your group booking ' . (string)$groupRow['booking_code'] . ' has been marked completed.',
                ]);
            }
        } catch (Throwable $e) {
            error_log('Group auto-complete skipped for #' . $leadId . ': ' . $e->getMessage());
        }
    }

    $selectStmt = $pdo->prepare(
        "SELECT appointment_id, user_id, barber_id, booking_code
         FROM appointments
         WHERE booking_group_id IS NULL
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
           AND (
                appointment_date::timestamp + start_time + make_interval(mins => :duration) <= NOW()
                OR (
                    end_time IS NOT NULL
                    AND end_time <> '00:00:00'::time
                    AND end_time > start_time
                    AND appointment_date::timestamp + end_time <= NOW()
                )
           )"
    );
    $selectStmt->execute([':duration' => $duration]);
    $dueRows = $selectStmt->fetchAll(PDO::FETCH_ASSOC);

    foreach ($dueRows as $row) {
        $appointmentId = (int)$row['appointment_id'];
        try {
            if (complete_booking_unit($pdo, $appointmentId) > 0) {
                $completedUnits++;
                $notifyStmt->execute([
                    (int)$row['user_id'],
                    'Your appointment ' . (string)$row['booking_code'] . ' has been marked completed.',
                ]);
            }
        } catch (Throwable $paymentError) {
            error_log('Appointment auto-complete skipped for #' . $appointmentId . ': ' . $paymentError->getMessage());
        }
    }

    if (!$force) {
        schema_cache_done('auto_complete_due_appointments');
        $done = true;
    }

    return $completedUnits;
}

/**
 * @return array{walkInsToday: int, appointmentsToday: int, inProgress: int, availableBarbers: int}
 */
function fetch_receptionist_front_desk_stats(PDO $pdo): array
{
    $walkInsTodayStmt = $pdo->prepare(
        'SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE'
    );
    $walkInsTodayStmt->execute();
    $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

    $appointmentsTodayStmt = $pdo->prepare(
        "SELECT COUNT(*) FROM (
            SELECT DISTINCT COALESCE(booking_group_id::text, 'a' || appointment_id::text) AS unit_key
            FROM appointments
            WHERE appointment_date = CURRENT_DATE
              AND status NOT IN ('Cancelled', 'NoShow')
         ) units"
    );
    $appointmentsTodayStmt->execute();
    $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

    $inProgressStmt = $pdo->prepare(
        "SELECT
            (SELECT COUNT(*) FROM walkin_queue
              WHERE status = 'InProgress' AND DATE(created_at) = CURRENT_DATE)
          + (SELECT COUNT(*) FROM (
                SELECT DISTINCT COALESCE(booking_group_id::text, 'a' || appointment_id::text) AS unit_key
                FROM appointments
                WHERE appointment_date = CURRENT_DATE AND status = 'InProgress'
             ) appt_units)"
    );
    $inProgressStmt->execute();
    $inProgress = (int)$inProgressStmt->fetchColumn();

    $availableBarbersStmt = $pdo->prepare(
        "SELECT COUNT(*)
         FROM barbers b
         WHERE b.is_active = TRUE
           AND NOT EXISTS (
                SELECT 1 FROM appointments a
                 WHERE a.barber_id = b.barber_id
                   AND a.appointment_date = CURRENT_DATE
                   AND a.status = 'InProgress'
           )
           AND NOT EXISTS (
                SELECT 1 FROM walkin_queue wq
                 WHERE wq.barber_id = b.barber_id
                   AND wq.status = 'InProgress'
           )"
    );
    $availableBarbersStmt->execute();
    $availableBarbers = (int)$availableBarbersStmt->fetchColumn();

    return [
        'walkInsToday' => $walkInsToday,
        'appointmentsToday' => $appointmentsToday,
        'inProgress' => $inProgress,
        'availableBarbers' => $availableBarbers,
    ];
}
