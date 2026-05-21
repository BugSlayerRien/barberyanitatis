<?php
require_once dirname(__DIR__) . '/api/db.php';

$userId = (int)($argv[1] ?? 1);
$ch = curl_init('http://localhost/barberyanitatis/tatis_barbershop/api/booking.php');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode(['action' => 'listByCustomer', 'userID' => $userId]),
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_RETURNTRANSFER => true,
]);
$body = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
echo "HTTP $code\n$body\n";
