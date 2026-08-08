<?php
// Time slots API (listByBarberDate)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/group_booking.php';
require_once __DIR__ . '/slot_locking.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['listByBarberDate', 'suggestBestSlot', 'availabilityByBarberMonth', 'findGroupSlots'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

/**
 * @return string[]
 */
function default_slot_times(?string $date = null): array
{
    return shop_default_slot_times($date);
}

function seed_slots_for_barber_dates(PDO $pdo, int $barberID, array $dates): void
{
    if ($barberID <= 0 || !$dates) {
        return;
    }

    $slotDuration = shop_slot_duration_minutes();
    $insertStmt = $pdo->prepare(
        "INSERT INTO time_slots (barber_id, slot_date, slot_time, duration, status)
         VALUES (:barber_id, :slot_date, :slot_time, :duration, 'Available')
         ON CONFLICT (barber_id, slot_date, slot_time) DO NOTHING"
    );

    foreach ($dates as $slotDate) {
        foreach (default_slot_times($slotDate) as $slotTime) {
            $insertStmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
                ':slot_time' => $slotTime,
                ':duration' => $slotDuration,
            ]);
        }
    }
}

function seed_week_for_barber(PDO $pdo, int $barberID, ?int $windowDays = null): void
{
    $windowDays = $windowDays ?? shop_booking_window_days();
    if ($barberID <= 0 || $windowDays <= 0) {
        return;
    }

    $today = shop_now()->setTime(0, 0);
    $dates = [];
    for ($offset = 0; $offset < $windowDays; $offset++) {
        $dates[] = $today->modify('+' . $offset . ' day')->format('Y-m-d');
    }

    seed_slots_for_barber_dates($pdo, $barberID, $dates);
}

/** Avoid re-inserting hundreds of rows on every suggestBestSlot call (slow on remote DB). */
function ensure_week_seeded_for_barber(PDO $pdo, int $barberID, ?int $windowDays = null): void
{
    $windowDays = $windowDays ?? shop_booking_window_days();
    if ($barberID <= 0 || $windowDays <= 0) {
        return;
    }

    $today = shop_now()->setTime(0, 0);
    $start = $today->format('Y-m-d');
    $end = $today->modify('+' . ($windowDays - 1) . ' day')->format('Y-m-d');

    $check = $pdo->prepare(
        'SELECT COUNT(*) FROM time_slots
         WHERE barber_id = :barber_id AND slot_date BETWEEN :start AND :end'
    );
    $check->execute([
        ':barber_id' => $barberID,
        ':start' => $start,
        ':end' => $end,
    ]);
    if ((int)$check->fetchColumn() > 0) {
        return;
    }

    seed_week_for_barber($pdo, $barberID, $windowDays);
}

/**
 * @param array<int, array<string, mixed>> $dbRows
 * @return array<int, array<string, mixed>>
 */
function merge_barber_slots_for_date(array $dbRows, int $capacity = 10, ?string $slotDate = null): array
{
    $byTime = [];
    foreach ($dbRows as $row) {
        $normalized = shop_normalize_slot_time((string)($row['slot_time'] ?? ''), $slotDate);
        if ($normalized === null) {
            continue;
        }

        $existing = $byTime[$normalized] ?? null;
        $status = (string)($row['status'] ?? 'Available');
        $bookedCount = (int)($row['booked_count'] ?? 0);

        if ($existing === null) {
            $byTime[$normalized] = [
                'slot_id' => $row['slot_id'] ?? null,
                'slot_time' => $normalized,
                'status' => $status,
                'booked_count' => $bookedCount,
                'capacity' => (int)($row['capacity'] ?? $capacity),
            ];
            continue;
        }

        $existingStatus = (string)($existing['status'] ?? 'Available');
        $existingBooked = (int)($existing['booked_count'] ?? 0);
        if ($existingStatus === 'Available' && $status !== 'Available') {
            $byTime[$normalized] = [
                'slot_id' => $row['slot_id'] ?? $existing['slot_id'] ?? null,
                'slot_time' => $normalized,
                'status' => $status,
                'booked_count' => $bookedCount,
                'capacity' => (int)($row['capacity'] ?? $capacity),
            ];
        } elseif ($existingStatus === 'Available' && $status === 'Available' && $bookedCount > $existingBooked) {
            $byTime[$normalized]['booked_count'] = $bookedCount;
        }
    }

    $merged = [];
    foreach (default_slot_times($slotDate) as $slotTime) {
        if (isset($byTime[$slotTime])) {
            $merged[] = $byTime[$slotTime];
            continue;
        }

        $merged[] = [
            'slot_id' => null,
            'slot_time' => $slotTime,
            'status' => 'Available',
            'booked_count' => 0,
            'capacity' => $capacity,
        ];
    }

    return $merged;
}

