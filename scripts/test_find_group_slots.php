<?php
$ch = curl_init('http://localhost/barberyanitatis/tatis_barbershop/api/time_slots.php');
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode(['action' => 'findGroupSlots', 'barberID' => 1, 'peopleCount' => 3]),
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_RETURNTRANSFER => true,
]);
$body = curl_exec($ch);
echo 'HTTP ' . curl_getinfo($ch, CURLINFO_HTTP_CODE) . "\n$body\n";
