<?php
// Admin dashboard API (placeholder data)

declare(strict_types=1);
header('Content-Type: application/json');

// TODO: Replace with real queries using get_db_connection() from db.php.
// Example: $pdo = get_db_connection();
// $usersCount = $pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();

$response = [
    'stats' => [
        ['title' => 'Total Users', 'value' => '1,247', 'change' => '+12% from last month', 'changeType' => 'success'],
        ['title' => 'Active Services', 'value' => '12', 'change' => '2 new this week', 'changeType' => 'success'],
        ['title' => 'Monthly Revenue', 'value' => '₱45,680', 'change' => '+8% from last month', 'changeType' => 'success'],
        ['title' => 'Pending Appointments', 'value' => '23', 'change' => 'Requires attention', 'changeType' => 'warning'],
    ],
    'activities' => [
        [
            'icon' => '👤',
            'title' => 'New user registration',
            'description' => 'Jessica Martinez registered 5 minutes ago',
            'time' => 'JUST NOW',
        ],
        [
            'icon' => '₱',
            'title' => 'Payment received',
            'description' => '₱750 payment for luxury treatment',
            'time' => '15 min ago',
        ],
        [
            'icon' => '📅',
            'title' => 'Service booking',
            'description' => 'Color transformation booked for tomorrow',
            'time' => '1 hour ago',
        ],
    ],
];

echo json_encode($response);
