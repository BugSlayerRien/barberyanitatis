<?php
// Receptionist dashboard API (GET, PostgreSQL)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';

require_method('GET');

try {
    $pdo = get_db_connection();
    ensure_walkin_guest_name_column($pdo);
    auto_complete_due_appointments($pdo);

    $deskStats = fetch_receptionist_front_desk_stats($pdo);
    $walkInsToday = $deskStats['walkInsToday'];
    $appointmentsToday = $deskStats['appointmentsToday'];
    $inProgress = $deskStats['inProgress'];
    $activeBarbers = $deskStats['availableBarbers'];
    $todayRevenue = $deskStats['todayRevenue'];

    $appointmentsStmt = $pdo->prepare(
        'SELECT a.appointment_id, u.full_name AS name,
                string_agg(s.service_name, \' , \') AS service,
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
         GROUP BY a.appointment_id, u.full_name, a.start_time, a.status, b.full_name
         ORDER BY a.start_time ASC'
    );
    $appointmentsStmt->execute();
    $appointments = $appointmentsStmt->fetchAll();

    $walkinsStmt = $pdo->prepare(
        'SELECT wq.queue_id,
                wq.queue_number,
                COALESCE(NULLIF(TRIM(wq.guest_name), \'\'), \'Walk-in #\' || RIGHT(wq.queue_number, 3)) AS name,
                COALESCE(string_agg(s.service_name, \' , \' ORDER BY s.service_name), \'Walk-in\') AS service,
                wq.wait_time_minutes,
                wq.status,
                b.full_name AS barber
         FROM walkin_queue wq
         JOIN walkin_service_details wsd ON wq.queue_id = wsd.queue_id
         JOIN services s ON wsd.service_id = s.service_id
         LEFT JOIN barbers b ON wq.barber_id = b.barber_id
         WHERE DATE(wq.created_at) = CURRENT_DATE
         GROUP BY wq.queue_id, wq.queue_number, wq.guest_name, wq.wait_time_minutes, wq.status, b.full_name
         ORDER BY wq.queue_id ASC'
    );
    $walkinsStmt->execute();
    $walkins = array_map(function (array $row): array {
        return [
            'name' => $row['name'] ?? 'Walk-in',
            'service' => $row['service'] ?? 'Walk-in',
            'waitTime' => isset($row['wait_time_minutes']) && $row['wait_time_minutes'] !== null ? $row['wait_time_minutes'] . ' min' : '',
            'status' => $row['status'] ?? 'Waiting',
        ];
    }, $walkinsStmt->fetchAll());

    $barbersStmt = $pdo->prepare(
        'SELECT full_name, specialty, rating, years_experience
         FROM barbers
         WHERE is_active = TRUE
         ORDER BY full_name'
    );
    $barbersStmt->execute();
    $barbers = array_map(function (array $row): array {
        return [
            'name' => $row['full_name'] ?? 'Barber',
            'specialty' => $row['specialty'] ?? 'N/A',
            'rating' => $row['rating'] ?? null,
            'experience' => isset($row['years_experience']) && $row['years_experience'] !== null ? $row['years_experience'] . ' yrs' : 'N/A',
        ];
    }, $barbersStmt->fetchAll());

    json_response([
        'stats' => [
            ['title' => 'Walk-ins', 'value' => (string)$walkInsToday, 'change' => '', 'changeType' => 'info'],
            ['title' => 'Appointments', 'value' => (string)$appointmentsToday, 'change' => '', 'changeType' => 'success'],
            ['title' => "Today's revenue", 'value' => 'PHP ' . number_format($todayRevenue, 2, '.', ''), 'change' => '', 'changeType' => 'gold'],
            ['title' => 'In Progress', 'value' => (string)$inProgress, 'change' => '', 'changeType' => 'warning'],
            ['title' => 'Available Barbers', 'value' => (string)$activeBarbers, 'change' => '', 'changeType' => 'success'],
        ],
        'todayRevenue' => $todayRevenue,
        'appointments' => array_map(function (array $row): array {
            return [
                'name' => $row['name'] ?? 'Customer',
                'service' => $row['service'] ?? 'Service',
                'time' => $row['time'] ?? '',
                'duration' => $row['duration'] ?? 0,
                'price' => $row['price'] ?? 0,
                'status' => $row['status'] ?? 'Scheduled',
                'barber' => $row['barber'] ?? '',
            ];
        }, $appointments),
        'walkins' => $walkins,
        'tracking' => [],
        'barbers' => $barbers,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
