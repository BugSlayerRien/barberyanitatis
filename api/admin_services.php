<?php
// Admin services API

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('GET');

try {
    $pdo = get_db_connection();

    $stmt = $pdo->prepare(
        'SELECT service_id, service_name, description, base_duration, base_price, category, is_active, created_at
         FROM services
         ORDER BY service_name'
    );
    $stmt->execute();

    json_response(['services' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
