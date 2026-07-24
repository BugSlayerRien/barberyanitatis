<?php
declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';

$sqlFile = __DIR__ . '/../database/migrations/drop_unused_schema_objects.sql';
$sql = file_get_contents($sqlFile);
if ($sql === false) {
    fwrite(STDERR, "Could not read migration file.\n");
    exit(1);
}

try {
    $pdo = get_db_connection();
    $pdo->exec($sql);

    $tables = $pdo->query(
        "SELECT table_name
         FROM information_schema.tables
         WHERE table_schema = current_schema()
           AND table_type = 'BASE TABLE'
         ORDER BY table_name"
    )->fetchAll(PDO::FETCH_COLUMN);

    $views = $pdo->query(
        "SELECT table_name
         FROM information_schema.views
         WHERE table_schema = current_schema()
         ORDER BY table_name"
    )->fetchAll(PDO::FETCH_COLUMN);

    echo json_encode([
        'status' => 'ok',
        'dropped' => ['queue_display', 'feedback', 'user_history', 'daily_analytics', 'barber_performance'],
        'table_count' => count($tables),
        'tables' => $tables,
        'view_count' => count($views),
        'views' => $views,
    ], JSON_PRETTY_PRINT) . PHP_EOL;
} catch (Throwable $e) {
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}
