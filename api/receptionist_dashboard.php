<?php
// Receptionist dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $walkInsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM walkIns WHERE visitDate = CURRENT_DATE()');
    $walkInsTodayStmt->execute();
    $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

    $appointmentsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointmentDate = CURRENT_DATE()');
    $appointmentsTodayStmt->execute();
    $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

    $inProgressStmt = $pdo->prepare("SELECT COUNT(*) FROM walkIns WHERE status = 'InService'");
    $inProgressStmt->execute();
    $inProgress = (int)$inProgressStmt->fetchColumn();

    $activeBarbersStmt = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE is_active = TRUE');
    $activeBarbersStmt->execute();
    $activeBarbers = (int)$activeBarbersStmt->fetchColumn();

    $appointmentsStmt = $pdo->prepare(
        'SELECT a.appointmentID, u.fullName AS name,
                GROUP_CONCAT(s.serviceName SEPARATOR ", ") AS service,
                a.appointmentTime AS time,
                SUM(s.durationMinutes) AS duration,
                SUM(s.price) AS price,
                a.status,
                bu.fullName AS barber
         FROM appointments a
         JOIN users u ON a.userID = u.userID
         JOIN barbers b ON a.barberID = b.barberID
         JOIN users bu ON b.userID = bu.userID
         JOIN appointmentServices aps ON a.appointmentID = aps.appointmentID
         JOIN services s ON aps.serviceID = s.serviceID
         WHERE a.appointmentDate = CURRENT_DATE()
         GROUP BY a.appointmentID, u.fullName, a.appointmentTime, a.status, bu.fullName
         ORDER BY a.appointmentTime ASC'
    );
    $appointmentsStmt->execute();
    $appointments = $appointmentsStmt->fetchAll();

    $walkinsStmt = $pdo->prepare(
        'SELECT w.walkInID,
                COALESCE(w.customerName, "Walk-in") AS name,
                w.status
         FROM walkIns w
         WHERE w.visitDate = CURRENT_DATE()
         ORDER BY w.walkInID ASC'
    );
    $walkinsStmt->execute();
    $walkins = array_map(function ($row) {
        return [
            'name' => $row['name'],
            'service' => 'Walk-in',
            'waitTime' => '',
            'status' => $row['status'],
        ];
    }, $walkinsStmt->fetchAll());

    $barbersStmt = $pdo->prepare(
        'SELECT barber_id, full_name, specialty, rating, years_experience
         FROM barbers
         WHERE is_active = TRUE
         ORDER BY full_name'
    );
    $barbersStmt->execute();
    $barbers = array_map(function ($row) {
        return [
            'name' => $row['fullName'],
            'specialty' => 'N/A',
            'rating' => null,
            'experience' => 'N/A',
        ];
    }, $barbersStmt->fetchAll());

    $response = [
        'stats' => [
            ['title' => 'Walk-ins', 'value' => (string)$walkInsToday, 'change' => '', 'changeType' => 'info'],
            ['title' => 'Appointments', 'value' => (string)$appointmentsToday, 'change' => '', 'changeType' => 'success'],
            ['title' => 'In Progress', 'value' => (string)$inProgress, 'change' => '', 'changeType' => 'warning'],
            ['title' => 'Available Barbers', 'value' => (string)$activeBarbers, 'change' => '', 'changeType' => 'success'],
        ],
        'appointments' => array_map(function ($row) {
            return [
                'name' => $row['name'],
                'service' => $row['service'],
                'time' => $row['time'],
                'duration' => $row['duration'],
                'price' => $row['price'],
                'status' => $row['status'],
                'barber' => $row['barber'],
            ];
        }, $appointments),
        'walkins' => $walkins,
        'tracking' => [],
        'barbers' => $barbers,
    ];

    json_response($response);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
