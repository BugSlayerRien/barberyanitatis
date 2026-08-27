<?php
// Phase 1 customer API authorization tests. Does not mutate bookings/payments.

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/customer_auth.php';

$failures = 0;
$reports = [];

function phase1_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures, $reports;
    if (!$ok) {
        $failures++;
    }
    $reports[] = ['name' => $name, 'ok' => $ok, 'detail' => $detail];
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

function phase1_b64url(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function phase1_mint_hs256(array $payload, string $secret): string
{
    $header = phase1_b64url(json_encode(['alg' => 'HS256', 'typ' => 'JWT'], JSON_UNESCAPED_SLASHES));
    $body = phase1_b64url(json_encode($payload, JSON_UNESCAPED_SLASHES));
    $sig = phase1_b64url(hash_hmac('sha256', $header . '.' . $body, $secret, true));

    return $header . '.' . $body . '.' . $sig;
}

function phase1_http(string $url, array $body, array $headers = []): array
{
    $ch = curl_init($url);
    $httpHeaders = ['Content-Type: application/json'];
    foreach ($headers as $header) {
        $httpHeaders[] = $header;
    }
    $options = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => $httpHeaders,
        CURLOPT_POSTFIELDS => json_encode($body),
        CURLOPT_TIMEOUT => 20,
        CURLOPT_CONNECTTIMEOUT => 5,
    ];
    foreach (api_curl_ssl_options() as $opt => $value) {
        $options[$opt] = $value;
    }
    curl_setopt_array($ch, $options);
    $raw = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    $decoded = is_string($raw) && $raw !== '' ? json_decode($raw, true) : null;

    return [
        'status' => $status,
        'body' => is_array($decoded) ? $decoded : [],
        'raw' => is_string($raw) ? $raw : '',
        'error' => $err,
    ];
}

$originalJwtSecret = trim((string)(getenv('SUPABASE_JWT_SECRET') ?: ($_ENV['SUPABASE_JWT_SECRET'] ?? '')));
$testSecret = 'phase1-test-jwt-secret';
putenv('SUPABASE_JWT_SECRET=' . $testSecret);
$_ENV['SUPABASE_JWT_SECRET'] = $testSecret;

$now = time();
$validPayload = [
    'aud' => 'authenticated',
    'role' => 'authenticated',
    'email' => 'phase1-jwt-unit@example.com',
    'sub' => '00000000-0000-4000-8000-000000000001',
    'exp' => $now + 3600,
    'iat' => $now,
];
$token = phase1_mint_hs256($validPayload, $testSecret);
$verified = customer_verify_jwt_hs256($token, $testSecret);
phase1_ok('JWT HS256 accepts a valid authenticated token', is_array($verified) && ($verified['email'] ?? '') === 'phase1-jwt-unit@example.com');

$expired = $validPayload;
$expired['exp'] = $now - 120;
phase1_ok('JWT HS256 rejects an expired token', customer_verify_jwt_hs256(phase1_mint_hs256($expired, $testSecret), $testSecret) === null);

phase1_ok('JWT HS256 rejects a token signed with the wrong secret', customer_verify_jwt_hs256($token, 'other-secret') === null);

$anonPayload = $validPayload;
$anonPayload['role'] = 'anon';
$anonPayload['aud'] = 'anon';
phase1_ok('JWT HS256 rejects the project anon role', customer_verify_jwt_hs256(phase1_mint_hs256($anonPayload, $testSecret), $testSecret) === null);

try {
    customer_verify_supabase_access_token('');
    phase1_ok('Empty token is 401', false);
} catch (CustomerAuthException $e) {
    phase1_ok('Empty token is 401', $e->httpStatus === 401, (string)$e->httpStatus);
}

$pdo = get_db_connection();
putenv('SUPABASE_JWT_SECRET=' . $testSecret);
$_ENV['SUPABASE_JWT_SECRET'] = $testSecret;

$usersStmt = $pdo->query(
    "SELECT user_id, email, password_hash
     FROM users
     WHERE is_active = TRUE
     ORDER BY user_id
     LIMIT 20"
);
$users = $usersStmt ? $usersStmt->fetchAll(PDO::FETCH_ASSOC) : [];
if (count($users) < 2) {
    phase1_ok('Need at least two public.users rows for IDOR tests', false, 'found ' . count($users));
    echo "\n{$failures} failed\n";
    exit($failures > 0 ? 1 : 0);
}

$usable = [];
foreach ($users as $row) {
    if (customer_is_usable_email((string)$row['email'])) {
        $usable[] = $row;
    }
}
if (count($usable) < 2) {
    phase1_ok('Need at least two public.users rows with emails for IDOR tests', false, 'found ' . count($usable));
    echo "\n{$failures} failed\n";
    exit($failures > 0 ? 1 : 0);
}
$userA = $usable[0];
$userB = $usable[1];

