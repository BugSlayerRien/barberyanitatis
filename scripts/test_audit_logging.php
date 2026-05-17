<?php
require_once __DIR__ . '/../api/db.php';

try {
    $pdo = get_db_connection();

    // Insert test audit entries to verify audit_logs is working
    $pdo->prepare(
        "INSERT INTO audit_logs (action_type, table_name, record_id, old_values, new_values, user_id, created_at)
         VALUES (:action_type, :table_name, :record_id, :old_values, :new_values, :user_id, NOW())"
    )->execute([
        ':action_type' => 'TEST_CREATE',
        ':table_name' => 'test_table',
        ':record_id' => '123',
        ':old_values' => null,
        ':new_values' => json_encode(['test' => 'value']),
        ':user_id' => 1,
    ]);

    $pdo->prepare(
        "INSERT INTO audit_logs (action_type, table_name, record_id, old_values, new_values, user_id, created_at)
         VALUES (:action_type, :table_name, :record_id, :old_values, :new_values, :user_id, NOW())"
    )->execute([
        ':action_type' => 'TEST_UPDATE',
        ':table_name' => 'test_table',
        ':record_id' => '456',
        ':old_values' => json_encode(['status' => 'Active']),
        ':new_values' => json_encode(['status' => 'Inactive']),
        ':user_id' => 2,
    ]);

    // Now fetch audit logs via the API
    $_SERVER['REQUEST_METHOD'] = 'GET';
    ob_start();
    include __DIR__ . '/../api/admin_audit.php';
    $out = ob_get_clean();
    
    $result = json_decode($out, true);
    echo json_encode([
        'status' => 'Test audit entries inserted and API response:',
        'events_count' => count($result['events'] ?? []),
        'sample_events' => array_slice($result['events'] ?? [], 0, 3),
    ], JSON_PRETTY_PRINT);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
