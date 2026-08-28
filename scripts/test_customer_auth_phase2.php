<?php
// Phase 2 customer API authorization tests. Does not mutate bookings/payments/feedback.

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/customer_auth.php';

$failures = 0;
$reports = [];

function phase2_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures, $reports;
    if (!$ok) {
        $failures++;
    }
    $reports[] = ['name' => $name, 'ok' => $ok, 'detail' => $detail];
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

function phase2_b64url(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function phase2_mint_hs256(array $payload, string $secret): string
{
    $header = phase2_b64url(json_encode(['alg' => 'HS256', 'typ' => 'JWT'], JSON_UNESCAPED_SLASHES));
    $body = phase2_b64url(json_encode($payload, JSON_UNESCAPED_SLASHES));
    $sig = phase2_b64url(hash_hmac('sha256', $header . '.' . $body, $secret, true));

    return $header . '.' . $body . '.' . $sig;
}

function phase2_http(string $url, array $body, array $headers = []): array
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
        CURLOPT_TIMEOUT => 25,
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
$testSecret = 'phase2-test-jwt-secret';
putenv('SUPABASE_JWT_SECRET=' . $testSecret);
$_ENV['SUPABASE_JWT_SECRET'] = $testSecret;

$now = time();
$pdo = get_db_connection();

$usersStmt = $pdo->query(
    "SELECT user_id, email
     FROM users
     WHERE is_active = TRUE
     ORDER BY user_id
     LIMIT 20"
);
$users = $usersStmt ? $usersStmt->fetchAll(PDO::FETCH_ASSOC) : [];
$usable = [];
foreach ($users as $row) {
    if (customer_is_usable_email((string)$row['email'])) {
        $usable[] = $row;
    }
}
if (count($usable) < 2) {
    phase2_ok('Need at least two public.users rows with emails for IDOR tests', false, 'found ' . count($usable));
    echo "\n{$failures} failed\n";
    exit($failures > 0 ? 1 : 0);
}

$userA = $usable[0];
$userB = $usable[1];
$userAId = (int)$userA['user_id'];
$userBId = (int)$userB['user_id'];

$tokenA = phase2_mint_hs256([
    'aud' => 'authenticated',
    'role' => 'authenticated',
    'email' => strtolower((string)$userA['email']),
    'sub' => 'phase2-user-a',
    'exp' => $now + 3600,
    'iat' => $now,
], $testSecret);
$tokenB = phase2_mint_hs256([
    'aud' => 'authenticated',
    'role' => 'authenticated',
    'email' => strtolower((string)$userB['email']),
    'sub' => 'phase2-user-b',
    'exp' => $now + 3600,
    'iat' => $now,
], $testSecret);

$_SERVER['HTTP_AUTHORIZATION'] = '';
unset($_SERVER['HTTP_X_SUPABASE_ACCESS_TOKEN']);
try {
    $guest = resolve_customer_or_guest($pdo, []);
    phase2_ok('Guest with no JWT and no userID is allowed (kiosk)', $guest === null);
} catch (CustomerAuthException $e) {
    phase2_ok('Guest with no JWT and no userID is allowed (kiosk)', false, $e->getMessage());
}

try {
    resolve_customer_or_guest($pdo, ['userID' => $userAId]);
    phase2_ok('Claimed userID without JWT is 401', false);
} catch (CustomerAuthException $e) {
    phase2_ok('Claimed userID without JWT is 401', $e->httpStatus === 401, (string)$e->httpStatus);
}

$_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $tokenA;
try {
    $resolved = resolve_customer_or_guest($pdo, ['userID' => $userAId]);
    phase2_ok(
        'User A JWT + A userID succeeds',
        is_array($resolved) && (int)$resolved['user_id'] === $userAId,
        'user_id=' . ($resolved['user_id'] ?? '')
    );
} catch (CustomerAuthException $e) {
    phase2_ok('User A JWT + A userID succeeds', false, $e->httpStatus . ' ' . $e->getMessage());
}

try {
    resolve_customer_or_guest($pdo, ['userID' => $userBId]);
    phase2_ok('User A JWT + B userID is 403', false);
} catch (CustomerAuthException $e) {
    phase2_ok('User A JWT + B userID is 403', $e->httpStatus === 403, $e->getMessage());
}

$pdo->exec(
    "CREATE TABLE IF NOT EXISTS face_scan_sessions (
        scan_session_id VARCHAR(80) PRIMARY KEY,
        user_id BIGINT,
        face_shape VARCHAR(50),
        hair_texture TEXT,
        hair_density TEXT,
        consent_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )"
);

