<?php
// Admin operating schedule API: weekly hours, break windows, closed dates, slot settings.

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';

const SCHEDULE_DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function ensure_operating_schedule_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS shop_weekly_hours (
            day_of_week INT PRIMARY KEY CHECK (day_of_week BETWEEN 0 AND 6),
            is_closed BOOLEAN NOT NULL DEFAULT FALSE,
            open_time TIME NOT NULL DEFAULT '09:00',
            close_time TIME NOT NULL DEFAULT '20:00',
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT ck_weekly_hours_order CHECK (is_closed OR close_time > open_time)
        )"
    );
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS shop_break_windows (
            break_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            day_of_week INT CHECK (day_of_week BETWEEN 0 AND 6),
            start_time TIME NOT NULL,
            end_time TIME NOT NULL,
            label VARCHAR(80),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT ck_break_window_order CHECK (end_time > start_time)
        )"
    );
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS shop_closed_dates (
            closed_date DATE PRIMARY KEY,
            reason VARCHAR(160),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );

    $pdo->exec(
        "INSERT INTO shop_weekly_hours (day_of_week, is_closed, open_time, close_time)
         SELECT d, FALSE, '09:00'::time, '20:00'::time
         FROM generate_series(0, 6) AS d
         ON CONFLICT (day_of_week) DO NOTHING"
    );
    $pdo->exec(
        "INSERT INTO shop_break_windows (day_of_week, start_time, end_time, label)
         SELECT NULL, '12:00'::time, '13:00'::time, 'Lunch break'
         WHERE NOT EXISTS (SELECT 1 FROM shop_break_windows)"
    );
    $pdo->exec(
        "INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_editable, updated_at)
         VALUES
           ('shop_slot_duration_minutes', '60', 'Number', 'operations', 'Calendar slot length in minutes', TRUE, NOW()),
           ('shop_appointment_duration_minutes', '60', 'Number', 'operations', 'Appointment service length in minutes', TRUE, NOW()),
           ('shop_walkin_duration_minutes', '35', 'Number', 'operations', 'Walk-in service length in minutes', TRUE, NOW()),
           ('shop_timezone', 'Asia/Manila', 'String', 'operations', 'Shop timezone identifier', TRUE, NOW())
         ON CONFLICT (setting_key) DO NOTHING"
    );
}

/** Validate and normalize 'HH:MM' (or 'HH:MM:SS') to 'HH:MM:SS'; null when malformed. */
function schedule_parse_time(string $time): ?string
{
    if (!preg_match('/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/', trim($time), $m)) {
        return null;
    }
    $hour = (int)$m[1];
    $minute = (int)$m[2];
    if ($hour > 23 || $minute > 59) {
        return null;
    }

    return sprintf('%02d:%02d:00', $hour, $minute);
}

function schedule_is_valid_date(string $date): bool
{
    $dt = DateTimeImmutable::createFromFormat('!Y-m-d', $date);

    return $dt !== false && $dt->format('Y-m-d') === $date;
}

/** @return array<string, mixed> */
function operating_schedule_payload(PDO $pdo): array
{
    $weekly = $pdo->query(
        'SELECT day_of_week, is_closed, open_time, close_time FROM shop_weekly_hours ORDER BY day_of_week'
    )->fetchAll(PDO::FETCH_ASSOC);

    $breaks = $pdo->query(
        'SELECT break_id, day_of_week, start_time, end_time, label
         FROM shop_break_windows
         ORDER BY day_of_week NULLS FIRST, start_time'
    )->fetchAll(PDO::FETCH_ASSOC);

    $closedDates = $pdo->query(
        "SELECT closed_date, reason
         FROM shop_closed_dates
         WHERE closed_date >= CURRENT_DATE - INTERVAL '30 day'
         ORDER BY closed_date"
    )->fetchAll(PDO::FETCH_ASSOC);

    $cfg = shop_schedule_config(true);

    return [
        'weekly' => array_map(static fn(array $row): array => [
            'dayOfWeek' => (int)$row['day_of_week'],
            'dayName' => SCHEDULE_DAY_NAMES[(int)$row['day_of_week']],
            'isClosed' => (bool)$row['is_closed'],
            'openTime' => substr((string)$row['open_time'], 0, 5),
            'closeTime' => substr((string)$row['close_time'], 0, 5),
        ], $weekly),
        'breaks' => array_map(static fn(array $row): array => [
            'breakId' => (int)$row['break_id'],
            'dayOfWeek' => $row['day_of_week'] !== null ? (int)$row['day_of_week'] : null,
            'dayName' => $row['day_of_week'] !== null ? SCHEDULE_DAY_NAMES[(int)$row['day_of_week']] : 'Every day',
            'startTime' => substr((string)$row['start_time'], 0, 5),
            'endTime' => substr((string)$row['end_time'], 0, 5),
            'label' => (string)($row['label'] ?? ''),
        ], $breaks),
        'closedDates' => array_map(static fn(array $row): array => [
            'date' => (string)$row['closed_date'],
            'reason' => (string)($row['reason'] ?? ''),
        ], $closedDates),
        'settings' => [
            'slotMinutes' => $cfg['slot_minutes'],
            'appointmentMinutes' => $cfg['appointment_minutes'],
            'walkinMinutes' => $cfg['walkin_minutes'],
            'timezone' => $cfg['timezone'],
        ],
    ];
}

