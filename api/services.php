<?php
// Services API (list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/service_channel.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'list';

if ($action !== 'list') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();
    schema_ensure_once('services.channel', static function () use ($pdo): void {
        ensure_service_channel_column($pdo);
    });

    $channel = normalize_service_channel($input['channel'] ?? $input['serviceChannel'] ?? null);
    $channelFilter = $channel !== null ? service_channel_filter_sql($channel) : '';

    $stmt = $pdo->prepare(
        "SELECT service_id, service_name, description, base_duration, base_price, category, service_channel
         FROM services
         WHERE is_active = TRUE{$channelFilter}
         ORDER BY service_name"
    );
    $stmt->execute();

    json_response(['services' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
