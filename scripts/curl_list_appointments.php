<?php
$base = $argv[1] ?? 'http://localhost/barberyanitatis/tatis_barbershop/api/booking.php';
$userId = (int)($argv[2] ?? 1);
$body = json_encode(['action' => 'listByCustomer', 'userID' => $userId]);
$ch = curl_init($base);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS => $body,
    CURLOPT_RETURNTRANSFER => true,
]);
$out = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
echo "HTTP $code\n$out\n";
