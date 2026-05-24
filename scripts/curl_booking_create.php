<?php
declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/shop_schedule.php';

$pdo = get_db_connection();
$userId = (int)$pdo->query('SELECT user_id FROM users WHERE is_active = TRUE ORDER BY user_id LIMIT 1')->fetchColumn();
$barberId = (int)$pdo->query(
    "SELECT barber_id FROM barbers WHERE is_active = TRUE AND barber_channel = 'appointment' LIMIT 1"
)->fetchColumn();
$variantId = (int)($argv[1] ?? $pdo->query(
    'SELECT hv.variant_id FROM hairstyle_variants hv
     JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
     WHERE hs.is_active = TRUE ORDER BY hv.variant_id LIMIT 1'
)->fetchColumn());
$serviceId = (int)$pdo->query(
    "SELECT service_id FROM services WHERE category = 'Haircut' AND is_active = TRUE LIMIT 1"
)->fetchColumn();
$sessionId = (string)($pdo->query('SELECT scan_session_id FROM face_scan_sessions ORDER BY created_at DESC LIMIT 1')->fetchColumn() ?: '');

$tomorrow = shop_now()->modify('+2 days')->format('Y-m-d');
$payload = [
    'action' => 'create',
    'userID' => $userId,
    'barberID' => $barberId,
    'appointmentDate' => $tomorrow,
    'startTime' => '14:00:00',
    'endTime' => '15:00:00',
    'serviceIDs' => [$serviceId],
    'variantID' => $variantId,
    'scanSessionId' => $sessionId,
];

$url = 'http://localhost/barberyanitatis/tatis_barbershop/api/booking.php';
$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_POSTFIELDS => json_encode($payload),
    CURLOPT_RETURNTRANSFER => true,
]);
$body = curl_exec($ch);
$code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "HTTP $code\n$body\n";
