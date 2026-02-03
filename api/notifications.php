<?php
// Notifications API (derived from appointments)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$userID = (int)($input['userID'] ?? 0);
if ($userID <= 0) {
    json_response(['error' => 'Invalid userID'], 422);
}

try {
    $pdo = get_db_connection();

    $stmt = $pdo->prepare(
        'SELECT appointment_date, start_time, status, updated_at, created_at
         FROM appointments
         WHERE user_id = :user_id
         ORDER BY updated_at DESC, created_at DESC
         LIMIT 10'
    );
    $stmt->execute([':user_id' => $userID]);
    $rows = $stmt->fetchAll();

    $notifications = array_map(function ($row) {
        $status = $row['status'] ?? 'Scheduled';
        $date = $row['appointment_date'] ?? '';
        $time = $row['start_time'] ?? '';

        if ($status === 'Completed') {
            $title = 'Appointment completed';
        } elseif ($status === 'Cancelled') {
            $title = 'Appointment cancelled';
        } else {
            $title = 'Appointment booked';
        }

        $subtitle = trim($date . ' ' . $time);
        return [
            'title' => $title,
            'subtitle' => $subtitle,
        ];
    }, $rows);

    json_response(['notifications' => $notifications]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}