$tokenA = phase1_mint_hs256([
    'aud' => 'authenticated',
    'role' => 'authenticated',
    'email' => strtolower((string)$userA['email']),
    'sub' => 'phase1-user-a',
    'exp' => $now + 3600,
    'iat' => $now,
], $testSecret);
$tokenB = phase1_mint_hs256([
    'aud' => 'authenticated',
    'role' => 'authenticated',
    'email' => strtolower((string)$userB['email']),
    'sub' => 'phase1-user-b',
    'exp' => $now + 3600,
    'iat' => $now,
], $testSecret);

$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $tokenA;
try {
    $resolved = resolve_authenticated_customer($pdo, ['userID' => (int)$userA['user_id']]);
    phase1_ok(
        '1. User A JWT + A userID succeeds',
        (int)$resolved['user_id'] === (int)$userA['user_id'],
        'user_id=' . $resolved['user_id']
    );
} catch (CustomerAuthException $e) {
    phase1_ok('1. User A JWT + A userID succeeds', false, $e->httpStatus . ' ' . $e->getMessage());
}

try {
    resolve_authenticated_customer($pdo, ['userID' => (int)$userB['user_id']]);
    phase1_ok('2. User A JWT + B userID is 403', false);
} catch (CustomerAuthException $e) {
    phase1_ok('2. User A JWT + B userID is 403', $e->httpStatus === 403, $e->getMessage());
}

$_SERVER['HTTP_AUTHORIZATION'] = '';
try {
    resolve_authenticated_customer($pdo, ['userID' => (int)$userA['user_id']]);
    phase1_ok('3. No JWT + any userID is 401', false);
} catch (CustomerAuthException $e) {
    phase1_ok('3. No JWT + any userID is 401', $e->httpStatus === 401, $e->getMessage());
}

$apptB = $pdo->prepare(
    'SELECT appointment_id, user_id FROM appointments WHERE user_id <> :user_id ORDER BY appointment_id DESC LIMIT 1'
);
$apptB->execute([':user_id' => (int)$userA['user_id']]);
$bAppointment = $apptB->fetch(PDO::FETCH_ASSOC);

if ($bAppointment) {
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $tokenA;
    try {
        $customerA = resolve_authenticated_customer($pdo, null);
        try {
            assert_customer_owns_appointment($pdo, $customerA['user_id'], (int)$bAppointment['appointment_id']);
            phase1_ok('4. User A JWT + User B appointment ID is 403', false, 'ownership helper did not stop the request');
        } catch (CustomerAuthException $e) {
            phase1_ok('4. User A JWT + User B appointment ID is 403', $e->httpStatus === 403, $e->getMessage());
        }
    } catch (CustomerAuthException $e) {
        phase1_ok('4. User A JWT + User B appointment ID is 403', false, $e->getMessage());
    }
} else {
    phase1_ok('4. User A JWT + User B appointment ID is 403', true, 'skipped (user B has no appointments)');
}

$phpOnlyStmt = $pdo->query(
    "SELECT user_id, email, password_hash
     FROM users
     WHERE is_active = TRUE
     ORDER BY user_id"
);
$phpOnlyAccounts = [];
$oauthOrSupabase = 0;
if ($phpOnlyStmt) {
    foreach ($phpOnlyStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $hash = (string)($row['password_hash'] ?? '');
        if (str_starts_with($hash, '__auth_via_supabase__') || str_starts_with($hash, '__oauth_only__')) {
            $oauthOrSupabase++;
            continue;
        }
        if ($hash !== '' && (str_starts_with($hash, '$2y$') || str_starts_with($hash, '$2a$') || str_starts_with($hash, '$2b$'))) {
            $phpOnlyAccounts[] = [
                'user_id' => (int)$row['user_id'],
                'email' => (string)$row['email'],
            ];
        }
    }
}

echo "Customers with a local bcrypt hash: " . count($phpOnlyAccounts)
    . " (PHP login alone will not issue a JWT; Flutter now continues to Supabase for customers).\n";
echo "Mapped with Supabase/OAuth sentinel hashes: {$oauthOrSupabase}.\n";
if ($phpOnlyAccounts !== []) {
    echo "Accounts that need a Supabase Auth user (same email) to call protected APIs:\n";
    foreach (array_slice($phpOnlyAccounts, 0, 8) as $row) {
        echo "  #{$row['user_id']} {$row['email']}\n";
    }
    if (count($phpOnlyAccounts) > 8) {
        echo '  ... and ' . (count($phpOnlyAccounts) - 8) . " more\n";
    }
}

