<?php
// Receptionist actions API (dashboard + updates)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'dashboard';

$allowedActions = ['dashboard', 'updateAppointmentStatus', 'updateWalkinStatus', 'createWalkin'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'dashboard') {
        $walkInsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE');
        $walkInsTodayStmt->execute();
        $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

        $appointmentsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointment_date = CURRENT_DATE');
        $appointmentsTodayStmt->execute();
        $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

        $inProgressStmt = $pdo->prepare("SELECT COUNT(*) FROM walkin_queue WHERE status = 'InProgress'");
        $inProgressStmt->execute();
        $inProgress = (int)$inProgressStmt->fetchColumn();

        $activeBarbersStmt = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE is_active = 1');
        $activeBarbersStmt->execute();
        $activeBarbers = (int)$activeBarbersStmt->fetchColumn();

        $appointmentsStmt = $pdo->prepare(
            'SELECT a.appointment_id, a.barber_id, u.full_name AS name,
                    string_agg(s.service_name, \', \' ORDER BY s.service_name) AS service,
                    a.start_time AS time,
                    SUM(s.base_duration) AS duration,
                    SUM(ad.final_price) AS price,
                    a.status,
                    b.full_name AS barber
             FROM appointments a
             JOIN users u ON a.user_id = u.user_id
             JOIN barbers b ON a.barber_id = b.barber_id
             JOIN appointment_details ad ON a.appointment_id = ad.appointment_id
             JOIN services s ON ad.service_id = s.service_id
             WHERE a.appointment_date = CURRENT_DATE
             GROUP BY a.appointment_id, a.barber_id, u.full_name, a.start_time, a.status, b.full_name
             ORDER BY a.start_time ASC'
        );
        $appointmentsStmt->execute();
        $appointments = $appointmentsStmt->fetchAll();

        $walkinsStmt = $pdo->prepare(
            'SELECT wq.queue_id, wq.queue_number, wq.barber_id,
                    CONCAT(\'Walk-in #\', RIGHT(wq.queue_number, 3)) AS name,
                    string_agg(s.service_name, \', \' ORDER BY s.service_name) AS service,
                    wq.wait_time_minutes,
                    wq.status,
                    b.full_name AS barber
             FROM walkin_queue wq
             JOIN walkin_service_details wsd ON wq.queue_id = wsd.queue_id
             JOIN services s ON wsd.service_id = s.service_id
             LEFT JOIN barbers b ON wq.barber_id = b.barber_id
             WHERE DATE(wq.created_at) = CURRENT_DATE
             GROUP BY wq.queue_id, wq.queue_number, wq.barber_id, wq.wait_time_minutes, wq.status, b.full_name
             ORDER BY wq.queue_id ASC'
        );
        $walkinsStmt->execute();
        $walkins = $walkinsStmt->fetchAll();

        json_response([
            'stats' => [
                ['title' => 'Walk-ins', 'value' => (string)$walkInsToday, 'change' => '', 'changeType' => 'info'],
                ['title' => 'Appointments', 'value' => (string)$appointmentsToday, 'change' => '', 'changeType' => 'success'],
                ['title' => 'In Progress', 'value' => (string)$inProgress, 'change' => '', 'changeType' => 'warning'],
                ['title' => 'Available Barbers', 'value' => (string)$activeBarbers, 'change' => '', 'changeType' => 'success'],
            ],
            'appointments' => array_map(function ($row) {
                return [
                    'appointment_id' => (int)$row['appointment_id'],
                    'barber_id' => (int)$row['barber_id'],
                    'name' => $row['name'],
                    'service' => $row['service'],
                    'time' => $row['time'],
                    'duration' => $row['duration'],
                    'price' => $row['price'],
                    'status' => $row['status'],
                    'barber' => $row['barber'],
                ];
            }, $appointments),
            'walkins' => array_map(function ($row) {
                return [
                    'queue_id' => (int)$row['queue_id'],
                    'queue_number' => $row['queue_number'],
                    'barber_id' => $row['barber_id'] !== null ? (int)$row['barber_id'] : null,
                    'name' => $row['name'],
                    'service' => $row['service'] ?? 'Walk-in',
                    'waitTime' => $row['wait_time_minutes'] !== null ? $row['wait_time_minutes'] . ' min' : '',
                    'status' => $row['status'],
                    'barber' => $row['barber'],
                ];
            }, $walkins),
        ]);
    }

    if ($action === 'updateAppointmentStatus') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $status = trim((string)($input['status'] ?? ''));

        $allowed = ['Scheduled', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow'];
        if ($appointmentID <= 0 || !in_array($status, $allowed, true)) {
            json_response(['error' => 'Invalid appointmentID or status'], 422);
        }

        $checkinTime = null;
        $completionTime = null;
        if ($status === 'CheckedIn') {
            $checkinTime = date('Y-m-d H:i:s');
        }
        if ($status === 'Completed') {
            $completionTime = date('Y-m-d H:i:s');
        }

        $stmt = $pdo->prepare(
            'UPDATE appointments
             SET status = :status,
                 checkin_time = COALESCE(:checkin_time, checkin_time),
                 completion_time = COALESCE(:completion_time, completion_time)
             WHERE appointment_id = :appointment_id'
        );
        $stmt->execute([
            ':status' => $status,
            ':checkin_time' => $checkinTime,
            ':completion_time' => $completionTime,
            ':appointment_id' => $appointmentID,
        ]);

        json_response(['message' => 'Appointment updated']);
    }

    if ($action === 'updateWalkinStatus') {
        $queueID = (int)($input['queueID'] ?? 0);
        $status = trim((string)($input['status'] ?? ''));
        $barberID = (int)($input['barberID'] ?? 0);

        $allowed = ['Waiting', 'Assigned', 'InProgress', 'Completed', 'Cancelled'];
        if ($queueID <= 0 || !in_array($status, $allowed, true)) {
            json_response(['error' => 'Invalid queueID or status'], 422);
        }

        $actualStart = null;
        $actualEnd = null;
        if ($status === 'InProgress') {
            $actualStart = date('Y-m-d H:i:s');
        }
        if ($status === 'Completed' || $status === 'Cancelled') {
            $actualEnd = date('Y-m-d H:i:s');
        }

        $stmt = $pdo->prepare(
            'UPDATE walkin_queue
             SET status = :status,
                 barber_id = CASE WHEN :barber_id > 0 THEN :barber_id ELSE barber_id END,
                 actual_start = COALESCE(:actual_start, actual_start),
                 actual_end = COALESCE(:actual_end, actual_end)
             WHERE queue_id = :queue_id'
        );
        $stmt->execute([
            ':status' => $status,
            ':barber_id' => $barberID,
            ':actual_start' => $actualStart,
            ':actual_end' => $actualEnd,
            ':queue_id' => $queueID,
        ]);

        json_response(['message' => 'Walk-in updated']);
    }

    if ($action === 'createWalkin') {
        $serviceIDs = $input['serviceIDs'] ?? [];
        $barberID = (int)($input['barberID'] ?? 0);

        if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing serviceIDs'], 422);
        }

        $variantStmt = $pdo->prepare(
            'SELECT hv.variant_id
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hs.is_active = 1
             ORDER BY hv.confidence_score DESC, hv.variant_id ASC
             LIMIT 1'
        );
        $variantStmt->execute();
        $variantID = (int)$variantStmt->fetchColumn();
        if ($variantID <= 0) {
            json_response(['error' => 'No active hairstyle variants available'], 422);
        }

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE');
        $countStmt->execute();
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $queueNumber = 'W-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

        $status = $barberID > 0 ? 'Assigned' : 'Waiting';

        $insertQueue = $pdo->prepare(
            'INSERT INTO walkin_queue (queue_number, barber_id, status)
             VALUES (:queue_number, :barber_id, :status)
             RETURNING queue_id'
        );
        $insertQueue->execute([
            ':queue_number' => $queueNumber,
            ':barber_id' => $barberID > 0 ? $barberID : null,
            ':status' => $status,
        ]);

        $queueID = (int)$insertQueue->fetchColumn();

        $serviceStmt = $pdo->prepare(
            'SELECT service_id, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = 1'
        );
        $detailStmt = $pdo->prepare(
            'INSERT INTO walkin_service_details (queue_id, service_id, variant_id, selected_view, final_price)
             VALUES (:queue_id, :service_id, :variant_id, :selected_view, :final_price)'
        );

        foreach ($serviceIDs as $serviceID) {
            $serviceID = (int)$serviceID;
            if ($serviceID <= 0) {
                continue;
            }
            $serviceStmt->execute([':service_id' => $serviceID]);
            $service = $serviceStmt->fetch();
            if (!$service) {
                continue;
            }
            $detailStmt->execute([
                ':queue_id' => $queueID,
                ':service_id' => $serviceID,
                ':variant_id' => $variantID,
                ':selected_view' => 'Front',
                ':final_price' => $service['base_price'],
            ]);
        }

        $pdo->commit();

        json_response([
            'message' => 'Walk-in created',
            'queueID' => $queueID,
            'queueNumber' => $queueNumber,
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
