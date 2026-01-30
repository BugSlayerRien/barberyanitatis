<?php
// Receptionist dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $walkInsTodayStmt = $pdo->prepare("SELECT COUNT(*) FROM appointments WHERE appointmentType = 'WALKIN' AND appointmentDate = CURRENT_DATE()");
    $walkInsTodayStmt->execute();
    $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

    $appointmentsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointmentDate = CURRENT_DATE()');
    $appointmentsTodayStmt->execute();
    $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

    $inProgressStmt = $pdo->prepare("SELECT COUNT(*) FROM appointments WHERE status = 'IN_CONSULTATION'");
    $inProgressStmt->execute();
    $inProgress = (int)$inProgressStmt->fetchColumn();

    $activeBarbersStmt = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE isAvailable = 1');
    $activeBarbersStmt->execute();
    $activeBarbers = (int)$activeBarbersStmt->fetchColumn();

    $appointmentsStmt = $pdo->prepare(
        'SELECT a.appointmentID, u.fullName AS name,
                GROUP_CONCAT(s.serviceName SEPARATOR ", ") AS service,
                a.appointmentTime AS time,
                SUM(s.durationMinutes) AS duration,
                SUM(s.price) AS price,
                a.status
         FROM appointments a
         JOIN users u ON a.userID = u.userID
         JOIN appointmentServices aps ON a.appointmentID = aps.appointmentID
         JOIN services s ON aps.serviceID = s.serviceID
         WHERE a.appointmentDate = CURRENT_DATE() AND a.appointmentType = "APPOINTMENT"
         GROUP BY a.appointmentID, u.fullName, a.appointmentTime, a.status
         ORDER BY a.appointmentTime ASC'
    );
    $appointmentsStmt->execute();
    $appointments = $appointmentsStmt->fetchAll();

    $walkinsStmt = $pdo->prepare(
        'SELECT a.appointmentID AS walkInID,
                GROUP_CONCAT(s.serviceName SEPARATOR ", ") AS service,
                a.createdAt,
                a.status
         FROM appointments a
         JOIN appointmentServices aps ON a.appointmentID = aps.appointmentID
         JOIN services s ON aps.serviceID = s.serviceID
         WHERE a.appointmentDate = CURRENT_DATE() AND a.appointmentType = "WALKIN"
         GROUP BY a.appointmentID, a.createdAt, a.status
         ORDER BY a.createdAt ASC'
    );
    $walkinsStmt->execute();
    $walkins = $walkinsStmt->fetchAll();

    $barbersStmt = $pdo->prepare(
        'SELECT b.barberID, u.fullName
         FROM barbers b
         JOIN users u ON b.userID = u.userID
         WHERE b.isAvailable = 1
         ORDER BY u.fullName'
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
        'appointments' => $appointments,
        'walkins' => $walkins,
        'tracking' => [],
        'barbers' => $barbers,
    ];

    json_response($response);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