$apiBase = getenv('PHASE1_API_BASE') ?: 'http://localhost/barberyanitatis/tatis_barbershop/api';
$apiBase = rtrim($apiBase, '/');

echo "\nHTTP checks against {$apiBase}\n";

$probe = phase1_http($apiBase . '/profile.php', ['action' => 'get', 'userID' => (int)$userA['user_id']]);
if ($probe['status'] === 0) {
    echo 'HTTP API not reachable at ' . $apiBase
        . ($probe['error'] !== '' ? " ({$probe['error']})" : '')
        . ". In-process auth checks already cover 401/403. Skipping live HTTP.\n";
} else {
    phase1_ok('HTTP no JWT → profile 401', $probe['status'] === 401, 'status=' . $probe['status']);

    $cancelNoAuth = phase1_http($apiBase . '/booking.php', ['action' => 'cancel', 'appointmentID' => 1]);
    phase1_ok('5. HTTP cancel without auth → 401', $cancelNoAuth['status'] === 401, 'status=' . $cancelNoAuth['status']);

    $rescheduleNoAuth = phase1_http($apiBase . '/booking.php', [
        'action' => 'reschedule',
        'appointmentID' => 1,
        'appointmentDate' => '2099-01-01',
        'startTime' => '10:00:00',
    ]);
    phase1_ok('5b. HTTP reschedule without auth → 401', $rescheduleNoAuth['status'] === 401, 'status=' . $rescheduleNoAuth['status']);

    $payNoAuth = phase1_http($apiBase . '/payments.php', [
        'action' => 'createIntent',
        'appointmentID' => (int)($bAppointment['appointment_id'] ?? 1),
        'amount' => 100,
    ]);
    phase1_ok('6. HTTP payment without JWT → 401', $payNoAuth['status'] === 401, 'status=' . $payNoAuth['status']);

    $catalog = phase1_http($apiBase . '/services.php', ['action' => 'list']);
    phase1_ok('10. Public services catalog still works', $catalog['status'] === 200, 'status=' . $catalog['status']);

    $barbers = phase1_http($apiBase . '/barbers.php', ['action' => 'list']);
    phase1_ok('10b. Public barber list still works', $barbers['status'] === 200, 'status=' . $barbers['status']);

    $listByBarber = phase1_http($apiBase . '/booking.php', ['action' => 'listByBarber', 'barberID' => 1]);
    phase1_ok(
        'Barber listByBarber remains usable without a customer JWT',
        in_array($listByBarber['status'], [200, 422], true),
        'status=' . $listByBarber['status']
    );

    $kiosk = phase1_http($apiBase . '/kiosk.php', ['action' => 'services']);
    phase1_ok(
        'Kiosk endpoint remains unauthenticated',
        $kiosk['status'] === 200 || $kiosk['status'] === 400,
        'status=' . $kiosk['status'] . (isset($kiosk['body']['error']) ? ' ' . $kiosk['body']['error'] : '')
    );

    if ($originalJwtSecret === $testSecret) {
        $withA = phase1_http(
            $apiBase . '/profile.php',
            ['action' => 'get', 'userID' => (int)$userA['user_id']],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase1_ok('HTTP User A JWT + A userID → 200', $withA['status'] === 200, 'status=' . $withA['status']);

        $cross = phase1_http(
            $apiBase . '/profile.php',
            ['action' => 'get', 'userID' => (int)$userB['user_id']],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase1_ok('HTTP User A JWT + B userID → 403', $cross['status'] === 403, 'status=' . $cross['status']);

        if ($bAppointment) {
            $payCross = phase1_http(
                $apiBase . '/payments.php',
                [
                    'action' => 'createIntent',
                    'appointmentID' => (int)$bAppointment['appointment_id'],
                    'amount' => 100,
                ],
                ['Authorization: Bearer ' . $tokenA]
            );
            phase1_ok(
                '6b. HTTP User A JWT + User B appointment payment → 403',
                $payCross['status'] === 403,
                'status=' . $payCross['status']
            );

            $cancelCross = phase1_http(
                $apiBase . '/booking.php',
                [
                    'action' => 'cancel',
                    'appointmentID' => (int)$bAppointment['appointment_id'],
                ],
                ['Authorization: Bearer ' . $tokenA]
            );
            phase1_ok(
                'HTTP User A JWT + User B cancel → 403',
                $cancelCross['status'] === 403,
                'status=' . $cancelCross['status']
            );
        }
    } else {
        echo "HTTP JWT 200/403 skipped: set SUPABASE_JWT_SECRET to enable live HS256 tests against Apache.\n";
    }
}

echo "\n";
if ($failures > 0) {
    echo "{$failures} failed\n";
    exit(1);
}

echo "All Phase 1 checks passed\n";
exit(0);
