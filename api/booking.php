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
        $customerID = (int)($input['customerID'] ?? 0);
        $barberID = (int)($input['barberID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $appointmentTime = trim((string)($input['appointmentTime'] ?? ''));
        $serviceIDs = $input['serviceIDs'] ?? [];

        if ($customerID <= 0 || $barberID <= 0 || $appointmentDate === '' || $appointmentTime === '' || !is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        $pdo->beginTransaction();

        $stmt = $pdo->prepare('INSERT INTO appointments (customerID, barberID, appointmentDate, appointmentTime) VALUES (:customerID, :barberID, :appointmentDate, :appointmentTime)');
        $stmt->execute([
            ':customerID' => $customerID,
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
        $customerID = (int)($input['customerID'] ?? 0);
        if ($customerID <= 0) {
            json_response(['error' => 'Invalid customerID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT a.appointmentID, a.appointmentDate, a.appointmentTime, a.status, b.barberID, u.fullName AS barberName
             FROM appointments a
             JOIN barbers b ON a.barberID = b.barberID
             JOIN users u ON b.userID = u.userID
             WHERE a.customerID = :customerID
             ORDER BY a.appointmentDate DESC, a.appointmentTime DESC'
        );
        $stmt->execute([':customerID' => $customerID]);
        $appointments = $stmt->fetchAll();

        json_response(['appointments' => $appointments]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
