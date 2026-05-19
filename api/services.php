<?php
// Services API (list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'list';

if ($action !== 'list') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    $pdo->exec("UPDATE services SET base_price = 100 WHERE is_active = TRUE AND LOWER(category) = 'haircut'");

    $stmt = $pdo->prepare(
        'SELECT service_id, service_name, description, base_duration,
                     CASE WHEN LOWER(category) = \'haircut\' THEN 100 ELSE base_price END AS base_price,
                category
         FROM services
            WHERE is_active = TRUE
         ORDER BY service_name'
    );
    $stmt->execute();

    json_response(['services' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
