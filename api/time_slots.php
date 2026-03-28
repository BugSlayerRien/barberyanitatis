<?php
// Time slots API (listByBarberDate)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['listByBarberDate', 'suggestBestSlot'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'suggestBestSlot') {
        $bestStmt = $pdo->prepare(
            "SELECT barber_id, slot_date, COUNT(*) AS available_count
             FROM time_slots
               WHERE status = 'Available' AND slot_date >= CURRENT_DATE
             GROUP BY barber_id, slot_date
             ORDER BY available_count DESC, slot_date ASC
             LIMIT 1"
        );
        $bestStmt->execute();
        $best = $bestStmt->fetch();
        if (!$best) {
            $barberStmt = $pdo->prepare('SELECT barber_id, full_name, specialty FROM barbers WHERE is_active = 1 ORDER BY barber_id ASC LIMIT 1');
            $barberStmt->execute();
            $barber = $barberStmt->fetch();
            if (!$barber) {
                json_response(['error' => 'No available slots found'], 404);
            }

            $now = new DateTimeImmutable('now');
            $startHour = 9;
            $endHour = 18;
            $hour = (int)$now->format('G');

            if ($hour < $startHour) {
                $slotDate = $now->format('Y-m-d');
                $slotTime = sprintf('%02d:00:00', $startHour);
            } elseif ($hour >= $endHour) {
                $slotDate = $now->modify('+1 day')->format('Y-m-d');
                $slotTime = sprintf('%02d:00:00', $startHour);
            } else {
                $slotDate = $now->format('Y-m-d');
                $slotTime = sprintf('%02d:00:00', $hour + 1);
            }

            json_response([
                'suggestion' => [
                    'barberID' => (int)$barber['barber_id'],
                    'barberName' => $barber['full_name'] ?? 'Barber',
                    'specialty' => $barber['specialty'] ?? null,
                    'slotDate' => $slotDate,
                    'slotTime' => $slotTime,
                    'availableCount' => 0,
                    'isFallback' => true,
                ],
            ]);
        }

        $timeStmt = $pdo->prepare(
            "SELECT slot_time FROM time_slots
             WHERE barber_id = :barber_id AND slot_date = :slot_date AND status = 'Available'
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

    $barberID = (int)($input['barberID'] ?? 0);
    $slotDate = trim((string)($input['slotDate'] ?? ''));

    if ($barberID <= 0 || $slotDate === '') {
        json_response(['error' => 'Missing barberID or slotDate'], 422);
    }

    $stmt = $pdo->prepare(
        'SELECT slot_id, slot_time, status
         FROM time_slots
         WHERE barber_id = :barber_id AND slot_date = :slot_date
         ORDER BY slot_time'
    );
    $stmt->execute([
        ':barber_id' => $barberID,
        ':slot_date' => $slotDate,
    ]);

    json_response(['slots' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