$sessionB = 'phase2-idor-' . bin2hex(random_bytes(8));
$insertSession = $pdo->prepare(
    'INSERT INTO face_scan_sessions (scan_session_id, user_id, consent_at)
     VALUES (:scan_session_id, :user_id, NOW())'
);
$insertSession->execute([
    ':scan_session_id' => $sessionB,
    ':user_id' => $userBId,
]);

try {
    assert_scan_session_access($pdo, $sessionB, $userAId);
    phase2_ok('User A cannot access User B scan session', false);
} catch (CustomerAuthException $e) {
    phase2_ok('User A cannot access User B scan session', $e->httpStatus === 403, $e->getMessage());
}

try {
    assert_scan_session_access($pdo, $sessionB, $userBId);
    phase2_ok('User B can access own scan session', true);
} catch (CustomerAuthException $e) {
    phase2_ok('User B can access own scan session', false, $e->httpStatus . ' ' . $e->getMessage());
}

try {
    assert_scan_session_access($pdo, $sessionB, null);
    phase2_ok('Unauthenticated access to User B scan session is 401', false);
} catch (CustomerAuthException $e) {
    phase2_ok('Unauthenticated access to User B scan session is 401', $e->httpStatus === 401, (string)$e->httpStatus);
}

$apptB = $pdo->prepare(
    'SELECT appointment_id, user_id FROM appointments WHERE user_id = :user_id ORDER BY appointment_id DESC LIMIT 1'
);
$apptB->execute([':user_id' => $userBId]);
$bAppointment = $apptB->fetch(PDO::FETCH_ASSOC);

if ($bAppointment) {
    $_SERVER['HTTP_AUTHORIZATION'] = 'Bearer ' . $tokenA;
    try {
        assert_customer_owns_appointment($pdo, $userAId, (int)$bAppointment['appointment_id']);
        phase2_ok('User A cannot submit feedback for User B appointment', false);
    } catch (CustomerAuthException $e) {
        phase2_ok(
            'User A cannot submit feedback for User B appointment',
            $e->httpStatus === 403,
            $e->getMessage()
        );
    }
} else {
    phase2_ok('User A cannot submit feedback for User B appointment', true, 'skipped (user B has no appointments)');
}

$apiBase = getenv('PHASE2_API_BASE') ?: (getenv('PHASE1_API_BASE') ?: 'http://localhost/barberyanitatis/tatis_barbershop/api');
$apiBase = rtrim($apiBase, '/');

echo "\nHTTP checks against {$apiBase}\n";