function future_slot_sql_clause(): string
{
    return '(slot_date > :shop_today OR (slot_date = :shop_today AND slot_time > :shop_now_time))';
}

function bookable_slot_sql_clause(): string
{
    return '(slot_date > :lead_date OR (slot_date = :lead_date AND slot_time >= :lead_time))';
}

function calendar_bookable_slot_sql_clause(): string
{
    return '(slot_date > :min_date OR (slot_date = :min_date AND slot_time >= :min_time))';
}

function build_suggestion_reason(string $slotDate, string $slotTime, int $barberId, int $availableCount): string
{
    $slotDt = shop_slot_start_datetime($slotDate, $slotTime);
    $now = shop_now();
    if ($slotDt === null) {
        return 'This is the next open appointment slot for your selected barber.';
    }

    $leadHours = shop_booking_lead_hours();
    $sameDay = $slotDate === shop_today();
    $timeLabel = format_time_12h($slotTime);

    if ($sameDay) {
        $hoursUntil = max(0, (int)floor(($slotDt->getTimestamp() - $now->getTimestamp()) / 3600));
        return "Earliest available slot today at {$timeLabel} (about {$hoursUntil} hour(s) from now). "
            . "We require at least {$leadHours} hours notice for suggested bookings. "
            . "Barber #{$barberId} has {$availableCount} open hour(s) this day.";
    }

    return "No open slots remain today after the {$leadHours}-hour booking window. "
        . "The next available time is {$slotDate} at {$timeLabel} with {$availableCount} open hour(s) that day.";
}

