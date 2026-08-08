<?php
// Shared shop hours, slot generation, and appointment lifecycle helpers.

declare(strict_types=1);

require_once __DIR__ . '/payment_recording.php';

/**
 * Operating schedule configuration. Loaded once per request from
 * shop_weekly_hours / shop_break_windows / shop_closed_dates / system_settings,
 * falling back to the legacy hardcoded values when tables are missing.
 *
 * @return array{
 *   weekly: array<int, array{is_closed: bool, open: string, close: string}>,
 *   breaks: list<array{day: ?int, start: string, end: string}>,
 *   closed_dates: array<string, true>,
 *   closed_date_reasons: array<string, string>,
 *   slot_minutes: int, appointment_minutes: int, walkin_minutes: int, timezone: string
 * }
 */
function shop_schedule_config(bool $refresh = false): array
{
    static $config = null;
    if ($config !== null && !$refresh) {
        return $config;
    }

    $weekly = [];
    for ($day = 0; $day <= 6; $day++) {
        $weekly[$day] = ['is_closed' => false, 'open' => '09:00:00', 'close' => '20:00:00'];
    }

    $config = [
        'weekly' => $weekly,
        'breaks' => [['day' => null, 'start' => '12:00:00', 'end' => '13:00:00']],
        'closed_dates' => [],
        'closed_date_reasons' => [],
        'slot_minutes' => 60,
        'appointment_minutes' => 60,
        'walkin_minutes' => 35,
        'timezone' => 'Asia/Manila',
    ];

    try {
        require_once __DIR__ . '/db.php';
        $pdo = get_db_connection();

        $weeklyRows = $pdo->query(
            'SELECT day_of_week, is_closed, open_time, close_time FROM shop_weekly_hours'
        )->fetchAll(PDO::FETCH_ASSOC);

        if ($weeklyRows) {
            foreach ($weeklyRows as $row) {
                $day = (int)$row['day_of_week'];
                if ($day < 0 || $day > 6) {
                    continue;
                }
                $config['weekly'][$day] = [
                    'is_closed' => (bool)$row['is_closed'],
                    'open' => shop_schedule_time_str((string)$row['open_time']),
                    'close' => shop_schedule_time_str((string)$row['close_time']),
                ];
            }

            // Schedule management is active: breaks come from DB (may be empty).
            $breakRows = $pdo->query(
                'SELECT day_of_week, start_time, end_time FROM shop_break_windows'
            )->fetchAll(PDO::FETCH_ASSOC);
            $config['breaks'] = array_map(static fn(array $row): array => [
                'day' => $row['day_of_week'] !== null ? (int)$row['day_of_week'] : null,
                'start' => shop_schedule_time_str((string)$row['start_time']),
                'end' => shop_schedule_time_str((string)$row['end_time']),
            ], $breakRows);

            $closedRows = $pdo->query(
                "SELECT closed_date, reason FROM shop_closed_dates
                 WHERE closed_date >= CURRENT_DATE - INTERVAL '1 year'
                   AND closed_date <= CURRENT_DATE + INTERVAL '1 year'"
            )->fetchAll(PDO::FETCH_ASSOC);
            $closedDates = [];
            $closedReasons = [];
            foreach ($closedRows as $row) {
                $closedDate = (string)($row['closed_date'] ?? '');
                if ($closedDate === '') {
                    continue;
                }
                $closedDates[$closedDate] = true;
                $closedReasons[$closedDate] = trim((string)($row['reason'] ?? ''));
            }
            $config['closed_dates'] = $closedDates;
            $config['closed_date_reasons'] = $closedReasons;
        }

        $settingRows = $pdo->query(
            "SELECT setting_key, setting_value FROM system_settings
             WHERE setting_key IN ('shop_slot_duration_minutes', 'shop_appointment_duration_minutes', 'shop_walkin_duration_minutes', 'shop_timezone')"
        )->fetchAll(PDO::FETCH_KEY_PAIR);
        foreach (['shop_slot_duration_minutes' => 'slot_minutes', 'shop_appointment_duration_minutes' => 'appointment_minutes', 'shop_walkin_duration_minutes' => 'walkin_minutes'] as $key => $target) {
            $value = (int)($settingRows[$key] ?? 0);
            if ($value >= 5 && $value <= 240) {
                $config[$target] = $value;
            }
        }
        $tz = trim((string)($settingRows['shop_timezone'] ?? ''));
        if ($tz !== '' && in_array($tz, DateTimeZone::listIdentifiers(), true)) {
            $config['timezone'] = $tz;
        }
    } catch (Throwable $e) {
        // Tables not migrated yet — legacy defaults above keep everything working.
    }

    return $config;
}

