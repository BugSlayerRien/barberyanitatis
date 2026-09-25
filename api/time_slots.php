<?php
// Time slots API (listByBarberDate)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/group_booking.php';
require_once __DIR__ . '/slot_locking.php';
require_once __DIR__ . '/slot_recommendation.php';
require_once __DIR__ . '/customer_auth.php';
require_once __DIR__ . '/schema_cache.php';

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

    // One row per statement meant ~10 slots x 30 days x every barber round
    // trips to a remote database before suggestBestSlot could answer, which on
    // a cold container blew past the client's timeout and pushed the customer
    // into the manual barber picker. Batched, the same seed is a handful of
    // statements.
    $rows = [];
    foreach ($dates as $slotDate) {
        foreach (default_slot_times($slotDate) as $slotTime) {
            $rows[] = [$barberID, $slotDate, $slotTime, $slotDuration];
        }
    }
    if ($rows === []) {
        return;
    }

    foreach (array_chunk($rows, 200) as $chunk) {
        $placeholders = implode(',', array_fill(0, count($chunk), "(?, ?, ?, ?, 'Available')"));
        $stmt = $pdo->prepare(
            "INSERT INTO time_slots (barber_id, slot_date, slot_time, duration, status)
             VALUES {$placeholders}
             ON CONFLICT (barber_id, slot_date, slot_time) DO NOTHING"
        );
        $params = [];
        foreach ($chunk as $row) {
            array_push($params, ...$row);
        }
        $stmt->execute($params);
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

    $existingStmt = $pdo->prepare(
        'SELECT DISTINCT slot_date FROM time_slots
         WHERE barber_id = :barber_id AND slot_date BETWEEN :start AND :end'
    );
    $existingStmt->execute([
        ':barber_id' => $barberID,
        ':start' => $start,
        ':end' => $end,
    ]);
    $have = [];
    foreach ($existingStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $ymd = shop_pdo_date_ymd($row['slot_date'] ?? '');
        if ($ymd !== '') {
            $have[$ymd] = true;
        }
    }

    $missing = [];
    for ($offset = 0; $offset < $windowDays; $offset++) {
        $date = $today->modify('+' . $offset . ' day')->format('Y-m-d');
        if (!isset($have[$date])) {
            $missing[] = $date;
        }
    }
    if ($missing !== []) {
        seed_slots_for_barber_dates($pdo, $barberID, $missing);
    }
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
        if ($bookedCount > 0 && strtolower($status) === 'available') {
            $status = 'Booked';
        }

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
            if ($bookedCount > 0) {
                $byTime[$normalized]['status'] = 'Booked';
            }
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
        $customer = require_customer($pdo, $input);
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
        $breakFilter = $breakHours === [] ? '' : ' AND EXTRACT(HOUR FROM (ts.slot_time::time)) NOT IN (' . implode(',', $breakHours) . ')';
        $breakFilter2 = str_replace('ts.slot_time', 'ts2.slot_time', $breakFilter);
        $closedDates = array_keys(shop_schedule_config()['closed_dates']);
        $closedFilter = $closedDates === []
            ? ''
            : " AND ts.slot_date NOT IN ('" . implode("','", array_map(static fn(string $d): string => preg_replace('/[^0-9-]/', '', $d), $closedDates)) . "')";

        $baseFrom = " FROM time_slots ts
                   JOIN barbers b ON b.barber_id = ts.barber_id
                  WHERE b.is_active = TRUE{$appointmentFilter}
                    AND ts.status = 'Available'
                    AND ts.slot_date <= :window_end_date{$closedFilter}
                    AND " . bookable_slot_sql_clause() . "
                    AND EXTRACT(MINUTE FROM ts.slot_time) = 0
                    AND EXTRACT(HOUR FROM (ts.slot_time::time)) BETWEEN {$envelopeHours}{$breakFilter}";

        $selectCols = "SELECT ts.barber_id, b.full_name AS barber_name, b.specialty, ts.slot_date, ts.slot_time,
                        (
                            SELECT COUNT(*)::int
                              FROM time_slots ts2
                             WHERE ts2.barber_id = ts.barber_id
                               AND ts2.slot_date = ts.slot_date
                               AND ts2.status = 'Available'
                               AND EXTRACT(MINUTE FROM ts2.slot_time) = 0
                               AND EXTRACT(HOUR FROM (ts2.slot_time::time)) BETWEEN {$envelopeHours}{$breakFilter2}
                        ) AS available_count";

        $baseParams = [
            ':lead_date' => $leadDate,
            ':lead_time' => $leadTime,
            ':window_end_date' => $shopWindowEnd,
        ];

        $runSlotQuery = static function (string $sql, array $params) use ($pdo): array {
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
        };

        $userId = (int)$customer['user_id'];
        $profile = slot_recommendation_build_profile([]);
        if ($userId > 0) {
            $profile = slot_recommendation_build_profile(
                slot_recommendation_load_history($pdo, $userId),
                slot_recommendation_load_rated_favorite($pdo, $userId)
            );
        }

        $cfg = slot_recommendation_config();
        $fetchCandidates = static function () use (
            $runSlotQuery,
            $selectCols,
            $baseFrom,
            $baseParams,
            $profile,
            $cfg
        ): array {
            $rows = [];

            $preferredBarber = (int)($profile['preferred_barber_id'] ?? 0);
            if ($preferredBarber > 0) {
                $params = $baseParams;
                $params[':pref_barber'] = $preferredBarber;
                $rows = array_merge($rows, $runSlotQuery(
                    $selectCols . $baseFrom . ' AND ts.barber_id = :pref_barber ORDER BY ts.slot_date ASC, ts.slot_time ASC LIMIT 40',
                    $params
                ));
            }

            $bucketHours = match ($profile['preferred_bucket'] ?? null) {
                'morning' => [9, 10, 11],
                'afternoon' => [13, 14, 15, 16],
                'evening' => [17, 18, 19],
                default => [],
            };
            if ($bucketHours !== []) {
                $hourList = implode(',', array_map('intval', $bucketHours));
                $rows = array_merge($rows, $runSlotQuery(
                    $selectCols . $baseFrom . " AND EXTRACT(HOUR FROM (ts.slot_time::time)) IN ({$hourList}) ORDER BY ts.slot_date ASC, ts.slot_time ASC LIMIT 40",
                    $baseParams
                ));
            }

            if (($profile['preferred_weekday'] ?? null) !== null && !empty($profile['preferred_weekday_usual'])) {
                $params = $baseParams;
                $params[':pref_dow'] = (int)$profile['preferred_weekday'];
                $rows = array_merge($rows, $runSlotQuery(
                    $selectCols . $baseFrom . ' AND EXTRACT(DOW FROM ts.slot_date) = :pref_dow ORDER BY ts.slot_date ASC, ts.slot_time ASC LIMIT 30',
                    $params
                ));
            }

            $rows = array_merge($rows, $runSlotQuery(
                $selectCols . $baseFrom . ' ORDER BY ts.slot_date ASC, ts.slot_time ASC LIMIT 30',
                $baseParams
            ));

            return slot_recommendation_dedupe_candidates($rows, (int)$cfg['candidate_cap']);
        };

        $candidates = $fetchCandidates();
        // Seeding every active barber across the whole booking window is the
        // most expensive thing this endpoint can do. Throttled so a genuinely
        // fully-booked shop doesn't pay for it on every suggestion request --
        // only a real gap in the calendar triggers a re-seed.
        if ($candidates === [] && schema_cache_should_run('suggest_seed_all_barbers', 300)) {
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
            schema_cache_done('suggest_seed_all_barbers');
            $candidates = $fetchCandidates();
        }

        $normalized = [];
        $nowTs = shop_now();
        foreach ($candidates as $row) {
            $slotDate = shop_pdo_date_ymd($row['slot_date'] ?? '');
            $timeStr = shop_pdo_time_hms($row['slot_time'] ?? '');
            $slotTime = shop_normalize_slot_time($timeStr, $slotDate);
            if ($slotDate === '' || $slotTime === null) {
                continue;
            }
            $slotDt = shop_slot_start_datetime($slotDate, $slotTime);
            if ($slotDt === null || $slotDt < $nowTs || !shop_is_suggestable_slot($slotDate, $slotTime)) {
                continue;
            }
            $row['slot_date'] = $slotDate;
            $row['slot_time'] = $slotTime;
            $row['barber_id'] = (int)($row['barber_id'] ?? 0);
            $normalized[] = $row;
        }

        if ($normalized === []) {
            json_response(['error' => 'No available slots found'], 404);
        }

        $earliestDate = (string)$normalized[0]['slot_date'];
        foreach ($normalized as $row) {
            if ((string)$row['slot_date'] < $earliestDate) {
                $earliestDate = (string)$row['slot_date'];
            }
        }

        $dayAvailableHours = [];
        $knownOccupancyDays = [];
        $pairs = [];
        foreach ($normalized as $row) {
            $pairs[(int)$row['barber_id'] . '|' . $row['slot_date']] = [
                'barber_id' => (int)$row['barber_id'],
                'slot_date' => (string)$row['slot_date'],
            ];
        }
        if ($pairs !== []) {
            $pairSql = [];
            $occParams = [];
            $i = 0;
            foreach ($pairs as $pair) {
                $b = ':ob' . $i;
                $d = ':od' . $i;
                $pairSql[] = "(barber_id = {$b} AND slot_date = {$d})";
                $occParams[$b] = $pair['barber_id'];
                $occParams[$d] = $pair['slot_date'];
                $i++;
            }
            $occStmt = $pdo->prepare(
                'SELECT barber_id, slot_date, EXTRACT(HOUR FROM (slot_time::time))::int AS hour, status
                   FROM time_slots
                  WHERE (' . implode(' OR ', $pairSql) . ")
                    AND EXTRACT(MINUTE FROM slot_time) = 0"
            );
            $occStmt->execute($occParams);
            foreach ($occStmt->fetchAll(PDO::FETCH_ASSOC) as $occ) {
                $occDate = shop_pdo_date_ymd($occ['slot_date'] ?? '');
                $key = (int)$occ['barber_id'] . '|' . $occDate;
                $knownOccupancyDays[$key] = true;
                if (strcasecmp((string)$occ['status'], 'Available') === 0) {
                    $dayAvailableHours[$key] ??= [];
                    $hour = (int)$occ['hour'];
                    if (!in_array($hour, $dayAvailableHours[$key], true)) {
                        $dayAvailableHours[$key][] = $hour;
                    }
                }
            }
        }

        $ranked = slot_recommendation_rank(
            $normalized,
            $profile,
            $dayAvailableHours,
            $earliestDate,
            $knownOccupancyDays
        );
        $primary = $ranked['primary'];
        if ($primary === null) {
            json_response(['error' => 'No available time for suggested slot'], 404);
        }

        $leadHours = shop_booking_lead_hours();
        $alternatives = [];
        foreach ($ranked['alternatives'] as $alt) {
            $alternatives[] = slot_recommendation_public_payload($alt, $leadHours);
        }

        json_response([
            'suggestion' => slot_recommendation_public_payload($primary, $leadHours),
            'alternatives' => $alternatives,
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

        $hourFilter = "EXTRACT(MINUTE FROM slot_time) = 0
               AND EXTRACT(HOUR FROM (slot_time::time)) BETWEEN 9 AND 19
               AND EXTRACT(HOUR FROM (slot_time::time)) <> 12";

        $stmt = $pdo->prepare(
            "SELECT slot_date, slot_time
             FROM time_slots
             WHERE barber_id = :barber_id
               AND status = 'Available'
               AND slot_date >= :start_date
               AND slot_date < :end_date
               AND slot_date <= :window_end_date
               AND " . calendar_bookable_slot_sql_clause() . "
               AND {$hourFilter}"
        );
        $stmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
            ':window_end_date' => $windowEndDate,
            ':min_date' => $minDate,
            ':min_time' => $minTime,
        ]);
        $availableTimes = [];
        foreach ($stmt->fetchAll() as $row) {
            $ymd = shop_pdo_date_ymd($row['slot_date'] ?? '');
            $time = shop_normalize_slot_time((string)($row['slot_time'] ?? ''), $ymd !== '' ? $ymd : null);
            if ($ymd === '' || $time === null) {
                continue;
            }
            $availableTimes[$ymd][$time] = true;
        }

        $bookedStmt = $pdo->prepare(
            "SELECT slot_date, slot_time
             FROM time_slots
             WHERE barber_id = :barber_id
               AND LOWER(status) = 'booked'
               AND slot_date >= :start_date
               AND slot_date < :end_date
               AND {$hourFilter}"
        );
        $bookedStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        $bookedTimes = [];
        foreach ($bookedStmt->fetchAll() as $row) {
            $ymd = shop_pdo_date_ymd($row['slot_date'] ?? '');
            $time = shop_normalize_slot_time((string)($row['slot_time'] ?? ''), $ymd !== '' ? $ymd : null);
            if ($ymd === '' || $time === null) {
                continue;
            }
            $bookedTimes[$ymd][$time] = true;
        }

        $occupiedStmt = $pdo->prepare(
            "SELECT appointment_date, start_time
             FROM appointments
             WHERE barber_id = :barber_id
               AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
               AND appointment_date >= :start_date
               AND appointment_date < :end_date"
        );
        $occupiedStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        foreach ($occupiedStmt->fetchAll() as $row) {
            $ymd = shop_pdo_date_ymd($row['appointment_date'] ?? '');
            $time = shop_normalize_slot_time((string)($row['start_time'] ?? ''), $ymd !== '' ? $ymd : null);
            if ($ymd === '' || $time === null) {
                continue;
            }
            $bookedTimes[$ymd][$time] = true;
            unset($availableTimes[$ymd][$time]);
        }

        $availability = [];
        for ($day = 1; $day <= $daysInMonth; $day++) {
            $date = sprintf('%04d-%02d-%02d', $year, $month, $day);
            $closure = shop_closure_details($date);
            $availableCount = $closure['isClosed'] ? 0 : count($availableTimes[$date] ?? []);
            $bookedCount = count($bookedTimes[$date] ?? []);
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
            WHERE status IN ('Scheduled', 'CheckedIn', 'InProgress')
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

    $holdStmt = $pdo->prepare(
        "SELECT start_time, COUNT(*) AS booked_count
         FROM appointments
         WHERE barber_id = :barber_id
           AND appointment_date = :slot_date
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
         GROUP BY start_time"
    );
    $holdStmt->execute([
        ':barber_id' => $barberID,
        ':slot_date' => $slotDate,
    ]);
    $heldByTime = [];
    foreach ($holdStmt->fetchAll() as $hold) {
        $time = shop_normalize_slot_time((string)($hold['start_time'] ?? ''), $slotDate);
        if ($time === null) {
            continue;
        }
        $heldByTime[$time] = (int)$hold['booked_count'];
    }
    foreach ($merged as &$slot) {
        $time = (string)($slot['slot_time'] ?? '');
        if (!isset($heldByTime[$time])) {
            continue;
        }
        $slot['booked_count'] = max((int)($slot['booked_count'] ?? 0), $heldByTime[$time]);
        if (strtolower((string)($slot['status'] ?? '')) === 'available') {
            $slot['status'] = 'Booked';
        }
    }
    unset($slot);

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