try {
    $pdo = get_db_connection();
    ensure_barber_channel_column($pdo);

    if ($action === 'listByBarberDate') {
        auto_complete_due_appointments($pdo);
        reconcile_pending_payment_slots($pdo);
    }

    if ($action === 'suggestBestSlot') {
        $appointmentFilter = barber_channel_filter_sql('appointment', 'b.barber_channel');
        $leadStart = shop_next_bookable_slot_start();
        $leadDate = $leadStart->format('Y-m-d');
        $leadTime = $leadStart->format('H:i:s');
        $bookingWindowDays = shop_booking_window_days();
        $shopWindowEnd = shop_window_end_date($bookingWindowDays);

        // Dynamic envelope bounds (per-date rules re-checked after the query).
        $envelopeTimes = shop_default_slot_times();
        $envelopeHours = $envelopeTimes === []
            ? '9 AND 19'
            : (int)substr($envelopeTimes[0], 0, 2) . ' AND ' . (int)substr($envelopeTimes[count($envelopeTimes) - 1], 0, 2);
        $breakHours = [];
        foreach ($envelopeTimes === [] ? [] : range((int)substr($envelopeTimes[0], 0, 2), (int)substr($envelopeTimes[count($envelopeTimes) - 1], 0, 2)) as $hour) {
            if (shop_is_break_slot_time(sprintf('%02d:00:00', $hour))) {
                $breakHours[] = $hour;
            }
        }
        $breakFilter = $breakHours === [] ? '' : ' AND EXTRACT(HOUR FROM ts.slot_time) NOT IN (' . implode(',', $breakHours) . ')';
        $breakFilter2 = str_replace('ts.slot_time', 'ts2.slot_time', $breakFilter);
        $closedDates = array_keys(shop_schedule_config()['closed_dates']);
        $closedFilter = $closedDates === []
            ? ''
            : " AND ts.slot_date NOT IN ('" . implode("','", array_map(static fn(string $d): string => preg_replace('/[^0-9-]/', '', $d), $closedDates)) . "')";

        $runBestSlotQuery = static function (PDO $pdo, string $leadDate, string $leadTime, string $shopWindowEnd, string $appointmentFilter) use ($envelopeHours, $breakFilter, $breakFilter2, $closedFilter): ?array {
            $bestStmt = $pdo->prepare(
                "SELECT ts.barber_id, ts.slot_date, ts.slot_time,
                        (
                            SELECT COUNT(*)::int
                              FROM time_slots ts2
                             WHERE ts2.barber_id = ts.barber_id
                               AND ts2.slot_date = ts.slot_date
                               AND ts2.status = 'Available'
                               AND EXTRACT(MINUTE FROM ts2.slot_time) = 0
                               AND EXTRACT(HOUR FROM ts2.slot_time) BETWEEN {$envelopeHours}{$breakFilter2}
                        ) AS available_count
                   FROM time_slots ts
                   JOIN barbers b ON b.barber_id = ts.barber_id
                  WHERE b.is_active = TRUE{$appointmentFilter}
                    AND ts.status = 'Available'
                    AND ts.slot_date <= :window_end_date{$closedFilter}
                    AND " . bookable_slot_sql_clause() . "
                    AND EXTRACT(MINUTE FROM ts.slot_time) = 0
                    AND EXTRACT(HOUR FROM ts.slot_time) BETWEEN {$envelopeHours}{$breakFilter}
                  ORDER BY ts.slot_date ASC, ts.slot_time ASC
                  LIMIT 1"
            );
            $bestStmt->execute([
                ':lead_date' => $leadDate,
                ':lead_time' => $leadTime,
                ':window_end_date' => $shopWindowEnd,
            ]);

            $row = $bestStmt->fetch();
            return $row === false ? null : $row;
        };

        $best = $runBestSlotQuery($pdo, $leadDate, $leadTime, $shopWindowEnd, $appointmentFilter);

        if (!$best) {
            $seedStmt = $pdo->prepare(
                "SELECT barber_id FROM barbers WHERE is_active = TRUE{$appointmentFilter}"
            );
            $seedStmt->execute();
            foreach ($seedStmt->fetchAll() as $barberRow) {
                $barberID = (int)($barberRow['barber_id'] ?? 0);
                if ($barberID > 0) {
                    ensure_week_seeded_for_barber($pdo, $barberID, $bookingWindowDays);
                }
            }
            $best = $runBestSlotQuery($pdo, $leadDate, $leadTime, $shopWindowEnd, $appointmentFilter);
        }

        if (!$best) {
            json_response(['error' => 'No available slots found'], 404);
        }

        $normalizedSlotTime = shop_normalize_slot_time((string)$best['slot_time'], (string)$best['slot_date']);
        if ($normalizedSlotTime === null || !shop_is_suggestable_slot((string)$best['slot_date'], $normalizedSlotTime)) {
            json_response(['error' => 'No available time for suggested slot'], 404);
        }

        $barberStmt = $pdo->prepare('SELECT barber_id, full_name, specialty FROM barbers WHERE barber_id = :barber_id');
        $barberStmt->execute([':barber_id' => $best['barber_id']]);
        $barber = $barberStmt->fetch();

        $barberId = (int)$best['barber_id'];
        $availableCount = (int)($best['available_count'] ?? 0);
        $reason = build_suggestion_reason((string)$best['slot_date'], $normalizedSlotTime, $barberId, $availableCount);

        json_response([
            'suggestion' => [
                'barberID' => $barberId,
                'barberName' => $barber['full_name'] ?? 'Barber',
                'specialty' => $barber['specialty'] ?? null,
                'slotDate' => $best['slot_date'],
                'slotTime' => $normalizedSlotTime,
                'availableCount' => $availableCount,
                'suggestionReason' => $reason,
                'leadHours' => shop_booking_lead_hours(),
                'isFallback' => false,
            ],
        ]);
    }

    if ($action === 'availabilityByBarberMonth') {
        $barberID = (int)($input['barberID'] ?? 0);
        $year = (int)($input['year'] ?? 0);
        $month = (int)($input['month'] ?? 0);

        if ($barberID <= 0 || $year < 2000 || $month < 1 || $month > 12) {
            json_response(['error' => 'Missing or invalid barberID/year/month'], 422);
        }

        $bookingWindowDays = shop_booking_window_days();
        ensure_week_seeded_for_barber($pdo, $barberID, $bookingWindowDays);

        $startDate = sprintf('%04d-%02d-01', $year, $month);
        $endDate = date('Y-m-d', strtotime($startDate . ' +1 month'));
        $windowEndDate = shop_window_end_date($bookingWindowDays);
        $minBookable = shop_earliest_bookable_slot_start();
        $minDate = $minBookable->format('Y-m-d');
        $minTime = $minBookable->format('H:i:s');
        $daysInMonth = (int)date('t', strtotime($startDate));

        $stmt = $pdo->prepare(
            "SELECT slot_date, COUNT(*) AS available_count
             FROM time_slots
             WHERE barber_id = :barber_id
               AND status = 'Available'
               AND slot_date >= :start_date
               AND slot_date < :end_date
               AND slot_date <= :window_end_date
               AND " . calendar_bookable_slot_sql_clause() . "
               AND EXTRACT(MINUTE FROM slot_time) = 0
               AND EXTRACT(HOUR FROM slot_time) BETWEEN 9 AND 19
               AND EXTRACT(HOUR FROM slot_time) <> 12
             GROUP BY slot_date"
        );
        $stmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
            ':window_end_date' => $windowEndDate,
            ':min_date' => $minDate,
            ':min_time' => $minTime,
        ]);
        $availableMap = [];
        foreach ($stmt->fetchAll() as $row) {
            $availableMap[(string)$row['slot_date']] = (int)$row['available_count'];
        }

        $bookedStmt = $pdo->prepare(
            "SELECT slot_date, COUNT(*) AS booked_count
             FROM time_slots
             WHERE barber_id = :barber_id
               AND LOWER(status) = 'booked'
               AND slot_date >= :start_date
               AND slot_date < :end_date
               AND EXTRACT(MINUTE FROM slot_time) = 0
               AND EXTRACT(HOUR FROM slot_time) BETWEEN 9 AND 19
               AND EXTRACT(HOUR FROM slot_time) <> 12
             GROUP BY slot_date"
        );
        $bookedStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        $bookedMap = [];
        foreach ($bookedStmt->fetchAll() as $row) {
            $bookedMap[(string)$row['slot_date']] = (int)$row['booked_count'];
        }

        $availability = [];
        for ($day = 1; $day <= $daysInMonth; $day++) {
            $date = sprintf('%04d-%02d-%02d', $year, $month, $day);
            $closure = shop_closure_details($date);
            $availableCount = $closure['isClosed'] ? 0 : (int)($availableMap[$date] ?? 0);
            $bookedCount = (int)($bookedMap[$date] ?? 0);
            $defaultTotal = $closure['isClosed'] ? 0 : count(shop_default_slot_times($date));
            $totalSlots = max($defaultTotal, $availableCount + $bookedCount);

            $availability[] = [
                'slotDate' => $date,
                'availableCount' => $availableCount,
                'bookedCount' => $bookedCount,
                'totalSlots' => $totalSlots,
                'isClosed' => $closure['isClosed'],
                'closureStatus' => $closure['status'],
                'closureReason' => $closure['reason'],
                'closureMessage' => $closure['customerMessage'],
            ];
        }

        json_response(['availability' => $availability]);
    }

    if ($action === 'findGroupSlots') {
        $barberID = (int)($input['barberID'] ?? 0);
        $peopleCount = (int)($input['peopleCount'] ?? $input['groupSize'] ?? 0);
        $preferredDate = trim((string)($input['slotDate'] ?? $input['appointmentDate'] ?? ''));

        if ($peopleCount < 1 || $peopleCount > 5) {
            json_response(['error' => 'peopleCount must be between 1 and 5'], 422);
        }

        if ($preferredDate !== '' && !preg_match('/^\d{4}-\d{2}-\d{2}$/', $preferredDate)) {
            json_response(['error' => 'Invalid slotDate'], 422);
        }

        ensure_group_booking_schema($pdo);
        ensure_barber_channel_column($pdo);

        if ($barberID > 0) {
            ensure_week_seeded_for_barber($pdo, $barberID, shop_booking_window_days());
        }

        $result = find_group_booking_options($pdo, $barberID, $peopleCount, $preferredDate !== '' ? $preferredDate : null);
        json_response($result);
    }

    $barberID = (int)($input['barberID'] ?? 0);
    $slotDate = trim((string)($input['slotDate'] ?? ''));

    if ($barberID <= 0 || $slotDate === '') {
        json_response(['error' => 'Missing barberID or slotDate'], 422);
    }

    $capacity = 10;
    $stmt = $pdo->prepare(
        "SELECT ts.slot_id,
                ts.slot_time,
                ts.status,
                COALESCE(appt.booked_count, 0) AS booked_count,
                {$capacity} AS capacity
         FROM time_slots ts
         LEFT JOIN (
            SELECT barber_id, appointment_date, start_time, COUNT(*) AS booked_count
            FROM appointments
            WHERE status IN ('Scheduled', 'CheckedIn', 'InProgress', 'Completed')
            GROUP BY barber_id, appointment_date, start_time
         ) appt
           ON appt.barber_id = ts.barber_id
          AND appt.appointment_date = ts.slot_date
          AND appt.start_time = ts.slot_time
         WHERE ts.barber_id = :barber_id AND ts.slot_date = :slot_date
         ORDER BY ts.slot_time"
    );
    $stmt->execute([
        ':barber_id' => $barberID,
        ':slot_date' => $slotDate,
    ]);

    $rows = array_values(array_filter($stmt->fetchAll(), static function (array $row) use ($slotDate): bool {
        return !shop_is_break_slot_time((string)($row['slot_time'] ?? ''), $slotDate);
    }));

    if (!$rows) {
        $requestedDate = DateTimeImmutable::createFromFormat('Y-m-d', $slotDate, new DateTimeZone(shop_timezone()));
        $today = shop_now()->setTime(0, 0);
        $windowEndDate = shop_window_end_date();

        if ($requestedDate !== false && $requestedDate >= $today && $requestedDate->format('Y-m-d') <= $windowEndDate) {
            seed_slots_for_barber_dates($pdo, $barberID, [$slotDate]);

            $stmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
            ]);
            $rows = $stmt->fetchAll();
        }
    }

    $merged = merge_barber_slots_for_date($rows, $capacity, $slotDate);
    $minBookable = shop_earliest_bookable_slot_start();
    foreach ($merged as &$slot) {
        $time = (string)($slot['slot_time'] ?? '');
        $dt = shop_slot_start_datetime($slotDate, $time);
        $bookable = $dt !== null
            && $dt >= $minBookable
            && (string)($slot['status'] ?? '') === 'Available';
        $slot['isBookable'] = $bookable;
        if (!$bookable && (string)($slot['status'] ?? '') === 'Available') {
            $slot['status'] = 'Unavailable';
        }
    }
    unset($slot);

    $closure = shop_closure_details($slotDate);
    $bookedCount = 0;
    $availableCount = 0;
    foreach ($merged as $slot) {
        $status = strtolower((string)($slot['status'] ?? ''));
        if ($status === 'booked') {
            $bookedCount++;
        } elseif (!empty($slot['isBookable'])) {
            $availableCount++;
        }
    }

    json_response([
        'slots' => $closure['isClosed'] ? [] : $merged,
        'isClosed' => $closure['isClosed'],
        'closureStatus' => $closure['status'],
        'closureReason' => $closure['reason'],
        'closureMessage' => $closure['customerMessage'],
        'availableCount' => $closure['isClosed'] ? 0 : $availableCount,
        'bookedCount' => $bookedCount,
        'totalSlots' => $closure['isClosed'] ? 0 : count($merged),
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response([
        'error' => 'Server error',
        'details' => $e->getMessage(),
    ], 500);
}
