<?php
// Database connection (PDO) — reads DB_URL / DB_DSN / DB_HOST from .env via load_project_env()

declare(strict_types=1);

require_once __DIR__ . '/http.php';

if (PHP_SAPI !== 'cli') {
    load_project_env();
    apply_api_cors_headers();
}

/**
 * PayMongo / scripts call this name; it is the same as load_project_env().
 */
function load_repository_env(): void
{
    load_project_env();
}

function create_pdo(string $dsn, string $user, string $pass): PDO
{
    $options = [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ];

    return new PDO($dsn, $user, $pass, $options);
}

/**
 * Open PDO from .env (single attempt).
 */
function open_pdo_once(): PDO
{
    load_project_env();

    $dbUrl = trim((string)(getenv('DB_URL') ?: ''));
    if ($dbUrl !== '') {
        return connect_from_db_url($dbUrl);
    }

    $dsn = trim((string)(getenv('DB_DSN') ?: ''));
    if ($dsn !== '') {
        $user = getenv('DB_USER') ?: 'postgres';
        $pass = getenv('DB_PASS') ?: '';

        return create_pdo($dsn, $user, $pass);
    }

    $host = getenv('DB_HOST') ?: 'localhost';
    $db = getenv('DB_NAME') ?: 'tatis_barbershop';
    $user = getenv('DB_USER') ?: 'root';
    $pass = getenv('DB_PASS') ?: '';
    $charset = 'utf8mb4';

    return create_pdo("mysql:host={$host};dbname={$db};charset={$charset}", $user, $pass);
}

/**
 * Same as open_pdo_once(); kept as the name the rest of the API uses.
 */
function get_db_connection(): PDO
{
    return open_pdo_once();
}

/**
 * Runs your code with one connection. Same as calling get_db_connection() yourself.
 */
function with_pdo_retry(callable $callback, ?int $maxAttempts = null): mixed
{
    return $callback(get_db_connection());
}

/**
 * JSON body for DB errors (includes driver "details" so you can see connect vs query failures).
 *
 * @return array<string, mixed>
 */
function db_error_response_payload(PDOException $e): array
{
    return [
        'error' => 'Database error',
        'details' => $e->getMessage(),
    ];
}

function connect_from_db_url(string $dbUrl): PDO
{
    $parts = parse_url($dbUrl);
    if ($parts === false || !isset($parts['host'])) {
        throw new RuntimeException('Invalid DB_URL in .env');
    }

    $scheme = strtolower((string)($parts['scheme'] ?? 'postgresql'));
    $host = (string)$parts['host'];
    $port = (int)($parts['port'] ?? ($scheme === 'mysql' ? 3306 : 5432));
    $dbname = ltrim((string)($parts['path'] ?? '/postgres'), '/');
    $user = urldecode((string)($parts['user'] ?? 'postgres'));
    $pass = urldecode((string)($parts['pass'] ?? ''));

    if ($scheme === 'mysql') {
        $dsn = "mysql:host={$host};port={$port};dbname={$dbname};charset=utf8mb4";

        return create_pdo($dsn, $user, $pass);
    }

    // PostgreSQL: pass through any ?query= options from DB_URL as libpq DSN parts.
    $dsn = "pgsql:host={$host};port={$port};dbname={$dbname}";
    if (!empty($parts['query'])) {
        $dsn .= ';' . str_replace('&', ';', (string)$parts['query']);
    }

    // Supabase (and their pooler) expect TLS. A URL with no sslmode often hits "SSL SYSCALL /
    // connection reset" on Windows with libpq — not a stricter app rule, just what that host needs.
    $isSupabaseHost = str_contains($host, 'supabase.co') || str_contains($host, 'supabase.com');
    if ($isSupabaseHost && stripos($dsn, 'sslmode=') === false) {
        $dsn .= ';sslmode=require';
    }

    return create_pdo($dsn, $user, $pass);
}

function ensure_walkin_guest_name_column(PDO $pdo): void
{
    static $checked = false;
    if ($checked) {
        return;
    }
    $checked = true;

    $driver = (string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
    if ($driver !== 'pgsql') {
        return;
    }

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

    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN IF NOT EXISTS guest_name VARCHAR(120)');
}

function ensure_walkin_queue_timestamp_columns(PDO $pdo): void
{
    static $checked = false;
    if ($checked) {
        return;
    }
    $checked = true;

    if ((string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'pgsql') {
        return;
    }

    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN IF NOT EXISTS actual_start TIMESTAMPTZ');
    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN IF NOT EXISTS actual_end TIMESTAMPTZ');
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
        return false;
    }
}

