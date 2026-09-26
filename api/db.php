<?php
// Database connection (PDO) — reads DB_URL / DB_DSN / DB_HOST from .env via load_project_env()

declare(strict_types=1);

require_once __DIR__ . '/http.php';

if (PHP_SAPI !== 'cli') {
    load_project_env();
    apply_api_cors_headers();

    // Browsers on Vercel (cross-origin) send OPTIONS before JSON POSTs.
    // Endpoints that only allow GET/POST must still answer OPTIONS with 204 + CORS,
    // or the browser blocks the real request as "Failed to fetch".
    if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')) === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
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
 * Run idempotent schema setup once per server container instead of per request.
 *
 * Endpoints call ensure_*() helpers (ALTER TABLE ... ADD COLUMN IF NOT EXISTS,
 * CREATE TABLE IF NOT EXISTS, constraint checks) before doing any work. Their
 * `static $initialized` guards only last one PHP request, and under Apache every
 * request is a fresh one -- so booking.php alone was sending ~15 DDL statements
 * to Supabase on every call, including read-only ones. ALTER TABLE takes an
 * exclusive lock even when the column already exists, so this was the bulk of
 * the multi-second latency on booking screens.
 *
 * A marker file in the system temp dir records that the setup succeeded. The
 * key includes the newest modification time of every loaded API file and the
 * target database, so a deploy, a code change, or pointing DB_URL at a different
 * database all re-run the setup once. On Render each deploy starts a new
 * container with an empty temp dir, so migrations still run on first request.
 *
 * The marker is written only after $ensure returns, so a failed setup retries
 * on the next request instead of being skipped.
 */
function schema_ensure_once(string $key, callable $ensure): void
{
    static $done = [];

    $codeStamp = 0;
    foreach (get_included_files() as $file) {
        $mtime = @filemtime($file);
        if ($mtime !== false && $mtime > $codeStamp) {
            $codeStamp = $mtime;
        }
    }
    $dbStamp = substr(md5((string)(getenv('DB_URL') ?: getenv('DB_DSN') ?: getenv('DB_HOST') ?: '')), 0, 10);
    $stamp = preg_replace('/[^A-Za-z0-9_.-]/', '_', "{$key}-{$codeStamp}-{$dbStamp}");

    if (isset($done[$stamp])) {
        return;
    }

    $dir = rtrim(sys_get_temp_dir(), '/\\') . DIRECTORY_SEPARATOR . 'tatis_schema';
    $marker = $dir . DIRECTORY_SEPARATOR . $stamp;
    if (is_file($marker)) {
        $done[$stamp] = true;
        return;
    }

    $ensure();

    if (!is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }
    @touch($marker);
    $done[$stamp] = true;
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

/**
 * Kiosk walk-in: when the guest accepted the terms, and how they said they
 * would pay.
 *
 * Consent is recorded per walk-in rather than per device -- a kiosk is used by
 * a different person every time, so a stored "already agreed" flag would be
 * someone else's agreement.
 *
 * payment_mode is an intention, not a payment: the kiosk never calls the
 * gateway. Staff still take the money and complete the visit, which is what
 * records the actual payment (payment_recording.php).
 */
function ensure_walkin_kiosk_columns(PDO $pdo): void
{
    static $checked = false;
    if ($checked) {
        return;
    }
    $checked = true;

    if ((string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME) !== 'pgsql') {
        return;
    }

    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN IF NOT EXISTS consent_accepted_at TIMESTAMPTZ');
    $pdo->exec('ALTER TABLE walkin_queue ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20)');
}

/**
 * Who performed an audited action.
 *
 * `user_id` alone could not answer this: staff are `staff_users.staff_id`,
 * barbers are `barbers.barber_id` and customers are `users.user_id` — three
 * separate id spaces, so the same number means three different people
 * depending on the row. Every existing call site passes null, which made the
 * column useless anyway. The actor is recorded separately and `user_id` keeps
 * its original meaning: the customer a record belongs to.
 */
function ensure_audit_actor_columns(PDO $pdo): void
{
    $pdo->exec('ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_type VARCHAR(20)');
    $pdo->exec('ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_id BIGINT');
    $pdo->exec('ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_label VARCHAR(120)');
}

/** Actor descriptor for a signed-in portal staff member (see require_admin). */
function audit_actor_staff(array $staff): array
{
    $role = strtolower(trim((string)($staff['role'] ?? '')));
    $name = trim((string)($staff['full_name'] ?? ''));
    $email = trim((string)($staff['email'] ?? ''));

    return [
        'type' => $role === 'admin' ? 'admin' : 'staff',
        'id' => isset($staff['staff_id']) ? (int)$staff['staff_id'] : null,
        'label' => $name !== '' ? $name : ($email !== '' ? $email : 'Staff'),
    ];
}

/** Actor descriptor for work with no human behind it (sweeps, webhooks). */
function audit_actor_system(string $label = 'System'): array
{
    return ['type' => 'system', 'id' => null, 'label' => $label];
}

function audit_actor_webhook(string $label = 'PayMongo webhook'): array
{
    return ['type' => 'webhook', 'id' => null, 'label' => $label];
}

function audit_actor_customer(?int $userId, ?string $label = null): array
{
    return [
        'type' => 'customer',
        'id' => $userId,
        'label' => $label !== null && trim($label) !== '' ? trim($label) : 'Customer',
    ];
}

/**
 * Remembers who is acting for the rest of this request, so audit_log() calls
 * buried inside helper functions do not each have to be handed the identity.
 * Set once after authentication; an explicit $actor argument still wins.
 */
function audit_set_current_actor(?array $actor): void
{
    $GLOBALS['__audit_current_actor'] = $actor;
}

function audit_current_actor(): ?array
{
    $actor = $GLOBALS['__audit_current_actor'] ?? null;

    return is_array($actor) ? $actor : null;
}

/**
 * @param array|null $actor ['type' => ..., 'id' => ..., 'label' => ...], from
 *                          one of the audit_actor_* helpers. Falls back to
 *                          audit_set_current_actor() when omitted.
 */
function audit_log(PDO $pdo, string $action_type, ?string $table_name, ?string $record_id, ?array $old_values, ?array $new_values, ?int $user_id = null, ?array $actor = null): bool
{
    try {
        schema_ensure_once('audit_logs.actor', static function () use ($pdo): void {
            ensure_audit_actor_columns($pdo);
        });

        $ip_address = $_SERVER['REMOTE_ADDR'] ?? null;
        $user_agent = $_SERVER['HTTP_USER_AGENT'] ?? null;

        $actor = $actor ?? audit_current_actor();
        $actorLabel = isset($actor['label']) ? trim((string)$actor['label']) : '';

        $stmt = $pdo->prepare(
            'INSERT INTO audit_logs (action_type, table_name, record_id, old_values, new_values, user_id, actor_type, actor_id, actor_label, ip_address, user_agent, created_at)
             VALUES (:action_type, :table_name, :record_id, :old_values, :new_values, :user_id, :actor_type, :actor_id, :actor_label, :ip_address, :user_agent, NOW())'
        );

        return $stmt->execute([
            ':action_type' => $action_type,
            ':table_name' => $table_name,
            // Cast only when there is something to cast: (string)null is '',
            // which stored an empty string instead of leaving record_id NULL.
            ':record_id' => $record_id === null ? null : (string)$record_id,
            ':old_values' => $old_values ? json_encode($old_values) : null,
            ':new_values' => $new_values ? json_encode($new_values) : null,
            ':user_id' => $user_id,
            ':actor_type' => isset($actor['type']) ? (string)$actor['type'] : null,
            ':actor_id' => isset($actor['id']) && $actor['id'] !== null ? (int)$actor['id'] : null,
            ':actor_label' => $actorLabel !== '' ? $actorLabel : null,
            ':ip_address' => $ip_address,
            ':user_agent' => $user_agent,
        ]);
    } catch (PDOException $e) {
        // Audit failure must not break the action being audited, but silence
        // made a wrong column look like a working log. Leave a trace.
        error_log('audit_log failed (' . $action_type . '): ' . $e->getMessage());

        return false;
    }
}

