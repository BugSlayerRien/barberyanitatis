<?php
/**
 * auth_sync.php
 * Server-side utilities to sync Supabase Auth users to public.users table.
 * Called after signup to create the public profile record.
 */

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/** Marker in public.users.password_hash: real password lives in Supabase Auth. */
const USER_PASSWORD_HASH_SUPABASE = '__auth_via_supabase__';
/** Marker: customer was provisioned via Google/Facebook; no app password. */
const USER_PASSWORD_HASH_OAUTH = '__oauth_only__';

function customer_password_kind(?string $hash): string
{
    $value = trim((string)$hash);
    if ($value === '' || $value === USER_PASSWORD_HASH_OAUTH || str_starts_with($value, USER_PASSWORD_HASH_OAUTH)) {
        return 'oauth';
    }
    if ($value === USER_PASSWORD_HASH_SUPABASE || str_starts_with($value, USER_PASSWORD_HASH_SUPABASE)) {
        return 'supabase';
    }

    return 'local';
}

/**
 * Create or update a public.users record from Supabase Auth metadata.
 * 
 * @param string $email The user's email (from auth.users)
 * @param string $fullName The user's full name (from auth metadata)
 * @return array ['success' => bool, 'message' => string, 'user_id' => int|null]
 */
function sync_auth_to_public_users(string $email, string $fullName): array {
    try {
        $pdo = get_db_connection();
        
        // Validate inputs
        if (empty(trim($email))) {
            return ['success' => false, 'message' => 'Email cannot be empty'];
        }
        
        if (empty(trim($fullName))) {
            return ['success' => false, 'message' => 'Full name cannot be empty'];
        }
        
        $normalizedEmail = strtolower(trim($email));

        // Check if user already exists in public.users (case-insensitive)
        $check = $pdo->prepare(
            'SELECT user_id, is_active FROM users WHERE lower(email) = lower(?) LIMIT 1'
        );
        $check->execute([$normalizedEmail]);
        $existing = $check->fetch(PDO::FETCH_ASSOC);

        if ($existing) {
            $existingId = (int)$existing['user_id'];
            if (!(bool)$existing['is_active']) {
                $reactivate = $pdo->prepare(
                    'UPDATE users
                     SET is_active = TRUE,
                         full_name = CASE WHEN ? <> \'\' THEN ? ELSE full_name END
                     WHERE user_id = ?'
                );
                $reactivate->execute([trim($fullName), trim($fullName), $existingId]);
            }

            return [
                'success' => true,
                'message' => 'User already in public.users',
                'user_id' => $existingId,
            ];
        }
        
        // Insert public.users identity only. Credentials stay in Supabase Auth.
        $stmt = $pdo->prepare(
            'INSERT INTO users (email, full_name, password_hash, is_active)
             VALUES (?, ?, ?, TRUE)
             RETURNING user_id'
        );

        $stmt->execute([$normalizedEmail, trim($fullName), USER_PASSWORD_HASH_SUPABASE]);
        $userId = $stmt->fetchColumn();
        
        if ($userId) {
            return ['success' => true, 'message' => 'User synced to public.users', 'user_id' => (int)$userId];
        }
        
        return ['success' => false, 'message' => 'Failed to insert user'];
        
    } catch (Throwable $e) {
        return ['success' => false, 'message' => 'Database error: ' . $e->getMessage()];
    }
}

// Only handle direct HTTP requests to auth_sync.php (not when included by auth.php).
$isDirectRequest = basename((string)($_SERVER['SCRIPT_FILENAME'] ?? '')) === basename(__FILE__);
if ($isDirectRequest && ($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    header('Content-Type: application/json');

    $data = json_decode(file_get_contents('php://input'), true) ?? [];
    $email = $data['email'] ?? '';
    $fullName = $data['full_name'] ?? '';

    $result = sync_auth_to_public_users($email, $fullName);
    http_response_code($result['success'] ? 200 : 400);
    echo json_encode($result);
    exit;
}
