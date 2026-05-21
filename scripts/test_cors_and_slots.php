<?php
function test(string $url, string $method, ?string $body = null): void
{
    $ch = curl_init($url);
    $headers = ['Content-Type: application/json'];
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HEADER => true,
    ]);
    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }
    $raw = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    echo "=== $method $url HTTP $code ===\n";
    if (preg_match('/Access-Control-Allow-Origin:/i', $raw)) {
        echo "CORS: present\n";
    } else {
        echo "CORS: MISSING\n";
    }
    $parts = explode("\r\n\r\n", $raw, 2);
    echo substr($parts[1] ?? $raw, 0, 500) . "\n\n";
}

$base = 'http://localhost/barberyanitatis/tatis_barbershop/api';
test("$base/notifications.php", 'OPTIONS');
test("$base/notifications.php", 'POST', json_encode(['action' => 'unreadCount', 'userID' => 1]));
$body = json_encode([
    'action' => 'listByBarberDate',
    'barberID' => 1,
    'slotDate' => date('Y-m-d'),
]);
test("$base/time_slots.php", 'POST', $body);
test("$base/time_slots.php", 'POST', json_encode(['action' => 'suggestBestSlot']));
