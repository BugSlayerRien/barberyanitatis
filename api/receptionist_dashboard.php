<?php
// Receptionist dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $walkInsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM walkIns WHERE DATE(createdAt) = CURRENT_DATE()');
    $walkInsTodayStmt->execute();
    $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

    $appointmentsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointmentDate = CURRENT_DATE()');
    $appointmentsTodayStmt->execute();
    $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

    $inProgressStmt = $pdo->prepare("SELECT COUNT(*) FROM appointmentQueue WHERE status = 'InProgress'");
    $inProgressStmt->execute();
    $inProgress = (int)$inProgressStmt->fetchColumn();

    $activeBarbersStmt = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE isActive = 1');
    $activeBarbersStmt->execute();
    $activeBarbers = (int)$activeBarbersStmt->fetchColumn();

    $appointmentsStmt = $pdo->prepare(
        'SELECT a.appointmentID, u.fullName AS name, s.serviceName AS service, a.startTime AS time,
                s.durationMinutes AS duration, s.price, a.status
         FROM appointments a
         JOIN users u ON a.userID = u.userID
         JOIN services s ON a.serviceID = s.serviceID
         WHERE a.appointmentDate = CURRENT_DATE()
         ORDER BY a.startTime ASC'
    );
    $appointmentsStmt->execute();
    $appointments = $appointmentsStmt->fetchAll();

    $walkinsStmt = $pdo->prepare(
        'SELECT w.walkInID, s.serviceName AS service, w.participantCount, w.createdAt
         FROM walkIns w
         JOIN services s ON w.serviceID = s.serviceID
         WHERE DATE(w.createdAt) = CURRENT_DATE()
         ORDER BY w.createdAt ASC'
    );
    $walkinsStmt->execute();
    $walkins = $walkinsStmt->fetchAll();

    $barbersStmt = $pdo->prepare('SELECT barberID, fullName FROM barbers WHERE isActive = 1 ORDER BY fullName');
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