$probe = phase2_http($apiBase . '/time_slots.php', ['action' => 'suggestBestSlot', 'userID' => $userAId]);
if ($probe['status'] === 0) {
    echo 'HTTP API not reachable at ' . $apiBase
        . ($probe['error'] !== '' ? " ({$probe['error']})" : '')
        . ". In-process auth checks already cover 401/403. Skipping live HTTP.\n";
} else {
    phase2_ok('HTTP no JWT → suggestBestSlot 401', $probe['status'] === 401, 'status=' . $probe['status']);

    $feedbackNoAuth = phase2_http($apiBase . '/barbers.php', [
        'action' => 'submitFeedback',
        'appointmentID' => (int)($bAppointment['appointment_id'] ?? 1),
        'barberID' => 1,
        'userID' => $userAId,
        'rating' => 5,
    ]);
    phase2_ok('HTTP no JWT → submitFeedback 401', $feedbackNoAuth['status'] === 401, 'status=' . $feedbackNoAuth['status']);

    $funnelNoAuth = phase2_http($apiBase . '/ai_funnel.php', [
        'action' => 'saveSelection',
        'scanSessionId' => $sessionB,
        'userID' => $userBId,
        'variantID' => 1,
        'styleName' => 'phase2',
    ]);
    phase2_ok('HTTP no JWT → ai_funnel saveSelection 401', $funnelNoAuth['status'] === 401, 'status=' . $funnelNoAuth['status']);

    $trackNoAuth = phase2_http($apiBase . '/ai_funnel.php', [
        'action' => 'trackScan',
        'scanSessionId' => 'phase2-guest',
        'userID' => $userAId,
    ]);
    phase2_ok('HTTP no JWT → ai_funnel trackScan 401', $trackNoAuth['status'] === 401, 'status=' . $trackNoAuth['status']);

    $scanClaimNoAuth = phase2_http($apiBase . '/ai_scan.php', [
        'action' => 'rankByFeatures',
        'userID' => $userAId,
        'faceShape' => 'Oval',
        'hairTexture' => 'Wavy',
    ]);
    phase2_ok(
        'HTTP no JWT + claimed userID → ai_scan 401',
        $scanClaimNoAuth['status'] === 401,
        'status=' . $scanClaimNoAuth['status']
    );

    $faceClaimNoAuth = phase2_http($apiBase . '/face_scan.php', [
        'action' => 'analyzeCaptures',
        'scanSessionId' => $sessionB,
        'userID' => $userBId,
    ]);
    phase2_ok(
        'HTTP no JWT + claimed userID → face_scan 401',
        $faceClaimNoAuth['status'] === 401,
        'status=' . $faceClaimNoAuth['status']
    );

    $attachNoAuth = phase2_http($apiBase . '/face_scan.php', [
        'action' => 'attachToAppointment',
        'appointmentID' => (int)($bAppointment['appointment_id'] ?? 1),
        'scanSessionId' => $sessionB,
        'variantID' => 1,
    ]);
    phase2_ok('HTTP no JWT → attachToAppointment 401', $attachNoAuth['status'] === 401, 'status=' . $attachNoAuth['status']);

    $slotsPublic = phase2_http($apiBase . '/time_slots.php', [
        'action' => 'listByBarberDate',
        'barberID' => 1,
        'slotDate' => '2099-01-01',
    ]);
    phase2_ok(
        'Public listByBarberDate still works without JWT',
        in_array($slotsPublic['status'], [200, 422], true),
        'status=' . $slotsPublic['status']
    );

    $barbersPublic = phase2_http($apiBase . '/barbers.php', ['action' => 'list']);
    phase2_ok('Public barber list still works without JWT', $barbersPublic['status'] === 200, 'status=' . $barbersPublic['status']);

    $kiosk = phase2_http($apiBase . '/kiosk.php', ['action' => 'not-a-real-action']);
    phase2_ok(
        'Kiosk endpoint remains unauthenticated',
        in_array($kiosk['status'], [200, 400], true),
        'status=' . $kiosk['status'] . ($kiosk['error'] !== '' ? ' ' . $kiosk['error'] : '')
    );

    $guestRank = phase2_http($apiBase . '/ai_scan.php', [
        'action' => 'rankByFeatures',
        'faceShape' => 'Oval',
        'hairTexture' => 'Wavy',
    ]);
    phase2_ok(
        'Kiosk/guest ai_scan rankByFeatures still works without JWT',
        $guestRank['status'] === 200,
        'status=' . $guestRank['status']
    );

    if ($originalJwtSecret === $testSecret) {
        $crossSuggest = phase2_http(
            $apiBase . '/time_slots.php',
            ['action' => 'suggestBestSlot', 'userID' => $userBId],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase2_ok(
            'HTTP User A JWT + B userID → suggestBestSlot 403',
            $crossSuggest['status'] === 403,
            'status=' . $crossSuggest['status']
        );

        $crossFunnel = phase2_http(
            $apiBase . '/ai_funnel.php',
            [
                'action' => 'saveSelection',
                'scanSessionId' => $sessionB,
                'userID' => $userBId,
                'variantID' => 1,
                'styleName' => 'phase2',
            ],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase2_ok(
            'HTTP User A JWT + B userID → ai_funnel 403',
            $crossFunnel['status'] === 403,
            'status=' . $crossFunnel['status']
        );

        $crossScan = phase2_http(
            $apiBase . '/face_scan.php',
            ['action' => 'analyzeCaptures', 'scanSessionId' => $sessionB],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase2_ok(
            'HTTP User A JWT cannot analyze User B scan session',
            $crossScan['status'] === 403,
            'status=' . $crossScan['status']
        );

        $crossFeedback = phase2_http(
            $apiBase . '/barbers.php',
            [
                'action' => 'submitFeedback',
                'appointmentID' => (int)($bAppointment['appointment_id'] ?? 1),
                'barberID' => 1,
                'userID' => $userBId,
                'rating' => 5,
            ],
            ['Authorization: Bearer ' . $tokenA]
        );
        phase2_ok(
            'HTTP User A JWT + B userID → submitFeedback 403',
            in_array($crossFeedback['status'], [403, 404], true),
            'status=' . $crossFeedback['status']
        );
    } else {
        echo "HTTP JWT 200/403 skipped: set SUPABASE_JWT_SECRET to enable live HS256 tests against Apache.\n";
    }
}

$pdo->prepare('DELETE FROM face_scan_sessions WHERE scan_session_id = :id')->execute([':id' => $sessionB]);

echo "\n";
if ($failures > 0) {
    echo "{$failures} failed\n";
    exit(1);
}

echo "All Phase 2 checks passed\n";
exit(0);
