<?php

declare(strict_types=1);

/**
 * Server-only GoTrue Admin API helpers (service role).
 * Used to inspect Auth users for duplicate signup and to create Auth users
 * when Admin creates a brand-new barber who is not already in Auth.
 */

require_once __DIR__ . '/storage.php';

/**
 * @param list<string> $providers
 */
function supabase_admin_is_oauth_only(array $providers): bool
{
    $normalized = [];
    foreach ($providers as $provider) {
        $p = strtolower(trim((string)$provider));
        if ($p !== '') {
            $normalized[$p] = true;
        }
    }

    $hasOauth = isset($normalized['google']) || isset($normalized['facebook']) || isset($normalized['apple']);
    $hasEmail = isset($normalized['email']);

    return $hasOauth && !$hasEmail;
}

/**
 * @param array<string, mixed> $user
 * @return list<string>
 */
function supabase_admin_providers_from_user(array $user): array
{
    $found = [];

    $identities = $user['identities'] ?? null;
    if (is_array($identities)) {
        foreach ($identities as $identity) {
            if (!is_array($identity)) {
                continue;
            }
            $provider = strtolower(trim((string)($identity['provider'] ?? '')));
            if ($provider !== '') {
                $found[$provider] = true;
            }
        }
    }

    $appMeta = $user['app_metadata'] ?? null;
    if (is_array($appMeta)) {
        $providers = $appMeta['providers'] ?? null;
        if (is_array($providers)) {
            foreach ($providers as $provider) {
                $p = strtolower(trim((string)$provider));
                if ($p !== '') {
                    $found[$p] = true;
                }
            }
        }
        $provider = strtolower(trim((string)($appMeta['provider'] ?? '')));
        if ($provider !== '') {
            $found[$provider] = true;
        }
    }

    return array_keys($found);
}

/**
 * @return array{ok: bool, status: int, body: mixed, raw: string, error: ?string}
 */
function supabase_admin_http(string $method, string $pathWithQuery, ?array $payload = null): array
{
    $base = rtrim(storage_supabase_base_url(), '/');
    $key = storage_service_role_key();
    if ($base === '' || $key === '') {
        return [
            'ok' => false,
            'status' => 0,
            'body' => null,
            'raw' => '',
            'error' => 'not_configured',
        ];
    }

    $url = $base . '/auth/v1' . $pathWithQuery;
    $ch = curl_init($url);
    if ($ch === false) {
        return [
            'ok' => false,
            'status' => 0,
            'body' => null,
            'raw' => '',
            'error' => 'curl_init_failed',
        ];
    }

    $headers = [
        'apikey: ' . $key,
        'Authorization: Bearer ' . $key,
        'Content-Type: application/json',
        'Accept: application/json',
    ];

    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CUSTOMREQUEST => strtoupper($method),
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_TIMEOUT => 15,
        CURLOPT_FOLLOWLOCATION => false,
    ] + api_curl_ssl_options();

    if ($payload !== null) {
        $opts[CURLOPT_POSTFIELDS] = json_encode($payload, JSON_UNESCAPED_SLASHES);
    }

    curl_setopt_array($ch, $opts);
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if ($raw === false) {
        return [
            'ok' => false,
            'status' => $status,
            'body' => null,
            'raw' => '',
            'error' => $curlError !== '' ? $curlError : 'curl_failed',
        ];
    }

    $decoded = json_decode((string)$raw, true);

    return [
        'ok' => $status >= 200 && $status < 300,
        'status' => $status,
        'body' => $decoded,
        'raw' => (string)$raw,
        'error' => null,
    ];
}

/**
 * @param array<string, mixed> $decoded
 * @return array<string, mixed>|null
 */
function supabase_admin_extract_user_from_list_payload(mixed $decoded, string $email): ?array
{
    $needle = strtolower(trim($email));
    if ($needle === '') {
        return null;
    }

    if (!is_array($decoded)) {
        return null;
    }

    if (isset($decoded['id'], $decoded['email']) && is_string($decoded['email'])) {
        if (strtolower($decoded['email']) === $needle) {
            return $decoded;
        }
    }

    if (isset($decoded['user']) && is_array($decoded['user'])) {
        $userEmail = strtolower(trim((string)($decoded['user']['email'] ?? '')));
        if ($userEmail === $needle) {
            return $decoded['user'];
        }
    }

    $lists = [];
    if (isset($decoded['users']) && is_array($decoded['users'])) {
        $lists[] = $decoded['users'];
    }
    if (array_is_list($decoded) || (isset($decoded[0]) && is_array($decoded[0] ?? null))) {
        $lists[] = $decoded;
    }

    foreach ($lists as $list) {
        foreach ($list as $user) {
            if (!is_array($user)) {
                continue;
            }
            $userEmail = strtolower(trim((string)($user['email'] ?? '')));
            if ($userEmail === $needle) {
                return $user;
            }
        }
    }

    return null;
}

