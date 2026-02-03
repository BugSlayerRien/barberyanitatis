<?php
// Admin services API (list/update)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['error' => 'Method not allowed'], 405);
}

try {
    $pdo = get_db_connection();

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = get_json_input();
        $action = $input['action'] ?? 'update';
        if ($action !== 'update') {
            json_response(['error' => 'Invalid action'], 400);
        }

        $serviceID = (int)($input['serviceID'] ?? 0);
        if ($serviceID <= 0) {
            json_response(['error' => 'Invalid serviceID'], 422);
        }

        $current = $pdo->prepare('SELECT service_name, description, base_duration, base_price, category, is_active FROM services WHERE service_id = :id');
        $current->execute([':id' => $serviceID]);
        $row = $current->fetch();
        if (!$row) {
            json_response(['error' => 'Service not found'], 404);
        }

        $name = trim((string)($input['serviceName'] ?? $row['service_name']));
        $description = trim((string)($input['description'] ?? $row['description']));
        $duration = isset($input['baseDuration']) ? (int)$input['baseDuration'] : (int)$row['base_duration'];
        $price = isset($input['basePrice']) ? (float)$input['basePrice'] : (float)$row['base_price'];
        $category = trim((string)($input['category'] ?? $row['category']));
        $isActive = isset($input['isActive']) ? (int)$input['isActive'] : (int)$row['is_active'];

        $stmt = $pdo->prepare(
            'UPDATE services SET service_name = :service_name, description = :description, base_duration = :base_duration,
             base_price = :base_price, category = :category, is_active = :is_active WHERE service_id = :id'
        );
        $stmt->execute([
            ':service_name' => $name,
            ':description' => $description !== '' ? $description : null,
            ':base_duration' => $duration,
            ':base_price' => $price,
            ':category' => $category !== '' ? $category : $row['category'],
            ':is_active' => $isActive,
            ':id' => $serviceID,
        ]);

        $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
             VALUES ('Admin', 0, 'System', 'Service updated', :message)"
        )->execute([':message' => $name . ' service updated']);

        json_response(['message' => 'Service updated']);
    }

    $services = $pdo->query(
        'SELECT service_id, service_code, service_name, description, base_duration, base_price, category, is_active, created_at
         FROM services
         ORDER BY service_name'
    )->fetchAll();

    json_response(['services' => $services]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
