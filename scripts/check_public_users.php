<?php
require_once __DIR__ . '/../api/db.php';
try {
    $pdo = get_db_connection();
    $stmt = $pdo->query("SELECT user_id, email, full_name, is_active, created_at FROM users ORDER BY created_at DESC LIMIT 50");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    echo json_encode(['count' => count($rows), 'recent' => $rows], JSON_PRETTY_PRINT);
} catch (Throwable $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