/**
 * Future appointments that would fall outside the proposed weekly hours.
 *
 * @param array<int, array{is_closed: bool, open: string, close: string}> $proposed
 * @return list<string>
 */
function weekly_hours_warnings(PDO $pdo, array $proposed): array
{
    $rows = $pdo->query(
        "SELECT EXTRACT(DOW FROM appointment_date)::int AS dow, start_time, COUNT(*) AS cnt
         FROM appointments
         WHERE appointment_date >= CURRENT_DATE
           AND status IN ('Scheduled', 'CheckedIn')
         GROUP BY 1, 2"
    )->fetchAll(PDO::FETCH_ASSOC);

    $affected = array_fill(0, 7, 0);
    $duration = shop_appointment_duration_minutes();
    foreach ($rows as $row) {
        $dow = (int)$row['dow'];
        $day = $proposed[$dow] ?? null;
        if ($day === null) {
            continue;
        }
        $startTime = shop_schedule_time_str((string)$row['start_time']);
        if ($day['is_closed']) {
            $affected[$dow] += (int)$row['cnt'];
            continue;
        }
        $lastStart = shop_add_minutes_to_time($day['close'], -$duration);
        if ($startTime < $day['open'] || $startTime > $lastStart) {
            $affected[$dow] += (int)$row['cnt'];
        }
    }

    $warnings = [];
    foreach ($affected as $dow => $count) {
        if ($count > 0) {
            $warnings[] = $count . ' upcoming appointment(s) on ' . SCHEDULE_DAY_NAMES[$dow]
                . 's fall outside the new hours. They remain booked; review them manually.';
        }
    }

    return $warnings;
}

