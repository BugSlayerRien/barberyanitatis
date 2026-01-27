<?php
// Receptionist dashboard API (placeholder data)

declare(strict_types=1);
header('Content-Type: application/json');

$response = [
    'stats' => [
        ['title' => 'Walk-ins', 'value' => '0', 'change' => 'No walk-ins yet', 'changeType' => 'info'],
        ['title' => 'Appointments', 'value' => '3', 'change' => '3 scheduled today', 'changeType' => 'success'],
        ['title' => 'In Progress', 'value' => '1', 'change' => 'Active services', 'changeType' => 'warning'],
        ['title' => 'Available Barbers', 'value' => '2', 'change' => 'On shift', 'changeType' => 'success'],
    ],
    'appointments' => [
        [
            'name' => 'Jessica Davis',
            'service' => 'Precision Cut & Style',
            'time' => '10:00 AM',
            'duration' => '90 min',
            'price' => '₱100',
            'status' => 'CONFIRMED',
            'barber' => 'Mike Chen',
        ],
        [
            'name' => 'Maria Rodriguez',
            'service' => 'Color Transformation',
            'time' => '2:00 PM',
            'duration' => '180 min',
            'price' => '₱150',
            'status' => 'PENDING',
            'barber' => 'Sarah Johnson',
        ],
        [
            'name' => 'Sarah Johnson',
            'service' => 'Luxury Treatment',
            'time' => '5:00 PM',
            'duration' => '120 min',
            'price' => '₱200',
            'status' => 'CONFIRMED',
            'barber' => 'Emma Rodriguez',
        ],
    ],
    'walkins' => [],
    'tracking' => [
        [
            'name' => 'Alex Brown',
            'service' => 'Haircut & Styling',
            'status' => 'IN PROGRESS',
            'progress' => 0.65,
            'timeRemaining' => '15 min remaining',
            'color' => '#4caf50',
        ],
        [
            'name' => 'Jessica White',
            'service' => 'Color Treatment',
            'status' => 'WAITING',
            'progress' => 0,
            'timeRemaining' => 'Waiting',
            'color' => '#2196f3',
        ],
        [
            'name' => 'Michael Johnson',
            'service' => 'Beard Trim',
            'status' => 'COMPLETED',
            'progress' => 1,
            'timeRemaining' => 'Completed',
            'color' => '#9e9e9e',
        ],
    ],
    'barbers' => [
        ['name' => 'Mike Chen', 'specialty' => 'Precision Cuts', 'rating' => 4.9, 'experience' => '8 years'],
        ['name' => 'Sarah Johnson', 'specialty' => 'Color Expert', 'rating' => 4.8, 'experience' => '6 years'],
        ['name' => 'Emma Rodriguez', 'specialty' => 'Styling Specialist', 'rating' => 4.7, 'experience' => '5 years'],
    ],
];

echo json_encode($response);