/**
 * Lookup a GoTrue user by email (case-insensitive match on the returned record).
 *
 * @return array{
 *   lookup: 'ok'|'not_found'|'not_configured'|'error',
 *   user: ?array,
 *   providers: list<string>,
 *   oauthOnly: bool,
 *   detail: string
 * }
 */
function supabase_admin_find_user_by_email(string $email): array
{
    $normalized = strtolower(trim($email));
    $empty = [
        'lookup' => 'not_found',
        'user' => null,
        'providers' => [],
        'oauthOnly' => false,
        'detail' => '',
    ];

    if ($normalized === '') {
        return $empty;
    }

    $query = '/admin/users?email=' . rawurlencode($normalized);
    $response = supabase_admin_http('GET', $query);

    if (($response['error'] ?? null) === 'not_configured') {
        return [
            'lookup' => 'not_configured',
            'user' => null,
            'providers' => [],
            'oauthOnly' => false,
            'detail' => 'Supabase service role is not configured',
        ];
    }

    if (!$response['ok']) {
        return [
            'lookup' => 'error',
            'user' => null,
            'providers' => [],
            'oauthOnly' => false,
            'detail' => 'Auth admin lookup HTTP ' . (int)$response['status'],
        ];
    }

    $user = supabase_admin_extract_user_from_list_payload($response['body'], $normalized);
    if ($user === null) {
        $empty['lookup'] = 'not_found';
        return $empty;
    }

    $providers = supabase_admin_providers_from_user($user);

    return [
        'lookup' => 'ok',
        'user' => $user,
        'providers' => $providers,
        'oauthOnly' => supabase_admin_is_oauth_only($providers),
        'detail' => '',
    ];
}

/**
 * Create a confirmed Auth user when the email is not already in Auth.
 *
 * @return array{ok: bool, created: bool, alreadyExists: bool, error: ?string}
 */
function supabase_admin_ensure_user(string $email, string $password, string $fullName): array
{
    $normalized = strtolower(trim($email));
    $existing = supabase_admin_find_user_by_email($normalized);
    if ($existing['lookup'] === 'ok') {
        return ['ok' => true, 'created' => false, 'alreadyExists' => true, 'error' => null];
    }
    if ($existing['lookup'] === 'not_configured') {
        return ['ok' => false, 'created' => false, 'alreadyExists' => false, 'error' => 'not_configured'];
    }
    if ($existing['lookup'] === 'error') {
        return ['ok' => false, 'created' => false, 'alreadyExists' => false, 'error' => $existing['detail']];
    }

    $response = supabase_admin_http('POST', '/admin/users', [
        'email' => $normalized,
        'password' => $password,
        'email_confirm' => true,
        'user_metadata' => ['full_name' => trim($fullName)],
    ]);

    if ($response['ok']) {
        return ['ok' => true, 'created' => true, 'alreadyExists' => false, 'error' => null];
    }

    $status = (int)$response['status'];
    $raw = strtolower($response['raw'] . json_encode($response['body']));
    $already = $status === 422 || $status === 409
        || str_contains($raw, 'already')
        || str_contains($raw, 'registered')
        || str_contains($raw, 'exists');

    if ($already) {
        return ['ok' => true, 'created' => false, 'alreadyExists' => true, 'error' => null];
    }

    return [
        'ok' => false,
        'created' => false,
        'alreadyExists' => false,
        'error' => 'Auth admin createUser HTTP ' . $status,
    ];
}

function public_email_exists_in_app_tables(PDO $pdo, string $email): bool
{
    $e = strtolower(trim($email));
    if ($e === '') {
        return false;
    }

    $checks = [
        'SELECT 1 FROM users WHERE lower(email) = lower(:e) LIMIT 1',
        'SELECT 1 FROM barbers WHERE email IS NOT NULL AND lower(email) = lower(:e) LIMIT 1',
        'SELECT 1 FROM staff_users WHERE lower(email) = lower(:e) LIMIT 1',
    ];
    foreach ($checks as $sql) {
        $stmt = $pdo->prepare($sql);
        $stmt->execute([':e' => $e]);
        if ($stmt->fetchColumn()) {
            return true;
        }
    }

    return false;
}

/**
 * @return array<string, mixed>
 */
function build_check_email_exists_payload(PDO $pdo, string $email): array
{
    $inPublic = public_email_exists_in_app_tables($pdo, $email);
    $auth = supabase_admin_find_user_by_email($email);
    $inAuth = $auth['lookup'] === 'ok';
    $providers = $inAuth ? $auth['providers'] : [];
    $oauthOnly = $inAuth && $auth['oauthOnly'];

    return [
        'exists' => $inPublic || $inAuth,
        'inPublicUsers' => $inPublic,
        'inAuth' => $inAuth,
        'authLookup' => $auth['lookup'],
        'providers' => $providers,
        'oauthOnly' => $oauthOnly,
    ];
}