try {
    $pdo = get_db_connection();
    ensure_operating_schedule_tables($pdo);

    $method = strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    if ($method === 'GET') {
        json_response(['schedule' => operating_schedule_payload($pdo)]);
    }
    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = trim((string)($input['action'] ?? 'get'));

    if ($action === 'get') {
        json_response(['schedule' => operating_schedule_payload($pdo)]);
    }

    if ($action === 'updateWeekly') {
        $days = $input['days'] ?? null;
        if (!is_array($days) || count($days) !== 7) {
            json_response(['error' => 'Provide all 7 days (days array).'], 422);
        }

        $proposed = [];
        foreach ($days as $day) {
            $dow = (int)($day['dayOfWeek'] ?? -1);
            if ($dow < 0 || $dow > 6 || isset($proposed[$dow])) {
                json_response(['error' => 'Invalid or duplicate dayOfWeek.'], 422);
            }
            $isClosed = !empty($day['isClosed']);
            $open = schedule_parse_time((string)($day['openTime'] ?? ''));
            $close = schedule_parse_time((string)($day['closeTime'] ?? ''));
            if (!$isClosed) {
                if ($open === null || $close === null) {
                    json_response(['error' => 'Invalid time for ' . SCHEDULE_DAY_NAMES[$dow] . ' (expected HH:MM).'], 422);
                }
                if ($close <= $open) {
                    json_response(['error' => SCHEDULE_DAY_NAMES[$dow] . ': close time must be after open time.'], 422);
                }
            }
            $proposed[$dow] = [
                'is_closed' => $isClosed,
                'open' => $open ?? '09:00:00',
                'close' => $close ?? '20:00:00',
            ];
        }

        $warnings = weekly_hours_warnings($pdo, $proposed);

        $stmt = $pdo->prepare(
            'INSERT INTO shop_weekly_hours (day_of_week, is_closed, open_time, close_time, updated_at)
             VALUES (:dow, :is_closed, :open_time, :close_time, NOW())
             ON CONFLICT (day_of_week)
             DO UPDATE SET is_closed = EXCLUDED.is_closed, open_time = EXCLUDED.open_time,
                           close_time = EXCLUDED.close_time, updated_at = NOW()'
        );
        foreach ($proposed as $dow => $day) {
            $stmt->execute([
                ':dow' => $dow,
                ':is_closed' => $day['is_closed'] ? 'true' : 'false',
                ':open_time' => $day['open'],
                ':close_time' => $day['close'],
            ]);
        }

        audit_log($pdo, 'schedule_update', 'shop_weekly_hours', null, null, ['days' => $proposed]);
        shop_schedule_reset_cache();

        json_response([
            'message' => 'Weekly hours saved.',
            'warnings' => $warnings,
            'resyncRecommended' => true,
            'schedule' => operating_schedule_payload($pdo),
        ]);
    }

    if ($action === 'updateBreaks') {
        $breaks = $input['breaks'] ?? null;
        if (!is_array($breaks)) {
            json_response(['error' => 'Provide a breaks array (may be empty).'], 422);
        }

        $parsed = [];
        foreach ($breaks as $break) {
            $dayRaw = $break['dayOfWeek'] ?? null;
            $day = ($dayRaw === null || $dayRaw === '') ? null : (int)$dayRaw;
            if ($day !== null && ($day < 0 || $day > 6)) {
                json_response(['error' => 'Invalid dayOfWeek in breaks.'], 422);
            }
            $start = schedule_parse_time((string)($break['startTime'] ?? ''));
            $end = schedule_parse_time((string)($break['endTime'] ?? ''));
            if ($start === null || $end === null || $end <= $start) {
                json_response(['error' => 'Each break needs a valid start/end (HH:MM, end after start).'], 422);
            }
            $parsed[] = [
                'day' => $day,
                'start' => $start,
                'end' => $end,
                'label' => trim((string)($break['label'] ?? '')),
            ];
        }

        // Reject overlaps within the same effective scope (global overlaps everything).
        $count = count($parsed);
        for ($i = 0; $i < $count; $i++) {
            for ($j = $i + 1; $j < $count; $j++) {
                $a = $parsed[$i];
                $b = $parsed[$j];
                $sameScope = $a['day'] === null || $b['day'] === null || $a['day'] === $b['day'];
                if ($sameScope && $a['start'] < $b['end'] && $b['start'] < $a['end']) {
                    json_response(['error' => 'Break windows overlap; merge or adjust them.'], 422);
                }
            }
        }

        // Breaks must sit inside the day's open hours.
        $weeklyRows = $pdo->query(
            'SELECT day_of_week, is_closed, open_time, close_time FROM shop_weekly_hours'
        )->fetchAll(PDO::FETCH_ASSOC);
        $weekly = [];
        foreach ($weeklyRows as $row) {
            $weekly[(int)$row['day_of_week']] = $row;
        }
        foreach ($parsed as $break) {
            $daysToCheck = $break['day'] !== null ? [$break['day']] : array_keys($weekly);
            foreach ($daysToCheck as $dow) {
                $day = $weekly[$dow] ?? null;
                if ($day === null || (bool)$day['is_closed']) {
                    continue;
                }
                $open = shop_schedule_time_str((string)$day['open_time']);
                $close = shop_schedule_time_str((string)$day['close_time']);
                if ($break['start'] < $open || $break['end'] > $close) {
                    json_response([
                        'error' => 'Break ' . substr($break['start'], 0, 5) . '–' . substr($break['end'], 0, 5)
                            . ' is outside ' . SCHEDULE_DAY_NAMES[$dow] . ' hours (' . substr($open, 0, 5) . '–' . substr($close, 0, 5) . ').',
                    ], 422);
                }
            }
        }

        $pdo->beginTransaction();
        $pdo->exec('DELETE FROM shop_break_windows');
        $insert = $pdo->prepare(
            'INSERT INTO shop_break_windows (day_of_week, start_time, end_time, label)
             VALUES (:day, :start_time, :end_time, :label)'
        );
        foreach ($parsed as $break) {
            $insert->execute([
                ':day' => $break['day'],
                ':start_time' => $break['start'],
                ':end_time' => $break['end'],
                ':label' => $break['label'] !== '' ? $break['label'] : null,
            ]);
        }
        $pdo->commit();

        audit_log($pdo, 'schedule_update', 'shop_break_windows', null, null, ['breaks' => $parsed]);
        shop_schedule_reset_cache();

        json_response([
            'message' => 'Break windows saved.',
            'resyncRecommended' => true,
            'schedule' => operating_schedule_payload($pdo),
        ]);
    }

    if ($action === 'addClosedDate') {
        $date = trim((string)($input['date'] ?? ''));
        $reason = trim((string)($input['reason'] ?? ''));
        if (!schedule_is_valid_date($date)) {
            json_response(['error' => 'Invalid date (expected YYYY-MM-DD).'], 422);
        }
        if ($date < shop_today()) {
            json_response(['error' => 'Closed dates must be today or in the future.'], 422);
        }

        $apptStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE appointment_date = :d AND status IN ('Scheduled', 'CheckedIn')"
        );
        $apptStmt->execute([':d' => $date]);
        $affected = (int)$apptStmt->fetchColumn();

        $insert = $pdo->prepare(
            'INSERT INTO shop_closed_dates (closed_date, reason)
             VALUES (:closed_date, :reason)
             ON CONFLICT (closed_date) DO UPDATE SET reason = EXCLUDED.reason'
        );
        $insert->execute([
            ':closed_date' => $date,
            ':reason' => $reason !== '' ? $reason : null,
        ]);

        audit_log($pdo, 'schedule_update', 'shop_closed_dates', $date, null, ['date' => $date, 'reason' => $reason]);
        shop_schedule_reset_cache();

        $warnings = [];
        if ($affected > 0) {
            $warnings[] = $affected . ' upcoming appointment(s) exist on ' . $date . '. They remain booked; review them manually.';
        }

        json_response([
            'message' => 'Closed date added.',
            'warnings' => $warnings,
            'schedule' => operating_schedule_payload($pdo),
        ]);
    }

    if ($action === 'removeClosedDate') {
        $date = trim((string)($input['date'] ?? ''));
        if (!schedule_is_valid_date($date)) {
            json_response(['error' => 'Invalid date (expected YYYY-MM-DD).'], 422);
        }
        if ($date < shop_today()) {
            json_response(['error' => 'Past closed dates cannot be removed.'], 422);
        }

        $pdo->prepare('DELETE FROM shop_closed_dates WHERE closed_date = :closed_date')
            ->execute([':closed_date' => $date]);

        audit_log($pdo, 'schedule_update', 'shop_closed_dates', $date, ['date' => $date], null);
        shop_schedule_reset_cache();

        json_response([
            'message' => 'Closed date removed.',
            'schedule' => operating_schedule_payload($pdo),
        ]);
    }

    if ($action === 'updateSlotSettings') {
        $fields = [
            'slotMinutes' => 'shop_slot_duration_minutes',
            'appointmentMinutes' => 'shop_appointment_duration_minutes',
            'walkinMinutes' => 'shop_walkin_duration_minutes',
        ];
        $saved = [];
        $stmt = $pdo->prepare(
            "INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_editable, updated_at)
             VALUES (:setting_key, :setting_value, 'Number', 'operations', '', TRUE, NOW())
             ON CONFLICT (setting_key)
             DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = NOW()"
        );
        foreach ($fields as $field => $key) {
            if (!isset($input[$field])) {
                continue;
            }
            $value = (int)$input[$field];
            if ($value < 5 || $value > 240) {
                json_response(['error' => ucfirst($field) . ' must be between 5 and 240 minutes.'], 422);
            }
            $stmt->execute([':setting_key' => $key, ':setting_value' => (string)$value]);
            $saved[$field] = $value;
        }

        audit_log($pdo, 'schedule_update', 'system_settings', null, null, $saved);
        shop_schedule_reset_cache();

        json_response([
            'message' => 'Slot settings saved.',
            'resyncRecommended' => true,
            'schedule' => operating_schedule_payload($pdo),
        ]);
    }

    if ($action === 'previewSlots') {
        $date = trim((string)($input['date'] ?? shop_today()));
        if (!schedule_is_valid_date($date)) {
            json_response(['error' => 'Invalid date (expected YYYY-MM-DD).'], 422);
        }

        shop_schedule_reset_cache();
        $closed = shop_is_closed_date($date);
        $slots = $closed ? [] : shop_default_slot_times($date);

        json_response([
            'date' => $date,
            'dayName' => SCHEDULE_DAY_NAMES[(int)(shop_weekday($date) ?? 0)],
            'isClosed' => $closed,
            'openTime' => $closed ? null : substr(shop_open_time($date), 0, 5),
            'closeTime' => $closed ? null : substr(shop_close_time($date), 0, 5),
            'breaks' => $closed ? [] : array_map(static fn(array $w): array => [
                'startTime' => substr($w['start'], 0, 5),
                'endTime' => substr($w['end'], 0, 5),
            ], shop_break_windows($date)),
            'slots' => array_map(static fn(string $time): array => [
                'time' => $time,
                'label' => format_time_12h($time),
            ], $slots),
        ]);
    }

    if ($action === 'calendarMonth') {
        $year = (int)($input['year'] ?? 0);
        $month = (int)($input['month'] ?? 0);
        if ($year < 2000 || $month < 1 || $month > 12) {
            json_response(['error' => 'Missing or invalid year/month'], 422);
        }

        shop_schedule_reset_cache();
        $cfg = shop_schedule_config();
        $monthStart = sprintf('%04d-%02d-01', $year, $month);
        $monthEnd = date('Y-m-d', strtotime($monthStart . ' +1 month'));

        $holidayRows = $pdo->prepare(
            'SELECT closed_date, reason FROM shop_closed_dates
             WHERE closed_date >= :start AND closed_date < :end'
        );
        $holidayRows->execute([':start' => $monthStart, ':end' => $monthEnd]);
        $holidayMap = [];
        foreach ($holidayRows->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $holidayMap[(string)$row['closed_date']] = (string)($row['reason'] ?? '');
        }

        $daysInMonth = (int)date('t', strtotime($monthStart));
        $today = shop_today();
        $days = [];

        for ($day = 1; $day <= $daysInMonth; $day++) {
            $date = sprintf('%04d-%02d-%02d', $year, $month, $day);
            $dow = shop_weekday($date) ?? 0;
            $weeklyClosed = (bool)($cfg['weekly'][$dow]['is_closed'] ?? false);
            $isHoliday = isset($holidayMap[$date]);

            if ($isHoliday) {
                $status = 'closed_holiday';
                $reason = $holidayMap[$date] !== '' ? $holidayMap[$date] : 'Holiday / closure';
            } elseif ($weeklyClosed) {
                $status = 'closed_weekly';
                $reason = 'Closed every ' . SCHEDULE_DAY_NAMES[$dow];
            } else {
                $status = 'open';
                $reason = '';
            }

            $closed = $status !== 'open';
            $slots = $closed ? [] : shop_default_slot_times($date);

            $days[] = [
                'date' => $date,
                'dayOfWeek' => $dow,
                'dayName' => SCHEDULE_DAY_NAMES[$dow],
                'status' => $status,
                'reason' => $reason,
                'isPast' => $date < $today,
                'openTime' => $closed ? null : substr(shop_open_time($date), 0, 5),
                'closeTime' => $closed ? null : substr(shop_close_time($date), 0, 5),
                'bookableSlotCount' => count($slots),
            ];
        }

        json_response([
            'year' => $year,
            'month' => $month,
            'monthLabel' => date('F Y', strtotime($monthStart)),
            'days' => $days,
        ]);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