function shop_schedule_reset_cache(): void
{
    shop_schedule_config(true);
}

/** Normalize '9:00' / '09:00' / '09:00:00' to 'HH:MM:SS'. */
function shop_schedule_time_str(string $time): string
{
    $parts = explode(':', trim($time));
    return sprintf('%02d:%02d:%02d', (int)($parts[0] ?? 0), (int)($parts[1] ?? 0), (int)($parts[2] ?? 0));
}

/** 0=Sunday .. 6=Saturday, or null when the date is malformed. */
function shop_weekday(string $date): ?int
{
    $dt = DateTimeImmutable::createFromFormat('!Y-m-d', $date, new DateTimeZone(shop_timezone()));
    return $dt === false ? null : (int)$dt->format('w');
}

/**
 * Effective hours for a date; with null date returns the widest open/close
 * envelope across all open days (used by callers without date context).
 *
 * @return array{is_closed: bool, open: string, close: string}
 */
function shop_day_hours(?string $date): array
{
    $cfg = shop_schedule_config();

    if ($date !== null) {
        $dow = shop_weekday($date);
        if ($dow !== null) {
            $day = $cfg['weekly'][$dow];
            return [
                'is_closed' => $day['is_closed'] || isset($cfg['closed_dates'][$date]),
                'open' => $day['open'],
                'close' => $day['close'],
            ];
        }
    }

    $open = null;
    $close = null;
    foreach ($cfg['weekly'] as $day) {
        if ($day['is_closed']) {
            continue;
        }
        if ($open === null || $day['open'] < $open) {
            $open = $day['open'];
        }
        if ($close === null || $day['close'] > $close) {
            $close = $day['close'];
        }
    }

    if ($open === null || $close === null) {
        return ['is_closed' => true, 'open' => '09:00:00', 'close' => '20:00:00'];
    }

    return ['is_closed' => false, 'open' => $open, 'close' => $close];
}

function shop_timezone(): string
{
    return shop_schedule_config()['timezone'];
}

/** Escape shop timezone for safe use inside SQL string literals. */
function shop_timezone_sql(): string
{
    return str_replace("'", "''", shop_timezone());
}

/**
 * SQL expression: interpret a naive appointment wall-clock timestamp as shop-local time
 * and convert to timestamptz for comparison with NOW().
 *
 * Example: shop_local_ts_sql('appointment_date', 'start_time')
 * → ((appointment_date + start_time) AT TIME ZONE 'Asia/Manila')
 */
function shop_local_ts_sql(string $dateExpr, string $timeExpr): string
{
    $tz = shop_timezone_sql();

    return "(({$dateExpr}::date + {$timeExpr}::time) AT TIME ZONE '{$tz}')";
}

/**
 * SQL expression for "today" in the shop timezone (date only).
 */
function shop_local_today_sql(): string
{
    $tz = shop_timezone_sql();

    return "((CURRENT_TIMESTAMP AT TIME ZONE '{$tz}')::date)";
}

/**
 * SQL expression for current local time-of-day in the shop timezone.
 */
