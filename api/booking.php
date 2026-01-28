<?php
// Booking API (create + list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if ($action !== 'create' && $action !== 'listByCustomer') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'create') {
        $userID = (int)($input['userID'] ?? 0);
        $serviceID = (int)($input['serviceID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $startTime = trim((string)($input['startTime'] ?? ''));
        $endTime = trim((string)($input['endTime'] ?? ''));
        $barberIDs = $input['barberIDs'] ?? [];
        $participants = $input['participants'] ?? [];

        if ($userID <= 0 || $serviceID <= 0 || $appointmentDate === '' || $startTime === '' || $endTime === '') {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        $pdo->beginTransaction();

        $stmt = $pdo->prepare(
            'INSERT INTO appointments (userID, serviceID, appointmentDate, startTime, endTime)
             VALUES (:userID, :serviceID, :appointmentDate, :startTime, :endTime)'
        );
        $stmt->execute([
            ':userID' => $userID,
            ':serviceID' => $serviceID,
            ':appointmentDate' => $appointmentDate,
            ':startTime' => $startTime,
            ':endTime' => $endTime,
        ]);

        $appointmentID = (int)$pdo->lastInsertId();

        if (is_array($barberIDs) && count($barberIDs) > 0) {
            $linkBarber = $pdo->prepare('INSERT INTO appointmentBarbers (appointmentID, barberID) VALUES (:appointmentID, :barberID)');
            foreach ($barberIDs as $barberID) {
                $barberID = (int)$barberID;
                if ($barberID <= 0) {
                    continue;
                }
                $linkBarber->execute([
                    ':appointmentID' => $appointmentID,
                    ':barberID' => $barberID,
                ]);
            }
        }

        if (is_array($participants) && count($participants) > 0) {
            $linkParticipant = $pdo->prepare(
                'INSERT INTO appointmentParticipants (appointmentID, participantType)
                 VALUES (:appointmentID, :participantType)'
            );
            foreach ($participants as $participantType) {
                $participantType = (string)$participantType;
                if ($participantType !== 'Adult' && $participantType !== 'Child') {
                    continue;
                }
                $linkParticipant->execute([
                    ':appointmentID' => $appointmentID,
                    ':participantType' => $participantType,
                ]);
            }
        }

        $pdo->commit();

        json_response([
            'message' => 'Appointment created',
            'appointmentID' => $appointmentID,
        ], 201);
    }

    if ($action === 'listByCustomer') {
        $userID = (int)($input['userID'] ?? 0);
        if ($userID <= 0) {
            json_response(['error' => 'Invalid userID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT a.appointmentID, a.appointmentDate, a.startTime, a.endTime, a.status,
                    s.serviceID, s.serviceName, s.durationMinutes, s.price
             FROM appointments a
             JOIN services s ON a.serviceID = s.serviceID
             WHERE a.userID = :userID
             ORDER BY a.appointmentDate DESC, a.startTime DESC'
        );
        $stmt->execute([':userID' => $userID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            json_response(['appointments' => []]);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointmentID'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $barberStmt = $pdo->prepare(
            "SELECT ab.appointmentID, b.barberID, b.fullName
             FROM appointmentBarbers ab
             JOIN barbers b ON ab.barberID = b.barberID
             WHERE ab.appointmentID IN ($inClause)"
        );
        $barberStmt->execute($appointmentIds);
        $barberRows = $barberStmt->fetchAll();

        $barberMap = [];
        foreach ($barberRows as $row) {
            $aid = (int)$row['appointmentID'];
            if (!isset($barberMap[$aid])) {
                $barberMap[$aid] = [];
            }
            $barberMap[$aid][] = [
                'barberID' => (int)$row['barberID'],
                'fullName' => $row['fullName'],
            ];
        }

        $appointments = array_map(function ($row) use ($barberMap) {
            $aid = (int)$row['appointmentID'];
            $row['barbers'] = $barberMap[$aid] ?? [];
            return $row;
        }, $appointments);

        json_response(['appointments' => $appointments]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
