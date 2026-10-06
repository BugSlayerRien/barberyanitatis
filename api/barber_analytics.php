<?php
// Barber analytics endpoint: one POST, one payload, every chart on the barber
// app's Insights tab. The barber can only ever read their own numbers -- the
// id is resolved from the signed-in email first.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/barber_analytics_lib.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? 'summary'));

if ($action !== 'summary') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    with_pdo_retry(function (PDO $pdo) use ($input): void {
        $barberId = (int)($input['barberID'] ?? $input['barberId'] ?? $input['userID'] ?? 0);
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $days = (int)($input['days'] ?? 30);

        $barber = analytics_resolve_barber($pdo, $barberId, $email);
        if ($barber['id'] <= 0) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $payload = barber_analytics_payload($pdo, $barber['id'], $days);
        $payload['barber'] = ['id' => $barber['id'], 'name' => $barber['name']];

        json_response($payload);
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 503);
}
