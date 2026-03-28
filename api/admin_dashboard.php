<?php
// Admin dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $totalUsers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
        $activeServices = (int)$pdo->query('SELECT COUNT(*) FROM services WHERE is_active = 1')->fetchColumn();
    $pendingAppointments = (int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE status = 'Scheduled'")->fetchColumn();
    $walkinsToday = (int)$pdo->query('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE')->fetchColumn();

    $monthlyRevenueStmt = $pdo->prepare(
                "SELECT COALESCE(SUM(total_amount), 0)
         FROM payments
                 WHERE payment_status = 'Paid'
                   AND created_at >= date_trunc('month', CURRENT_DATE)
                   AND created_at < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'"
    );
    $monthlyRevenueStmt->execute();
    $monthlyRevenue = (float)$monthlyRevenueStmt->fetchColumn();

    $recentAppointmentsStmt = $pdo->prepare(
           "SELECT a.appointment_id, u.full_name, a.created_at
            FROM appointments a
            JOIN users u ON a.user_id = u.user_id
            ORDER BY a.created_at DESC
         LIMIT 5"
    );
    $recentAppointmentsStmt->execute();
    $recentAppointments = $recentAppointmentsStmt->fetchAll();

    $recentWalkinsStmt = $pdo->prepare(
        "SELECT queue_number, created_at
         FROM walkin_queue
         ORDER BY created_at DESC
         LIMIT 5"
    );
    $recentWalkinsStmt->execute();
    $recentWalkins = $recentWalkinsStmt->fetchAll();

    $activities = array_merge(
        array_map(function ($row) {
            return [
                'icon' => '📅',
                'title' => 'New appointment created',
                'description' => $row['full_name'] . ' booked an appointment',
                'time' => $row['created_at'],
            ];
        }, $recentAppointments),
        array_map(function ($row) {
            return [
                'icon' => '🧾',
                'title' => 'New walk-in queued',
                'description' => 'Walk-in ' . $row['queue_number'] . ' added to queue',
                'time' => $row['created_at'],
            ];
        }, $recentWalkins)
    );

    $response = [
        'stats' => [
            ['title' => 'Total Users', 'value' => (string)$totalUsers, 'change' => '', 'changeType' => 'success'],
            ['title' => 'Active Services', 'value' => (string)$activeServices, 'change' => '', 'changeType' => 'success'],
            ['title' => 'Monthly Revenue', 'value' => '₱' . number_format($monthlyRevenue, 2), 'change' => '', 'changeType' => 'success'],
            ['title' => 'Pending Appointments', 'value' => (string)$pendingAppointments, 'change' => '', 'changeType' => 'warning'],
            ['title' => 'Walk-ins Today', 'value' => (string)$walkinsToday, 'change' => '', 'changeType' => 'info'],
        ],
        'activities' => $activities,
    ];

    json_response($response);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
