<?php
require_once __DIR__ . '/../api/db.php';
try {
    $pdo = get_db_connection();
    $stmt = $pdo->query(
        "SELECT staff_id, email, full_name, role, is_active,
                CASE WHEN password_hash IS NULL OR password_hash = '' THEN 'empty' ELSE 'set' END AS password_state
         FROM staff_users
         ORDER BY staff_id"
    );
    echo json_encode(['staff' => $stmt->fetchAll(PDO::FETCH_ASSOC)], JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
