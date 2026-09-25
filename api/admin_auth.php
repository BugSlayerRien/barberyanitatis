<?php
// Portal session tokens issued at staff login. Used to authorize admin-only APIs.
// The token is random; only a SHA-256 hash is stored. Never log the raw token.

declare(strict_types=1);

// audit_set_current_actor() / audit_actor_staff() live in db.php.
require_once __DIR__ . '/db.php';

const PORTAL_SESSION_TTL_SECONDS = 43200; // 12 hours

function ensure_portal_sessions_table(PDO $pdo): void
{
    static $ready = false;
    if ($ready) {
        return;
    }

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS portal_sessions (
            session_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            staff_id BIGINT NOT NULL,
            token_hash VARCHAR(64) NOT NULL UNIQUE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            expires_at TIMESTAMPTZ NOT NULL,
            last_used_at TIMESTAMPTZ
        )"
    );

    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_portal_sessions_staff ON portal_sessions (staff_id)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_portal_sessions_expires ON portal_sessions (expires_at)');
    $ready = true;
}

function portal_token_from_request(): string
{
    $candidates = [
        (string)($_SERVER['HTTP_AUTHORIZATION'] ?? ''),
        (string)($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? ''),
    ];
    foreach ($candidates as $header) {
        if (preg_match('/Bearer\s+(\S+)/i', $header, $matches) === 1) {
            return trim($matches[1]);
        }
    }

    return trim((string)($_SERVER['HTTP_X_PORTAL_TOKEN'] ?? ''));
}

function hash_portal_token(string $token): string
{
    return hash('sha256', $token);
}

function issue_portal_session(PDO $pdo, int $staffId): string
{
    ensure_portal_sessions_table($pdo);
    $pdo->prepare('DELETE FROM portal_sessions WHERE expires_at < NOW()')->execute();

    $token = bin2hex(random_bytes(32));
    $insert = $pdo->prepare(
        'INSERT INTO portal_sessions (staff_id, token_hash, expires_at)
         VALUES (:staff_id, :token_hash, NOW() + INTERVAL \'12 hours\')'
    );
    $insert->execute([
        ':staff_id' => $staffId,
        ':token_hash' => hash_portal_token($token),
    ]);

    return $token;
}

function attach_staff_portal_session(PDO $pdo, array $userPayload, int $staffId): array
{
    $token = issue_portal_session($pdo, $staffId);
    $userPayload['portalToken'] = $token;

    return $userPayload;
}

/**
 * @return array{staff_id:int, full_name:string, email:string, role:string}
 */
function require_admin(PDO $pdo): array
{
    ensure_portal_sessions_table($pdo);

    $token = portal_token_from_request();
    if ($token === '') {
        json_response(['error' => 'Admin authentication required.'], 401);
    }

    $stmt = $pdo->prepare(
        'SELECT s.staff_id, s.full_name, s.email, s.role, s.is_active, p.expires_at
         FROM portal_sessions p
         JOIN staff_users s ON s.staff_id = p.staff_id
         WHERE p.token_hash = :token_hash
         LIMIT 1'
    );
    $stmt->execute([':token_hash' => hash_portal_token($token)]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        json_response(['error' => 'Invalid or expired admin session.'], 401);
    }

    $expires = strtotime((string)$row['expires_at']);
    if ($expires !== false && $expires < time()) {
        json_response(['error' => 'Invalid or expired admin session.'], 401);
    }

    $active = $row['is_active'] === true || $row['is_active'] === 't' || (int)$row['is_active'] === 1;
    if (!$active) {
        json_response(['error' => 'Admin permission required.'], 403);
    }

    if (strtolower(trim((string)$row['role'])) !== 'admin') {
        json_response(['error' => 'Admin permission required.'], 403);
    }

    $pdo->prepare(
        'UPDATE portal_sessions SET last_used_at = NOW() WHERE token_hash = :token_hash'
    )->execute([':token_hash' => hash_portal_token($token)]);

    $staff = [
        'staff_id' => (int)$row['staff_id'],
        'full_name' => (string)$row['full_name'],
        'email' => (string)$row['email'],
        'role' => (string)$row['role'],
    ];

    // Every audit entry written later in this request is attributed to this
    // admin, including the ones inside helper functions that never see the
    // session. Their staff_id goes to actor_id, never to user_id -- that
    // column means "the customer this record is about".
    audit_set_current_actor(audit_actor_staff($staff));

    return $staff;
}
