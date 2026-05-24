<?php
$url = 'http://localhost/barberyanitatis/tatis_barbershop/api/face_scan.php';
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS => json_encode(['action' => 'ping']),
    CURLOPT_RETURNTRANSFER => true,
]);
$body = curl_exec($ch);
$code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo "HTTP $code\n" . substr((string)$body, 0, 500) . "\n";
