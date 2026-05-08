<?php
// Time slots API (listByBarberDate)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

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
    return [
        '09:00:00',
        '09:50:00',
        '10:40:00',
        '11:30:00',
        '12:20:00',
        '13:10:00',
        '14:00:00',
        '14:50:00',
        '15:40:00',
        '16:30:00',
    ];
}

function seed_slots_for_barber_dates(PDO $pdo, int $barberID, array $dates): void
{
    if ($barberID <= 0 || !$dates) {
        return;
    }

    $insertStmt = $pdo->prepare(
        "INSERT INTO time_slots (barber_id, slot_date, slot_time, duration, status)
         VALUES (:barber_id, :slot_date, :slot_time, 35, 'Available')
         ON CONFLICT (barber_id, slot_date, slot_time) DO NOTHING"
    );

    foreach ($dates as $slotDate) {
        foreach (default_slot_times() as $slotTime) {
            $insertStmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
                ':slot_time' => $slotTime,
            ]);
        }
    }
}

function seed_week_for_barber(PDO $pdo, int $barberID, int $windowDays = 7): void
{
    if ($barberID <= 0 || $windowDays <= 0) {
        return;
    }

    $today = new DateTimeImmutable('today');
    $dates = [];
    for ($offset = 0; $offset < $windowDays; $offset++) {
        $dates[] = $today->modify('+' . $offset . ' day')->format('Y-m-d');
    }

    seed_slots_for_barber_dates($pdo, $barberID, $dates);
}

try {
    $pdo = get_db_connection();

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

        $bestStmt = $pdo->prepare(
            "SELECT barber_id, slot_date, COUNT(*) AS available_count
             FROM time_slots
             WHERE status = 'Available'
                             AND slot_date <= (CURRENT_DATE + INTERVAL '6 day')
               AND (
                    slot_date > CURRENT_DATE
                    OR (slot_date = CURRENT_DATE AND slot_time > CURRENT_TIME)
               )
             GROUP BY barber_id, slot_date
             ORDER BY slot_date ASC, available_count DESC, barber_id ASC
             LIMIT 1"
        );
        $bestStmt->execute();
        $best = $bestStmt->fetch();

        if (!$best) {
            json_response(['error' => 'No available slots found'], 404);
        }

        $timeStmt = $pdo->prepare(
            "SELECT slot_time FROM time_slots
               WHERE barber_id = :barber_id
                AND slot_date = :slot_date
                AND status = 'Available'
                AND slot_date <= (CURRENT_DATE + INTERVAL '6 day')
                AND (
                    slot_date > CURRENT_DATE
                    OR (slot_date = CURRENT_DATE AND slot_time > CURRENT_TIME)
                )
             ORDER BY slot_time ASC LIMIT 1"
        );
        $timeStmt->execute([
            ':barber_id' => $best['barber_id'],
            ':slot_date' => $best['slot_date'],
        ]);
        $timeRow = $timeStmt->fetch();
        if (!$timeRow) {
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
                'slotTime' => $timeRow['slot_time'],
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
                $windowEndDate = (new DateTimeImmutable('today'))->modify('+6 day')->format('Y-m-d');

        $stmt = $pdo->prepare(
            "SELECT slot_date, COUNT(*) AS available_count
             FROM time_slots
             WHERE barber_id = :barber_id
               AND status = 'Available'
               AND slot_date >= :start_date
               AND slot_date < :end_date
                             AND slot_date <= :window_end_date
               AND (
                    slot_date > CURRENT_DATE
                    OR (slot_date = CURRENT_DATE AND slot_time > CURRENT_TIME)
               )
             GROUP BY slot_date"
        );
        $stmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
            ':window_end_date' => $windowEndDate,
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
        $requestedDate = DateTimeImmutable::createFromFormat('Y-m-d', $slotDate);
        $today = new DateTimeImmutable('today');
        $windowEndDate = $today->modify('+6 day');

        if ($requestedDate !== false && $requestedDate >= $today && $requestedDate <= $windowEndDate) {
            seed_slots_for_barber_dates($pdo, $barberID, [$slotDate]);

            $stmt->execute([
                ':barber_id' => $barberID,
                ':slot_date' => $slotDate,
            ]);
            $rows = $stmt->fetchAll();
        }
    }

    json_response(['slots' => $rows]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
