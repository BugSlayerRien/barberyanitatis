<?php
// Receptionist dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $walkInsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE()');
    $walkInsTodayStmt->execute();
    $walkInsToday = (int)$walkInsTodayStmt->fetchColumn();

    $appointmentsTodayStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointment_date = CURRENT_DATE()');
    $appointmentsTodayStmt->execute();
    $appointmentsToday = (int)$appointmentsTodayStmt->fetchColumn();

    $inProgressStmt = $pdo->prepare("SELECT COUNT(*) FROM walkin_queue WHERE status = 'InProgress'");
    $inProgressStmt->execute();
    $inProgress = (int)$inProgressStmt->fetchColumn();

    $activeBarbersStmt = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE is_active = 1');
    $activeBarbersStmt->execute();
    $activeBarbers = (int)$activeBarbersStmt->fetchColumn();

    $appointmentsStmt = $pdo->prepare(
        'SELECT a.appointment_id, u.full_name AS name,
                GROUP_CONCAT(s.service_name SEPARATOR ", ") AS service,
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
         WHERE a.appointment_date = CURRENT_DATE()
         GROUP BY a.appointment_id, u.full_name, a.start_time, a.status, b.full_name
         ORDER BY a.start_time ASC'
    );
    $appointmentsStmt->execute();
    $appointments = $appointmentsStmt->fetchAll();

    $walkinsStmt = $pdo->prepare(
        'SELECT wq.queue_id,
                CONCAT("Walk-in #", RIGHT(wq.queue_number, 3)) AS name,
                GROUP_CONCAT(s.service_name SEPARATOR ", ") AS service,
                wq.wait_time_minutes,
                wq.status
         FROM walkin_queue wq
         JOIN walkin_service_details wsd ON wq.queue_id = wsd.queue_id
         JOIN services s ON wsd.service_id = s.service_id
         WHERE DATE(wq.created_at) = CURRENT_DATE()
         GROUP BY wq.queue_id, wq.queue_number, wq.wait_time_minutes, wq.status
         ORDER BY wq.queue_id ASC'
    );
    $walkinsStmt->execute();
    $walkins = array_map(function ($row) {
        return [
            'name' => $row['name'],
            'service' => $row['service'] ?? 'Walk-in',
            'waitTime' => $row['wait_time_minutes'] !== null ? $row['wait_time_minutes'] . ' min' : '',
            'status' => $row['status'],
        ];
    }, $walkinsStmt->fetchAll());

    $barbersStmt = $pdo->prepare(
        'SELECT barber_id, full_name, specialty, rating, years_experience
         FROM barbers
         WHERE is_active = 1
         ORDER BY full_name'
    );
    $barbersStmt->execute();
    $barbers = array_map(function ($row) {
        return [
            'name' => $row['full_name'],
            'specialty' => $row['specialty'] ?? 'N/A',
            'rating' => $row['rating'],
            'experience' => $row['years_experience'] !== null ? $row['years_experience'] . ' yrs' : 'N/A',
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
