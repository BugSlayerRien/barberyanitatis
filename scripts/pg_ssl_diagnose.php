<?php
/**
 * SSL / connectivity probe for PostgreSQL using DB_URL from .env.
 * Does not print the password. Run: php scripts/pg_ssl_diagnose.php
 */
declare(strict_types=1);

require_once __DIR__ . '/../api/http.php';

load_project_env();

$dbUrl = trim((string)(getenv('DB_URL') ?: ''));
if ($dbUrl === '') {
    fwrite(STDERR, "No DB_URL in .env.\n");
    exit(1);
}

$parts = parse_url($dbUrl);
if ($parts === false || !isset($parts['host'])) {
    fwrite(STDERR, "Invalid DB_URL.\n");
    exit(1);
}

$scheme = strtolower((string)($parts['scheme'] ?? ''));
if (!in_array($scheme, ['postgresql', 'postgres'], true)) {
    echo json_encode([
        'skipped' => true,
        'reason' => 'DB_URL is not PostgreSQL',
        'scheme' => $scheme,
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
    exit(0);
}

$host = (string)$parts['host'];
$port = (int)($parts['port'] ?? 5432);
$dbname = ltrim((string)($parts['path'] ?? '/postgres'), '/');
$user = urldecode((string)($parts['user'] ?? 'postgres'));
$pass = urldecode((string)($parts['pass'] ?? ''));

$query = [];
if (!empty($parts['query'])) {
    parse_str((string)$parts['query'], $query);
}
unset($query['sslmode']);

$extraParts = [];
foreach ($query as $k => $v) {
    if (is_array($v)) {
        continue;
    }
    $extraParts[] = $k . '=' . $v;
}
$extra = $extraParts !== [] ? implode(';', $extraParts) : '';

/**
 * @return array{sslmode: string, ok: bool, ms?: float, error?: string}
 */
function pg_try_sslmode(
    string $host,
    int $port,
    string $dbname,
    string $user,
    string $pass,
    string $sslmode,
    string $extraWithoutSsl,
): array {
    $dsn = "pgsql:host={$host};port={$port};dbname={$dbname};sslmode={$sslmode}";
    if ($extraWithoutSsl !== '') {
        $dsn .= ';' . $extraWithoutSsl;
    }
    $t0 = microtime(true);
    try {
        $pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]);
        $pdo->query('SELECT 1 AS probe');
        $ms = round((microtime(true) - $t0) * 1000, 1);

        return ['sslmode' => $sslmode, 'ok' => true, 'ms' => $ms];
    } catch (PDOException $e) {
        return ['sslmode' => $sslmode, 'ok' => false, 'error' => $e->getMessage()];
    }
}

$modes = ['disable', 'prefer', 'require', 'verify-full'];
$attempts = [];
foreach ($modes as $mode) {
    $attempts[] = pg_try_sslmode($host, $port, $dbname, $user, $pass, $mode, $extra);
}

$isSupabase = str_contains($host, 'supabase.co') || str_contains($host, 'supabase.com');

echo json_encode([
    'target' => [
        'host' => $host,
        'port' => $port,
        'dbname' => $dbname,
        'user' => $user,
        'password_configured' => $pass !== '',
        'likely_cloud' => $isSupabase,
    ],
    'note' => $isSupabase
        ? 'Managed Postgres (e.g. Supabase) usually rejects sslmode=disable; a failed disable attempt is normal.'
        : 'If disable works but require fails, the server may not offer TLS on this port.',
    'attempts' => $attempts,
    'psql_same_machine' => sprintf(
        'psql "host=%s port=%d dbname=%s user=%s sslmode=require"',
        $host,
        $port,
        $dbname,
        $user
    ),
    'server_logs' => $isSupabase
        ? [
            'Supabase' => 'Dashboard → Logs (filter Postgres / Pooler / API) around the time you run this script.',
            'SSL handshake' => 'Look for connection reset, SSL, or authentication failures; timestamps help match this probe.',
        ]
        : [
            'Self-hosted' => 'Check postgresql.conf log_destination and log_directory; or journalctl for the Postgres service.',
        ],
    'network_checklist' => [
        'Try another network or mobile hotspot (rules out ISP/router filtering).',
        'Temporarily disable VPN; exempt php.exe and httpd.exe from strict SSL inspection if using AV.',
        'If pooler host fails with SSL SYSCALL, try Supabase "Direct connection" URI (db.<ref>.supabase.co:5432) in DB_URL.',
    ],
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
