<?php
// Database connection helper (PDO)
<<<<<<< Updated upstream
// Set environment variables in your server:
// DB_HOST, DB_NAME, DB_USER, DB_PASS
=======
// Supported environment variables:
// DB_URL or DATABASE_URL (postgresql://user:pass@host:port/db)
// DB_DSN (direct PDO DSN)
// DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS, DB_SSLMODE, DB_HOSTADDR
>>>>>>> Stashed changes

declare(strict_types=1);

function get_db_connection(): PDO
{
    $host = getenv('DB_HOST') ?: 'localhost';
    $db = getenv('DB_NAME') ?: 'barberyanitatis';
    $user = getenv('DB_USER') ?: 'root';
    $pass = getenv('DB_PASS') ?: '';
    $charset = 'utf8mb4';

<<<<<<< Updated upstream
    $dsn = "mysql:host={$host};dbname={$db};charset={$charset}";
=======
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
            $host = (string)(getenv('DB_HOST') ?: '127.0.0.1');
            $port = (string)(getenv('DB_PORT') ?: '5432');
            $db = (string)(getenv('DB_NAME') ?: 'postgres');
            $user = $user !== '' ? $user : (string)(getenv('DB_USER') ?: '');
            $pass = $pass !== '' ? $pass : (string)(getenv('DB_PASS') ?: '');

            $sslmode = (string)(getenv('DB_SSLMODE') ?: 'require');
            $hostAddr = trim((string)(getenv('DB_HOSTADDR') ?: ''));
            $dsn = "pgsql:host={$host};port={$port};dbname={$db};sslmode={$sslmode}";
            if ($hostAddr !== '') {
                $dsn .= ";hostaddr={$hostAddr}";
            }
        }
    }
>>>>>>> Stashed changes

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
