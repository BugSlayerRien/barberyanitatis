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
        $barberID = (int)($input['barberID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $appointmentTime = trim((string)($input['appointmentTime'] ?? ''));
        $serviceIDs = $input['serviceIDs'] ?? [];

        if ($userID <= 0 || $barberID <= 0 || $appointmentDate === '' || $appointmentTime === '' || !is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        $pdo->beginTransaction();

        $stmt = $pdo->prepare('INSERT INTO appointments (userID, barberID, appointmentDate, appointmentTime) VALUES (:userID, :barberID, :appointmentDate, :appointmentTime)');
        $stmt->execute([
            ':userID' => $userID,
            ':barberID' => $barberID,
            ':appointmentDate' => $appointmentDate,
            ':appointmentTime' => $appointmentTime,
        ]);

        $appointmentID = (int)$pdo->lastInsertId();

        $linkStmt = $pdo->prepare('INSERT INTO appointmentServices (appointmentID, serviceID) VALUES (:appointmentID, :serviceID)');
        foreach ($serviceIDs as $serviceID) {
            $serviceID = (int)$serviceID;
            if ($serviceID <= 0) {
                continue;
            }
            $linkStmt->execute([
                ':appointmentID' => $appointmentID,
                ':serviceID' => $serviceID,
            ]);
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
            'SELECT a.appointmentID, a.appointmentDate, a.appointmentTime, a.status,
                b.barberID, bu.fullName AS barberName
             FROM appointments a
             JOIN barbers b ON a.barberID = b.barberID
             JOIN users bu ON b.userID = bu.userID
             WHERE a.userID = :userID
             ORDER BY a.appointmentDate DESC, a.appointmentTime DESC'
        );
        $stmt->execute([':userID' => $userID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            json_response(['appointments' => []]);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointmentID'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $serviceStmt = $pdo->prepare(
            "SELECT aps.appointmentID, s.serviceID, s.serviceName, s.durationMinutes, s.price
             FROM appointmentServices aps
             JOIN services s ON aps.serviceID = s.serviceID
             WHERE aps.appointmentID IN ($inClause)"
        );
        $serviceStmt->execute($appointmentIds);
        $serviceRows = $serviceStmt->fetchAll();

        $serviceMap = [];
        foreach ($serviceRows as $row) {
            $aid = (int)$row['appointmentID'];
            if (!isset($serviceMap[$aid])) {
                $serviceMap[$aid] = [];
            }
            $serviceMap[$aid][] = [
                'serviceID' => (int)$row['serviceID'],
                'serviceName' => $row['serviceName'],
                'durationMinutes' => (int)$row['durationMinutes'],
                'price' => (string)$row['price'],
            ];
        }

        $appointments = array_map(function ($row) use ($serviceMap) {
            $aid = (int)$row['appointmentID'];
            $row['services'] = $serviceMap[$aid] ?? [];
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
