<?php
// Time slots API (listByBarberDate)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['listByBarberDate', 'suggestBestSlot', 'availabilityByBarberMonth'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

/**
 * @return string[]
 */
function default_slot_times(): array
{
    return shop_default_slot_times();
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
        foreach (default_slot_times() as $slotTime) {
            $insertStmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
                ':slot_time' => $slotTime,
                ':duration' => $slotDuration,
            ]);
        }
    }
}

function seed_week_for_barber(PDO $pdo, int $barberID, int $windowDays = 7): void
{
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

/**
 * @param array<int, array<string, mixed>> $dbRows
 * @return array<int, array<string, mixed>>
 */
function merge_barber_slots_for_date(array $dbRows, int $capacity = 10): array
{
    $byTime = [];
    foreach ($dbRows as $row) {
        $normalized = shop_normalize_slot_time((string)($row['slot_time'] ?? ''));
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
    foreach (default_slot_times() as $slotTime) {
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

try {
    $pdo = get_db_connection();
    auto_complete_due_appointments($pdo);

    if ($action === 'suggestBestSlot') {
        $activeBarbersStmt = $pdo->prepare('SELECT barber_id FROM barbers WHERE is_active = TRUE');
        $activeBarbersStmt->execute();
        $activeBarbers = $activeBarbersStmt->fetchAll();

        if (!$activeBarbers) {
            json_response(['error' => 'No available slots found'], 404);
        }

        foreach ($activeBarbers as $barberRow) {
            $barberID = (int)($barberRow['barber_id'] ?? 0);
            if ($barberID > 0) {
                seed_week_for_barber($pdo, $barberID, 7);
            }
        }

        $shopToday = shop_today();
        $shopNowTime = shop_current_time();
        $shopWindowEnd = shop_window_end_date(7);

        $bestStmt = $pdo->prepare(
            "SELECT barber_id, slot_date, COUNT(*) AS available_count
             FROM time_slots
             WHERE status = 'Available'
               AND slot_date <= :window_end_date
               AND " . future_slot_sql_clause() . "
               AND EXTRACT(MINUTE FROM slot_time) = 0
               AND EXTRACT(HOUR FROM slot_time) BETWEEN 9 AND 19
             GROUP BY barber_id, slot_date
             ORDER BY slot_date ASC, available_count DESC, barber_id ASC
             LIMIT 1"
        );
        $bestStmt->execute([
            ':shop_today' => $shopToday,
            ':shop_now_time' => $shopNowTime,
            ':window_end_date' => $shopWindowEnd,
        ]);
        $best = $bestStmt->fetch();

        if (!$best) {
            json_response(['error' => 'No available slots found'], 404);
        }

        $timeStmt = $pdo->prepare(
            "SELECT slot_time FROM time_slots
               WHERE barber_id = :barber_id
                AND slot_date = :slot_date
                AND status = 'Available'
                AND slot_date <= :window_end_date
                AND " . future_slot_sql_clause() . "
                AND EXTRACT(MINUTE FROM slot_time) = 0
                AND EXTRACT(HOUR FROM slot_time) BETWEEN 9 AND 19
             ORDER BY slot_time ASC LIMIT 1"
        );
        $timeStmt->execute([
            ':barber_id' => $best['barber_id'],
            ':slot_date' => $best['slot_date'],
            ':shop_today' => $shopToday,
            ':shop_now_time' => $shopNowTime,
            ':window_end_date' => $shopWindowEnd,
        ]);
        $timeRow = $timeStmt->fetch();
        if (!$timeRow) {
            json_response(['error' => 'No available time for suggested slot'], 404);
        }

        $normalizedSlotTime = shop_normalize_slot_time((string)$timeRow['slot_time']);
        if ($normalizedSlotTime === null || !shop_is_future_slot((string)$best['slot_date'], $normalizedSlotTime)) {
            json_response(['error' => 'No available time for suggested slot'], 404);
        }

        $barberStmt = $pdo->prepare('SELECT barber_id, full_name, specialty FROM barbers WHERE barber_id = :barber_id');
        $barberStmt->execute([':barber_id' => $best['barber_id']]);
        $barber = $barberStmt->fetch();

        json_response([
            'suggestion' => [
                'barberID' => (int)$best['barber_id'],
                'barberName' => $barber['full_name'] ?? 'Barber',
                'specialty' => $barber['specialty'] ?? null,
                'slotDate' => $best['slot_date'],
                'slotTime' => $normalizedSlotTime,
                'availableCount' => (int)$best['available_count'],
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

                seed_week_for_barber($pdo, $barberID, 7);

        $startDate = sprintf('%04d-%02d-01', $year, $month);
        $endDate = date('Y-m-d', strtotime($startDate . ' +1 month'));
        $windowEndDate = shop_window_end_date(7);
        $shopToday = shop_today();
        $shopNowTime = shop_current_time();

        $stmt = $pdo->prepare(
            "SELECT slot_date, COUNT(*) AS available_count
             FROM time_slots
             WHERE barber_id = :barber_id
               AND status = 'Available'
               AND slot_date >= :start_date
               AND slot_date < :end_date
               AND slot_date <= :window_end_date
               AND " . future_slot_sql_clause() . "
               AND EXTRACT(MINUTE FROM slot_time) = 0
               AND EXTRACT(HOUR FROM slot_time) BETWEEN 9 AND 19
             GROUP BY slot_date"
        );
        $stmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
            ':window_end_date' => $windowEndDate,
            ':shop_today' => $shopToday,
            ':shop_now_time' => $shopNowTime,
        ]);
        $rows = $stmt->fetchAll();

        $availability = [];
        foreach ($rows as $row) {
            $availability[] = [
                'slotDate' => (string)$row['slot_date'],
                'availableCount' => (int)$row['available_count'],
            ];
        }

        json_response(['availability' => $availability]);
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
            WHERE status NOT IN ('Cancelled', 'NoShow')
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

    $rows = $stmt->fetchAll();

    if (!$rows) {
        $requestedDate = DateTimeImmutable::createFromFormat('Y-m-d', $slotDate, new DateTimeZone(shop_timezone()));
        $today = shop_now()->setTime(0, 0);
        $windowEndDate = shop_window_end_date(7);

        if ($requestedDate !== false && $requestedDate >= $today && $requestedDate->format('Y-m-d') <= $windowEndDate) {
            seed_slots_for_barber_dates($pdo, $barberID, [$slotDate]);

            $stmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
            ]);
            $rows = $stmt->fetchAll();
        }
    }

    json_response(['slots' => merge_barber_slots_for_date($rows, $capacity)]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
