<?php
// Admin dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

try {
    $pdo = get_db_connection();

    $totalUsers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
    $activeServices = (int)$pdo->query('SELECT COUNT(*) FROM services WHERE is_active = TRUE')->fetchColumn();
    $pendingAppointments = (int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE status = 'Scheduled'")->fetchColumn();

    $monthlyRevenueStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(amount), 0)
         FROM payments
         WHERE status = 'Paid'
           AND YEAR(createdAt) = YEAR(CURRENT_DATE())
           AND MONTH(createdAt) = MONTH(CURRENT_DATE())"
    );
    $monthlyRevenueStmt->execute();
    $monthlyRevenue = (float)$monthlyRevenueStmt->fetchColumn();

    $recentAppointmentsStmt = $pdo->prepare(
        "SELECT a.appointmentID, u.fullName, a.createdAt
         FROM appointments a
         JOIN users u ON a.userID = u.userID
         ORDER BY a.createdAt DESC
         LIMIT 5"
    );
    $recentAppointmentsStmt->execute();
    $recentAppointments = $recentAppointmentsStmt->fetchAll();

    $activities = array_map(function ($row) {
        return [
            'icon' => '📅',
            'title' => 'New appointment created',
            'description' => $row['fullName'] . ' booked an appointment',
            'time' => $row['createdAt'],
        ];
    }, $recentAppointments);

    $response = [
        'stats' => [
            ['title' => 'Total Users', 'value' => (string)$totalUsers, 'change' => '', 'changeType' => 'success'],
            ['title' => 'Active Services', 'value' => (string)$activeServices, 'change' => '', 'changeType' => 'success'],
            ['title' => 'Monthly Revenue', 'value' => '₱' . number_format($monthlyRevenue, 2), 'change' => '', 'changeType' => 'success'],
            ['title' => 'Pending Appointments', 'value' => (string)$pendingAppointments, 'change' => '', 'changeType' => 'warning'],
        ],
        'activities' => $activities,
    ];

    json_response($response);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