function shop_local_time_sql(): string
{
    $tz = shop_timezone_sql();

    return "((CURRENT_TIMESTAMP AT TIME ZONE '{$tz}')::time)";
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

function shop_open_time(?string $date = null): string
{
    return shop_day_hours($date)['open'];
}

function shop_close_time(?string $date = null): string
{
    return shop_day_hours($date)['close'];
}

/** True when the shop is closed that date (weekly closure or holiday). */
function shop_is_closed_date(string $date): bool
{
    return shop_day_hours($date)['is_closed'];
}

/**
 * Closure status for calendars / customer messaging.
 *
 * @return array{
 *   isClosed: bool,
 *   status: 'open'|'closed_weekly'|'closed_holiday',
 *   reason: string,
 *   customerMessage: string
 * }
 */
function shop_closure_details(string $date): array
{
    static $dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    $cfg = shop_schedule_config();
    $dow = shop_weekday($date) ?? 0;

    if (isset($cfg['closed_dates'][$date])) {
        $raw = trim((string)($cfg['closed_date_reasons'][$date] ?? ''));
        $reason = $raw !== '' ? $raw : 'Holiday / special closure';
        $customerMessage = $raw !== ''
            ? "We're closed — {$raw}."
            : "We're closed this day.";

        return [
            'isClosed' => true,
            'status' => 'closed_holiday',
            'reason' => $reason,
            'customerMessage' => $customerMessage,
        ];
    }

    if (!empty($cfg['weekly'][$dow]['is_closed'])) {
        $dayName = $dayNames[$dow] ?? 'this weekday';

        return [
            'isClosed' => true,
            'status' => 'closed_weekly',
            'reason' => 'Closed every ' . $dayName,
            'customerMessage' => "We're closed every {$dayName}.",
        ];
    }

    return [
        'isClosed' => false,
        'status' => 'open',
        'reason' => '',
        'customerMessage' => '',
    ];
}

function shop_slot_duration_minutes(): int
{
    return shop_schedule_config()['slot_minutes'];
}

function shop_appointment_duration_minutes(): int
{
    return shop_schedule_config()['appointment_minutes'];
}

/** Regular walk-in / kiosk service window (minutes). */
function shop_walkin_duration_minutes(): int
{
    return shop_schedule_config()['walkin_minutes'];
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
 * Break windows applying to the given date (global + day-specific);
 * with null date only global windows are returned.
 *
 * @return list<array{start: string, end: string}>
 */
function shop_break_windows(?string $date = null): array
{
    $cfg = shop_schedule_config();
    $dow = $date !== null ? shop_weekday($date) : null;

    $windows = [];
    foreach ($cfg['breaks'] as $break) {
        if ($break['day'] === null || ($dow !== null && $break['day'] === $dow)) {
            $windows[] = ['start' => $break['start'], 'end' => $break['end']];
        }
    }

    return $windows;
}

/** True when a slot starting at $time would overlap any break window. */
function shop_is_break_slot_time(string $time, ?string $date = null): bool
{
    $normalized = shop_schedule_time_str($time);
    $slotEnd = shop_add_minutes_to_time($normalized, shop_appointment_duration_minutes());

    foreach (shop_break_windows($date) as $window) {
        if ($normalized < $window['end'] && $slotEnd > $window['start']) {
            return true;
        }
    }

    return false;
}

/**
 * Bookable on-the-hour slot starts for a date (or the global envelope when
 * null), bounded by open/close and excluding break windows.
 *
 * @return string[]
 */
function shop_default_slot_times(?string $date = null): array
{
    $hours = shop_day_hours($date);
    if ($hours['is_closed']) {
        return [];
    }

    $openHour = (int)substr($hours['open'], 0, 2);
    if (substr($hours['open'], 3, 2) !== '00') {
        $openHour++;
    }
    $lastStart = shop_add_minutes_to_time($hours['close'], -shop_appointment_duration_minutes());
    $lastHour = (int)substr($lastStart, 0, 2);

    $times = [];
    for ($hour = $openHour; $hour <= $lastHour; $hour++) {
        $time = sprintf('%02d:00:00', $hour);
        if (shop_is_break_slot_time($time, $date)) {
            continue;
        }
        $times[] = $time;
    }

    return $times;
}

/**
 * Normalize to an on-the-hour slot within shop hours for the date
 * (global envelope when null), or null when invalid/closed.
 */
function shop_normalize_slot_time(string $time, ?string $date = null): ?string
{
    $parts = explode(':', trim($time));
    if (count($parts) < 2) {
        return null;
    }

    $hour = (int)$parts[0];
    $minute = (int)$parts[1];
    if ($minute !== 0 || $hour < 0 || $hour > 23) {
        return null;
    }

    $hours = shop_day_hours($date);
    if ($hours['is_closed']) {
        return null;
    }

    $openHour = (int)substr($hours['open'], 0, 2);
    if (substr($hours['open'], 3, 2) !== '00') {
        $openHour++;
    }
    $normalized = sprintf('%02d:00:00', $hour);
    $lastStart = shop_add_minutes_to_time($hours['close'], -shop_appointment_duration_minutes());

    if ($hour < $openHour || $normalized > $lastStart) {
        return null;
    }

    return $normalized;
}

function shop_is_allowed_slot_time(string $time, ?string $date = null): bool
{
    return shop_normalize_slot_time($time, $date) !== null;
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

    for ($i = 0; $i < 30; $i++) {
        $date = $minimum->format('Y-m-d');
        $hours = shop_day_hours($date);
        if (!$hours['is_closed']) {
            $openHour = (int)substr($hours['open'], 0, 2);
            if (substr($hours['open'], 3, 2) !== '00') {
                $openHour++;
            }
            $lastStart = shop_add_minutes_to_time($hours['close'], -shop_appointment_duration_minutes());
            $lastHour = (int)substr($lastStart, 0, 2);

            $hour = (int)$minimum->format('H');
            if ($hour < $openHour) {
                return $minimum->setTime($openHour, 0);
            }
            if ($hour <= $lastHour) {
                return $minimum;
            }
        }
        $minimum = $minimum->modify('+1 day')->setTime(0, 0);
    }

    return $minimum;
}

function shop_slot_start_datetime(string $slotDate, string $slotTime): ?DateTimeImmutable
{
    $normalized = shop_normalize_slot_time($slotTime, $slotDate);
    if ($normalized === null || shop_is_break_slot_time($normalized, $slotDate)) {
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

    foreach (shop_break_windows($minimum->format('Y-m-d')) as $window) {
        $time = $minimum->format('H:i:s');
        if ($time >= $window['start'] && $time < $window['end']) {
            $minimum = $minimum->setTime((int)substr($window['end'], 0, 2), (int)substr($window['end'], 3, 2));
        }
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

function shop_booking_window_days(): int
{
    $days = (int)(getenv('BOOKING_WINDOW_DAYS') ?: ($_ENV['BOOKING_WINDOW_DAYS'] ?? 30));

    return max(1, min(60, $days));
}

function shop_max_reschedules_per_appointment(): int
{
    return 3;
}

function shop_reschedule_notice_hours(): int
{
    return 24;
}

function shop_window_end_date(?int $windowDays = null): string
{
    $days = $windowDays ?? shop_booking_window_days();

    return shop_now()->setTime(0, 0)->modify('+' . (max(1, $days) - 1) . ' day')->format('Y-m-d');
}

/**
 * Whether a customer may reschedule this appointment (policy only; not slot availability).
 *
 * @return array{allowed: bool, reason: string, remaining: int}
 */
function can_customer_reschedule_appointment(array $appt, string $paymentState): array
{
    $max = shop_max_reschedules_per_appointment();
    $count = (int)($appt['reschedule_count'] ?? 0);
    $remaining = max(0, $max - $count);

    if ($paymentState !== 'Paid') {
        return [
            'allowed' => false,
            'reason' => 'Reschedule is available only after payment is confirmed.',
            'remaining' => $remaining,
        ];
    }

    $status = (string)($appt['status'] ?? '');
    if ($status !== 'Scheduled') {
        return [
            'allowed' => false,
            'reason' => 'Only scheduled upcoming appointments can be rescheduled.',
            'remaining' => $remaining,
        ];
    }

    if ($count >= $max) {
        return [
            'allowed' => false,
            'reason' => 'You have used all ' . $max . ' reschedules for this appointment.',
            'remaining' => 0,
        ];
    }

    $slotDate = (string)($appt['appointment_date'] ?? '');
    $slotTime = (string)($appt['start_time'] ?? '');
    $currentStart = shop_slot_start_datetime($slotDate, $slotTime);
    if ($currentStart === null) {
        // The day may have been closed after booking; parse leniently so the
        // customer can still reschedule away from it.
        $lenient = DateTimeImmutable::createFromFormat(
            'Y-m-d H:i:s',
            $slotDate . ' ' . shop_schedule_time_str($slotTime),
            new DateTimeZone(shop_timezone())
        );
        $currentStart = $lenient === false ? null : $lenient;
    }
    if ($currentStart === null) {
        return [
            'allowed' => false,
            'reason' => 'This appointment time is invalid.',
            'remaining' => $remaining,
        ];
    }

    $noticeDeadline = shop_now()->modify('+' . shop_reschedule_notice_hours() . ' hours');
    if ($currentStart < $noticeDeadline) {
        return [
            'allowed' => false,
            'reason' => 'Reschedule at least ' . shop_reschedule_notice_hours() . ' hours before your appointment.',
            'remaining' => $remaining,
        ];
    }

    return [
        'allowed' => true,
        'reason' => '',
        'remaining' => $remaining,
    ];
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

function shop_is_time_within_hours(string $time, ?string $date = null): bool
{
    $normalized = strlen($time) === 5 ? $time . ':00' : $time;
    $hours = shop_day_hours($date);
    if ($hours['is_closed']) {
        return false;
    }
    $lastStart = shop_add_minutes_to_time($hours['close'], -shop_appointment_duration_minutes());

    return $normalized >= $hours['open'] && $normalized <= $lastStart;
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

    $localToday = shop_local_today_sql();
    $localTime = shop_local_time_sql();
    $selectStmt = $pdo->query(
        "SELECT booking_group_id
         FROM appointments
         WHERE booking_group_id IS NOT NULL
           AND status IN ('Scheduled', 'CheckedIn')
           AND (
                appointment_date < {$localToday}
                OR (appointment_date = {$localToday} AND start_time <= {$localTime})
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

    $localToday = shop_local_today_sql();
    $localTime = shop_local_time_sql();
    $startTs = shop_local_ts_sql('appointment_date', 'start_time');
    $selectStmt = $pdo->prepare(
        "SELECT appointment_id, booking_code, user_id
         FROM appointments
         WHERE booking_group_id IS NULL
           AND status IN ('Scheduled', 'CheckedIn')
           AND (
                appointment_date < {$localToday}
                OR (appointment_date = {$localToday} AND start_time <= {$localTime})
           )
           AND (
                {$startTs} + make_interval(mins => :duration) > NOW()
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
    $startTs = shop_local_ts_sql('appointment_date', 'start_time');
    $endTs = shop_local_ts_sql('appointment_date', 'end_time');

    $groupStmt = $pdo->prepare(
        "SELECT booking_group_id, MIN(appointment_id) AS lead_appointment_id,
                MAX(user_id) AS user_id, MAX(booking_code) AS booking_code
         FROM appointments
         WHERE booking_group_id IS NOT NULL
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
         GROUP BY booking_group_id
         HAVING MAX({$startTs} + make_interval(mins => :duration)) <= NOW()
            OR MAX(
                CASE
                    WHEN end_time IS NOT NULL
                         AND end_time <> '00:00:00'::time
                         AND end_time > start_time
                    THEN {$endTs}
                    ELSE NULL::timestamptz
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
                {$startTs} + make_interval(mins => :duration) <= NOW()
                OR (
                    end_time IS NOT NULL
                    AND end_time <> '00:00:00'::time
                    AND end_time > start_time
                    AND {$endTs} <= NOW()
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
