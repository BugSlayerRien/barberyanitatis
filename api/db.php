<?php
// Database connection helper (PDO)
// Set environment variables in your server:
// DB_HOST, DB_NAME, DB_USER, DB_PASS

declare(strict_types=1);

function get_db_connection(): PDO
{
    $host = getenv('DB_HOST') ?: 'localhost';
    $db = getenv('DB_NAME') ?: 'tatis_barbershop';
    $user = getenv('DB_USER') ?: 'root';
    $pass = getenv('DB_PASS') ?: '';
    $charset = 'utf8mb4';

    $dsn = "mysql:host={$host};dbname={$db};charset={$charset}";

    $options = [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ];

    return new PDO($dsn, $user, $pass, $options);
}

function ensure_walkin_guest_name_column(PDO $pdo): void
{
    static $checked = false;
    if ($checked) {
        return;
    }
    $checked = true;

    $check = $pdo->query(
        "SELECT 1
         FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name = 'walkin_queue'
           AND column_name = 'guest_name'
         LIMIT 1"
    );
    if ($check && $check->fetchColumn()) {
        return;
    }
    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN guest_name VARCHAR(120)');
}

function audit_log(PDO $pdo, string $action_type, ?string $table_name, ?string $record_id, ?array $old_values, ?array $new_values, ?int $user_id = null): bool
{
    try {
        $ip_address = $_SERVER['REMOTE_ADDR'] ?? null;
        $user_agent = $_SERVER['HTTP_USER_AGENT'] ?? null;

        $stmt = $pdo->prepare(
            'INSERT INTO audit_logs (action_type, table_name, record_id, old_values, new_values, user_id, ip_address, user_agent, created_at)
             VALUES (:action_type, :table_name, :record_id, :old_values, :new_values, :user_id, :ip_address, :user_agent, NOW())'
        );

        return $stmt->execute([
            ':action_type' => $action_type,
            ':table_name' => $table_name,
            ':record_id' => (string)$record_id,
            ':old_values' => $old_values ? json_encode($old_values) : null,
            ':new_values' => $new_values ? json_encode($new_values) : null,
            ':user_id' => $user_id,
            ':ip_address' => $ip_address,
            ':user_agent' => $user_agent,
        ]);
    } catch (PDOException $e) {
        // Log silently if audit fails; don't break the main transaction
        return false;
    }
}

