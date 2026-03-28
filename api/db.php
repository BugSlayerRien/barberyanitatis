<?php
// Database connection helper (PDO)
// Supported environment variables:
// DB_URL or DATABASE_URL (postgresql://user:pass@host:port/db)
// DB_DSN (direct PDO DSN)
// DB_DRIVER, DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS

declare(strict_types=1);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

if (isset($_SERVER['REQUEST_METHOD']) && $_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function load_local_env_file(): void
{
    static $loaded = false;
    if ($loaded) {
        return;
    }
    $loaded = true;

    $envPath = dirname(__DIR__) . '/.env';
    if (!is_file($envPath) || !is_readable($envPath)) {
        return;
    }

    $lines = file($envPath, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return;
    }

    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) {
            continue;
        }

        $parts = explode('=', $line, 2);
        if (count($parts) !== 2) {
            continue;
        }

        $key = trim($parts[0]);
        $value = trim($parts[1]);
        if ($key === '' || getenv($key) !== false) {
            continue;
        }

        if ((str_starts_with($value, '"') && str_ends_with($value, '"')) || (str_starts_with($value, "'") && str_ends_with($value, "'"))) {
            $value = substr($value, 1, -1);
        }

        putenv($key . '=' . $value);
        $_ENV[$key] = $value;
        $_SERVER[$key] = $value;
    }
}

function get_db_connection(): PDO
{
    load_local_env_file();

    $dsn = trim((string)(getenv('DB_DSN') ?: ''));
    $user = trim((string)(getenv('DB_USER') ?: ''));
    $pass = (string)(getenv('DB_PASS') ?: '');

    if ($dsn === '') {
        $url = trim((string)(getenv('DB_URL') ?: getenv('DATABASE_URL') ?: ''));

        if ($url !== '') {
            $parts = parse_url($url);
            if ($parts === false) {
                throw new RuntimeException('Invalid DB URL');
            }

            $scheme = strtolower((string)($parts['scheme'] ?? 'postgresql'));
            if ($scheme === 'postgresql' || $scheme === 'postgres') {
                $host = (string)($parts['host'] ?? '127.0.0.1');
                $port = (int)($parts['port'] ?? 5432);
                $db = ltrim((string)($parts['path'] ?? '/postgres'), '/');
                $urlUser = isset($parts['user']) ? urldecode((string)$parts['user']) : '';
                $urlPass = isset($parts['pass']) ? urldecode((string)$parts['pass']) : '';
                parse_str((string)($parts['query'] ?? ''), $query);
                $sslmode = (string)($query['sslmode'] ?? 'require');

                $hostAddr = trim((string)($query['hostaddr'] ?? getenv('DB_HOSTADDR') ?: ''));
                if ($hostAddr === '' && function_exists('dns_get_record')) {
                    $records = dns_get_record($host, DNS_AAAA);
                    if (is_array($records) && isset($records[0]['ipv6'])) {
                        $hostAddr = (string)$records[0]['ipv6'];
                    }
                }

                $dsn = "pgsql:host={$host};port={$port};dbname={$db};sslmode={$sslmode}";
                if ($hostAddr !== '') {
                    $dsn .= ";hostaddr={$hostAddr}";
                }
                $user = $user !== '' ? $user : $urlUser;
                $pass = $pass !== '' ? $pass : $urlPass;
            } else {
                throw new RuntimeException('Unsupported DB URL scheme. Use postgresql://');
            }
        }

        if ($dsn === '') {
            $driver = strtolower((string)(getenv('DB_DRIVER') ?: 'mysql'));
            $host = (string)(getenv('DB_HOST') ?: '127.0.0.1');
            $port = (string)(getenv('DB_PORT') ?: '');
            $db = (string)(getenv('DB_NAME') ?: 'barberyanitatis');
            $user = $user !== '' ? $user : (string)(getenv('DB_USER') ?: 'root');
            $pass = $pass !== '' ? $pass : (string)(getenv('DB_PASS') ?: '');

            if ($driver === 'pgsql' || $driver === 'postgres' || $driver === 'postgresql') {
                $port = $port !== '' ? $port : '5432';
                $sslmode = (string)(getenv('DB_SSLMODE') ?: 'prefer');
                $hostAddr = trim((string)(getenv('DB_HOSTADDR') ?: ''));
                $dsn = "pgsql:host={$host};port={$port};dbname={$db};sslmode={$sslmode}";
                if ($hostAddr !== '') {
                    $dsn .= ";hostaddr={$hostAddr}";
                }
            } else {
                $port = $port !== '' ? $port : '3306';
                $charset = 'utf8mb4';
                $dsn = "mysql:host={$host};port={$port};dbname={$db};charset={$charset}";
            }
        }
    }

    $options = [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ];

    return new PDO($dsn, $user, $pass, $options);
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
