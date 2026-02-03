<?php
// Admin audit logs API (derived activity feed)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('GET');

try {
    $pdo = get_db_connection();

    $events = [];

    $userRows = $pdo->query(
        'SELECT full_name, created_at
         FROM users
         ORDER BY created_at DESC
         LIMIT 25'
    )->fetchAll();
    foreach ($userRows as $row) {
        $events[] = [
            'time' => $row['created_at'],
            'title' => 'User created',
            'description' => $row['full_name'] . ' registered a customer account',
            'type' => 'user',
        ];
    }

    $staffRows = $pdo->query(
        'SELECT full_name, role, created_at
         FROM staff_users
         ORDER BY created_at DESC
         LIMIT 25'
    )->fetchAll();
    foreach ($staffRows as $row) {
        $events[] = [
            'time' => $row['created_at'],
            'title' => 'Staff created',
            'description' => $row['full_name'] . ' added as ' . $row['role'],
            'type' => 'staff',
        ];
    }

    $appointmentRows = $pdo->query(
        "SELECT a.booking_code, a.status, a.created_at, a.updated_at, u.full_name
         FROM appointments a
         JOIN users u ON a.user_id = u.user_id
         ORDER BY a.updated_at DESC
         LIMIT 50"
    )->fetchAll();
    foreach ($appointmentRows as $row) {
        $events[] = [
            'time' => $row['created_at'],
            'title' => 'Appointment created',
            'description' => $row['full_name'] . ' booked appointment ' . $row['booking_code'],
            'type' => 'appointment',
        ];
        if ($row['updated_at'] && $row['updated_at'] !== $row['created_at']) {
            $events[] = [
                'time' => $row['updated_at'],
                'title' => 'Appointment updated',
                'description' => $row['booking_code'] . ' changed to ' . $row['status'],
                'type' => 'appointment',
            ];
        }
    }

    $paymentRows = $pdo->query(
        "SELECT payment_ref, total_amount, payment_status, created_at
         FROM payments
         ORDER BY created_at DESC
         LIMIT 50"
    )->fetchAll();
    foreach ($paymentRows as $row) {
        $events[] = [
            'time' => $row['created_at'],
            'title' => 'Payment update',
            'description' => $row['payment_ref'] . ' ' . $row['payment_status'] . ' (₱' . number_format((float)$row['total_amount'], 2) . ')',
            'type' => 'payment',
        ];
    }

    $adminNotes = $pdo->query(
        "SELECT title, message, created_at
         FROM notifications
         WHERE recipient_type = 'Admin'
         ORDER BY created_at DESC
         LIMIT 50"
    )->fetchAll();
    foreach ($adminNotes as $row) {
        $events[] = [
            'time' => $row['created_at'],
            'title' => $row['title'],
            'description' => $row['message'],
            'type' => 'system',
        ];
    }

    usort($events, fn($a, $b) => strtotime((string)$b['time']) <=> strtotime((string)$a['time']));
    $events = array_slice($events, 0, 60);

    json_response(['events' => $events]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
