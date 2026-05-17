<?php
// Database connection helper (PDO)
// Supported environment variables:
// DB_URL or DATABASE_URL (postgresql://user:pass@host:port/db)
// DB_DSN (direct PDO DSN)
// DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS, DB_SSLMODE, DB_HOSTADDR

declare(strict_types=1);

function load_repository_env(): void
{
    static $loaded = false;

    if ($loaded) {
        return;
    }

    $loaded = true;
    $envFile = dirname(__DIR__) . DIRECTORY_SEPARATOR . '.env';

    if (!is_file($envFile) || !is_readable($envFile)) {
        return;
    }

    $lines = file($envFile, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        return;
    }

    foreach ($lines as $line) {
        $trimmed = trim($line);
        if ($trimmed === '' || str_starts_with($trimmed, '#')) {
            continue;
        }

        if (str_starts_with($trimmed, 'export ')) {
            $trimmed = trim(substr($trimmed, 7));
        }

        $parts = explode('=', $trimmed, 2);
        if (count($parts) !== 2) {
            continue;
        }

        $key = trim($parts[0]);
        if ($key === '' || getenv($key) !== false) {
            continue;
        }

        $value = trim($parts[1]);
        if ($value !== '') {
            $first = $value[0];
            $last = $value[strlen($value) - 1];
            if (($first === '"' && $last === '"') || ($first === "'" && $last === "'")) {
                $value = substr($value, 1, -1);
            }
        }

        $value = str_replace(['\\n', '\\r', '\\t'], ["\n", "\r", "\t"], $value);
        putenv($key . '=' . $value);
        $_ENV[$key] = $value;
        $_SERVER[$key] = $value;
    }
}

function apply_cors_headers(): void
{
    $origin = trim((string)($_SERVER['HTTP_ORIGIN'] ?? ''));
    $allowedOriginsEnv = trim((string)(getenv('CORS_ALLOWED_ORIGINS') ?: ''));

    if ($allowedOriginsEnv === '') {
        if ($origin !== '' && preg_match('/^https?:\\/\\/(localhost|127\\.0\\.0\\.1)(:\\d+)?$/i', $origin) === 1) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Vary: Origin');
        } else {
            header('Access-Control-Allow-Origin: *');
        }
    } else {
        $allowedOrigins = array_values(array_filter(array_map('trim', explode(',', $allowedOriginsEnv))));
        if ($origin !== '' && in_array($origin, $allowedOrigins, true)) {
            header('Access-Control-Allow-Origin: ' . $origin);
            header('Vary: Origin');
        }
    }

    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With');
}

apply_cors_headers();

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function get_db_connection(): PDO
{
    load_repository_env();

    $dsn = trim((string)(getenv('DB_DSN') ?: ''));
    $user = (string)(getenv('DB_USER') ?: 'postgres');
    $pass = (string)(getenv('DB_PASS') ?: '');

    if ($dsn === '') {
        $url = trim((string)(
            getenv('DB_URL')
            ?: getenv('DATABASE_URL')
            ?: getenv('SUPABASE_DB_URL')
            ?: ''
        ));

        if ($url !== '') {
            $parts = parse_url($url);
            if ($parts === false) {
                throw new RuntimeException('Invalid DB URL');
            }

            $scheme = strtolower((string)($parts['scheme'] ?? ''));

            if ($scheme === 'postgresql' || $scheme === 'postgres') {
                $host = (string)($parts['host'] ?? '127.0.0.1');
                $port = (int)($parts['port'] ?? 5432);
                $db = ltrim((string)($parts['path'] ?? '/postgres'), '/');
                $urlUser = isset($parts['user']) ? urldecode((string)$parts['user']) : '';
                $urlPass = isset($parts['pass']) ? urldecode((string)$parts['pass']) : '';
                parse_str((string)($parts['query'] ?? ''), $query);
                $sslmode = (string)($query['sslmode'] ?? (getenv('DB_SSLMODE') ?: 'prefer'));

                $hostAddr = trim((string)($query['hostaddr'] ?? getenv('DB_HOSTADDR') ?: ''));

                $dsn = "pgsql:host={$host};port={$port};dbname={$db};sslmode={$sslmode}";
                if ($hostAddr !== '') {
                    $dsn .= ";hostaddr={$hostAddr}";
                }

                if ($urlUser !== '') {
                    $user = $urlUser;
                }
                if ($urlPass !== '') {
                    $pass = $urlPass;
                }
            } else {
                throw new RuntimeException('Unsupported DB URL scheme. Use postgresql://');
            }
        }
    }

    if ($dsn === '') {
        // Default local/fallback mode: PostgreSQL-compatible connection.
        // Supabase requires sslmode=require.
        $host = (string)(getenv('DB_HOST') ?: '127.0.0.1');
        $port = (int)(getenv('DB_PORT') ?: 5432);
        $db = (string)(getenv('DB_NAME') ?: 'postgres');
        $sslmode = (string)(getenv('DB_SSLMODE') ?: 'require');
        $hostAddr = trim((string)(getenv('DB_HOSTADDR') ?: ''));
        $dsn = "pgsql:host={$host};port={$port};dbname={$db};sslmode={$sslmode}";
        if ($hostAddr !== '') {
            $dsn .= ";hostaddr={$hostAddr}";
        }
    }

    $options = [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ];

    $pdo = new PDO($dsn, $user, $pass, $options);

    // Central price policy: all active haircut services are fixed at PHP 100.
    $pdo->exec("UPDATE services SET base_price = 100 WHERE is_active = TRUE AND LOWER(category) = 'haircut'");

    return $pdo;
}

function json_response(array $data, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

function get_json_input(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }

    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function require_method(string $method): void
{
    if ($_SERVER['REQUEST_METHOD'] !== $method) {
        json_response(['error' => 'Method not allowed'], 405);
    }
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

