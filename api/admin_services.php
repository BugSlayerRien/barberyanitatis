<?php
// Admin services API (list + CRUD)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/service_channel.php';
require_once __DIR__ . '/admin_input.php';

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);
    ensure_service_channel_column($pdo);

    if ($method === 'GET') {
        $stmt = $pdo->prepare(
            'SELECT service_id, service_code, service_name, description,
                    base_duration, base_price, category, service_channel, is_active, created_at
             FROM services
             ORDER BY service_channel, service_name'
        );
        $stmt->execute();
        json_response(['services' => $stmt->fetchAll()]);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = trim((string)($input['action'] ?? ''));

    if ($action === 'create') {
        // Validated at the boundary: a rejected value returns 422 with a
        // reason, instead of being stored as-is (QA filed an SQL fragment as a
        // service name and it was accepted verbatim).
        $serviceName = admin_input_text($input['serviceName'] ?? '', 'Service name', 80, true);
        $description = admin_input_text($input['description'] ?? '', 'Description', 300);
        $baseDuration = admin_input_int($input['baseDuration'] ?? null, 'Duration', 5, 480, 30);
        $basePrice = admin_input_money($input['basePrice'] ?? null, 'Price', 0, 100000, 0);
        $category = admin_input_choice(
            $input['category'] ?? '',
            ['Haircut', 'Styling', 'Beard', 'Treatment'],
            'Category',
            'Haircut'
        );
        $channel = normalize_service_channel($input['serviceChannel'] ?? $input['service_channel'] ?? 'appointment') ?? 'appointment';
        $isActive = !empty($input['isActive']) && (string)$input['isActive'] !== '0';


        $codeBase = strtoupper(preg_replace('/[^A-Z0-9]+/', '_', $serviceName) ?? 'SVC');
        $codeBase = substr($codeBase, 0, 12) ?: 'SVC';
        $serviceCode = $codeBase . '_' . substr((string)time(), -4);

        $stmt = $pdo->prepare(
            'INSERT INTO services (
                service_code, service_name, description, base_duration, base_price,
                category, service_channel, is_active
             ) VALUES (
                :service_code, :service_name, :description, :base_duration, :base_price,
                :category, :service_channel, :is_active
             )
             RETURNING service_id'
        );
        $stmt->execute([
            ':service_code' => $serviceCode,
            ':service_name' => $serviceName,
            ':description' => $description !== '' ? $description : null,
            ':base_duration' => $baseDuration,
            ':base_price' => $basePrice,
            ':category' => $category !== '' ? $category : 'Haircut',
            ':service_channel' => $channel,
            ':is_active' => $isActive,
        ]);

        json_response([
            'message' => 'Service created',
            'serviceID' => (int)$stmt->fetchColumn(),
        ]);
    }

    if ($action === 'update') {
        $serviceID = (int)($input['serviceID'] ?? $input['service_id'] ?? 0);
        // Validated at the boundary: a rejected value returns 422 with a
        // reason, instead of being stored as-is (QA filed an SQL fragment as a
        // service name and it was accepted verbatim).
        $serviceName = admin_input_text($input['serviceName'] ?? '', 'Service name', 80, true);
        $description = admin_input_text($input['description'] ?? '', 'Description', 300);
        $baseDuration = admin_input_int($input['baseDuration'] ?? null, 'Duration', 5, 480, 30);
        $basePrice = admin_input_money($input['basePrice'] ?? null, 'Price', 0, 100000, 0);
        $category = admin_input_choice(
            $input['category'] ?? '',
            ['Haircut', 'Styling', 'Beard', 'Treatment'],
            'Category',
            'Haircut'
        );
        $channel = normalize_service_channel($input['serviceChannel'] ?? $input['service_channel'] ?? null);
        $isActive = !empty($input['isActive']) && (string)$input['isActive'] !== '0';

        if ($serviceID <= 0) {
            json_response(['error' => 'Invalid service payload'], 422);
        }

        $sql = 'UPDATE services
                SET service_name = :service_name,
                    description = :description,
                    base_duration = :base_duration,
                    base_price = :base_price,
                    category = :category,
                    is_active = :is_active';
        $params = [
            ':service_name' => $serviceName,
            ':description' => $description !== '' ? $description : null,
            ':base_duration' => $baseDuration,
            ':base_price' => $basePrice,
            ':category' => $category !== '' ? $category : 'Haircut',
            ':is_active' => $isActive,
            ':service_id' => $serviceID,
        ];

        if ($channel !== null) {
            $sql .= ', service_channel = :service_channel';
            $params[':service_channel'] = $channel;
        }
        $sql .= ' WHERE service_id = :service_id';

        $pdo->prepare($sql)->execute($params);
        json_response(['message' => 'Service updated']);
    }

    if ($action === 'delete') {
        $serviceID = (int)($input['serviceID'] ?? $input['service_id'] ?? 0);
        if ($serviceID <= 0) {
            json_response(['error' => 'Invalid serviceID'], 422);
        }

        $pdo->prepare('UPDATE services SET is_active = FALSE WHERE service_id = :service_id')
            ->execute([':service_id' => $serviceID]);

        json_response(['message' => 'Service deactivated']);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
