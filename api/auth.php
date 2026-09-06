<?php
// Unified auth API (register/login/google/forgot-password/reset-password)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/auth_sync.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/supabase_admin_auth.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));
$allowedActions = [
    'register',
    'login',
    'googleLogin',
    'forgotPassword',
    'verifyResetToken',
    'resetPassword',
    'changePassword',
    'checkEmailExists',
    'resolveAccount',
];

if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function is_valid_email(string $email): bool
{
    return filter_var($email, FILTER_VALIDATE_EMAIL) !== false;
}

/** App password policy (matches mobile registration). Returns error message or null. */
function validate_password_policy(string $password): ?string
{
    if (strlen($password) < 8) {
        return 'Password must be at least 8 characters long.';
    }
    if (!preg_match('/[A-Z]/', $password)) {
        return 'Password must contain at least one uppercase letter (A-Z).';
    }
    if (!preg_match('/[a-z]/', $password)) {
        return 'Password must contain at least one lowercase letter (a-z).';
    }
    if (!preg_match('/\d/', $password)) {
        return 'Password must contain at least one number (0-9).';
    }
    if (!preg_match('/[!@#$%^&*]/', $password)) {
        return 'Password must contain at least one special character (!@#$%^&*).';
    }
    return null;
}

function sanitize_full_name(string $fullName, string $emailFallback): string
{
    $name = trim($fullName);
    if ($name !== '') {
        return $name;
    }

    $prefix = trim((string)explode('@', $emailFallback)[0]);
    return $prefix !== '' ? $prefix : 'Customer';
}

function mask_email(string $email): string
{
    $parts = explode('@', $email, 2);
    if (count($parts) !== 2) {
        return '***';
    }

    [$local, $domain] = $parts;
    $localLen = strlen($local);
    if ($localLen <= 2) {
        $maskedLocal = str_repeat('*', max(1, $localLen));
    } else {
        $maskedLocal = substr($local, 0, 1) . str_repeat('*', $localLen - 2) . substr($local, -1);
    }

    return $maskedLocal . '@' . $domain;
}

function split_env_csv(string $value): array
{
    $parts = array_map('trim', explode(',', $value));
    $parts = array_values(array_filter($parts, static fn(string $item): bool => $item !== ''));
    return array_values(array_unique($parts));
}

function http_get_json(string $url): ?array
{
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        if ($ch === false) {
            return null;
        }

        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_TIMEOUT => 10,
            CURLOPT_HTTPHEADER => ['Accept: application/json'],
        ]);

        $body = curl_exec($ch);
        $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($body === false || $status < 200 || $status >= 300) {
            return null;
        }

        $decoded = json_decode($body, true);
        return is_array($decoded) ? $decoded : null;
    }

    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'timeout' => 10,
            'header' => "Accept: application/json\r\n",
        ],
    ]);
    $body = @file_get_contents($url, false, $context);
    if ($body === false) {
        return null;
    }

    $decoded = json_decode($body, true);
    return is_array($decoded) ? $decoded : null;
}

function is_google_identity_valid(string $email, string $googleUid, string $idToken, string $accessToken): bool
{
    $normalizedEmail = strtolower(trim($email));
    $normalizedUid = trim($googleUid);

    if ($idToken !== '') {
        $tokenInfo = http_get_json('https://oauth2.googleapis.com/tokeninfo?id_token=' . urlencode($idToken));
        if (is_array($tokenInfo)) {
            $tokenEmail = strtolower(trim((string)($tokenInfo['email'] ?? '')));
            $tokenSub = trim((string)($tokenInfo['sub'] ?? ''));
            $emailVerifiedRaw = $tokenInfo['email_verified'] ?? false;
            $emailVerified = is_bool($emailVerifiedRaw)
                ? $emailVerifiedRaw
                : in_array(strtolower(trim((string)$emailVerifiedRaw)), ['1', 'true', 'yes'], true);

            $aud = trim((string)($tokenInfo['aud'] ?? ''));
            $allowedAudiences = split_env_csv((string)(getenv('GOOGLE_ALLOWED_CLIENT_IDS') ?: ''));
            $audienceAllowed = empty($allowedAudiences) || ($aud !== '' && in_array($aud, $allowedAudiences, true));

            if (
                $emailVerified
                && $tokenEmail !== ''
                && $tokenEmail === $normalizedEmail
                && ($normalizedUid === '' || ($tokenSub !== '' && $tokenSub === $normalizedUid))
                && $audienceAllowed
            ) {
                return true;
            }
        }
    }

    if ($accessToken !== '') {
        $userInfo = http_get_json('https://www.googleapis.com/oauth2/v3/userinfo?access_token=' . urlencode($accessToken));
        if (is_array($userInfo)) {
            $tokenEmail = strtolower(trim((string)($userInfo['email'] ?? '')));
            $tokenSub = trim((string)($userInfo['sub'] ?? ''));
            $emailVerifiedRaw = $userInfo['email_verified'] ?? false;
            $emailVerified = is_bool($emailVerifiedRaw)
                ? $emailVerifiedRaw
                : in_array(strtolower(trim((string)$emailVerifiedRaw)), ['1', 'true', 'yes'], true);

            if (
                $emailVerified
                && $tokenEmail !== ''
                && $tokenEmail === $normalizedEmail
                && ($normalizedUid === '' || ($tokenSub !== '' && $tokenSub === $normalizedUid))
            ) {
                return true;
            }
        }
    }

    return false;
}

function build_user_payload(string $accountType, array $row): array
{
    if ($accountType === 'staff') {
        return [
            'userID' => (int)$row['staff_id'],
            'fullName' => (string)$row['full_name'],
            'email' => (string)$row['email'],
            'roles' => [strtolower((string)$row['role'])],
        ];
    }

    if ($accountType === 'barber') {
        return [
            'userID' => (int)$row['barber_id'],
            'fullName' => (string)$row['full_name'],
            'email' => (string)$row['email'],
            'roles' => ['barber'],
        ];
    }

    return [
        'userID' => (int)$row['user_id'],
        'fullName' => (string)$row['full_name'],
        'email' => (string)$row['email'],
        'roles' => ['customer'],
    ];
}

function password_hash_matches(array $row, string $password): bool
{
    $hash = (string)($row['password_hash'] ?? '');

    return $hash !== '' && password_verify($password, $hash);
}

function find_account_by_email(PDO $pdo, string $email): ?array
{
    $staffStmt = $pdo->prepare(
        'SELECT staff_id, full_name, email, role
         FROM staff_users
         WHERE lower(email) = lower(:email) AND is_active = TRUE
         LIMIT 1'
    );
    $staffStmt->execute([':email' => $email]);
    $staff = $staffStmt->fetch();
    if ($staff) {
        return ['type' => 'staff', 'row' => $staff];
    }

    $barberStmt = $pdo->prepare(
        'SELECT barber_id, full_name, email
         FROM barbers
         WHERE lower(email) = lower(:email) AND is_active = TRUE
         LIMIT 1'
    );
    $barberStmt->execute([':email' => $email]);
    $barber = $barberStmt->fetch();
    if ($barber) {
        return ['type' => 'barber', 'row' => $barber];
    }

    $userStmt = $pdo->prepare(
        'SELECT user_id, full_name, email
         FROM users
         WHERE lower(email) = lower(:email) AND is_active = TRUE
         LIMIT 1'
    );
    $userStmt->execute([':email' => $email]);
    $user = $userStmt->fetch();
    if ($user) {
        return ['type' => 'customer', 'row' => $user];
    }

    return null;
}

function ensure_auth_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS password_reset_requests (
            request_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            account_type VARCHAR(30) NOT NULL,
            account_id BIGINT NOT NULL,
            email VARCHAR(255) NOT NULL,
            reset_token VARCHAR(120) NOT NULL UNIQUE,
            expires_at TIMESTAMPTZ NOT NULL,
            used_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );
}

function find_valid_reset_request(PDO $pdo, string $token): ?array
{
    $stmt = $pdo->prepare(
        'SELECT request_id, account_type, account_id, email, expires_at
         FROM password_reset_requests
         WHERE reset_token = :reset_token
           AND used_at IS NULL
           AND expires_at > NOW()
         LIMIT 1'
    );
    $stmt->execute([':reset_token' => $token]);
    $row = $stmt->fetch();
    return $row ?: null;
}

function update_account_password(PDO $pdo, string $accountType, int $accountId, string $passwordHash): void
{
    if ($accountType === 'staff') {
        $stmt = $pdo->prepare('UPDATE staff_users SET password_hash = :password_hash WHERE staff_id = :id');
        $stmt->execute([':password_hash' => $passwordHash, ':id' => $accountId]);
        if ($stmt->rowCount() < 1) {
            throw new RuntimeException('Unable to update staff password.');
        }
        return;
    }

    if ($accountType === 'barber') {
        $stmt = $pdo->prepare('UPDATE barbers SET password_hash = :password_hash WHERE barber_id = :id');
        $stmt->execute([':password_hash' => $passwordHash, ':id' => $accountId]);
        if ($stmt->rowCount() < 1) {
            throw new RuntimeException('Unable to update barber password.');
        }
        return;
    }

    if ($accountType === 'customer') {
        $stmt = $pdo->prepare('UPDATE users SET password_hash = :password_hash WHERE user_id = :id');
        $stmt->execute([':password_hash' => $passwordHash, ':id' => $accountId]);
        if ($stmt->rowCount() < 1) {
            throw new RuntimeException('Unable to update customer password.');
        }
        return;
    }

    throw new RuntimeException('Unsupported account type for password reset.');
}

function create_customer_account(PDO $pdo, string $fullName, string $email): array
{
    $stmt = $pdo->prepare(
        'INSERT INTO users (email, password_hash, full_name, phone, gender)
         VALUES (:email, :password_hash, :full_name, :phone, :gender)
         RETURNING user_id, full_name, email'
    );
    $stmt->execute([
        ':email' => $email,
        ':password_hash' => USER_PASSWORD_HASH_OAUTH,
        ':full_name' => $fullName,
        ':phone' => null,
        ':gender' => 'Male',
    ]);

    $row = $stmt->fetch();
    if (!$row) {
        throw new RuntimeException('Unable to create customer account.');
    }

    return $row;
}

try {
    $pdo = get_db_connection();

    if ($action === 'register') {
        $fullName = trim((string)($input['fullName'] ?? ''));
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $password = (string)($input['password'] ?? '');
        $roleName = trim((string)($input['roleName'] ?? 'Customer'));

        if ($fullName === '' || $email === '' || $password === '') {
            json_response(['error' => 'Missing required fields'], 422);
        }
        if (!is_valid_email($email)) {
            json_response(['error' => 'Please provide a valid email address.'], 422);
        }
        if (strlen($password) < 6) {
            json_response(['error' => 'Password must be at least 6 characters.'], 422);
        }

        if (find_account_by_email($pdo, $email) !== null) {
            json_response(['error' => 'Email is already in use.'], 409);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        $stmt = $pdo->prepare(
            'INSERT INTO users (email, password_hash, full_name, phone, gender)
             VALUES (:email, :password_hash, :full_name, :phone, :gender)
             RETURNING user_id, full_name, email'
        );
        $stmt->execute([
            ':fullName' => $fullName,
            ':email' => $email,
            ':passwordHash' => $passwordHash,
            ':role' => $roleName,
        ]);
        $user = $stmt->fetch();

        json_response([
            'message' => 'Registration successful',
            'user' => [
                'userID' => (int)$user['user_id'],
                'fullName' => (string)$user['full_name'],
                'email' => (string)$user['email'],
                'roles' => ['customer'],
            ],
        ], 201);
    }

    if ($action === 'login') {
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $password = (string)($input['password'] ?? '');
        $isMobileClient = strtolower(trim((string)($input['client'] ?? ''))) === 'mobile';

        if ($email === '' || $password === '') {
            json_response(['error' => 'Missing email or password'], 422);
        }
        if (!is_valid_email($email)) {
            json_response(['error' => 'Please provide a valid email address.'], 422);
        }

        $staffStmt = $pdo->prepare(
            'SELECT staff_id, full_name, email, password_hash, role
             FROM staff_users
             WHERE lower(email) = lower(:email) AND is_active = TRUE
             LIMIT 1'
        );
        $staffStmt->execute([':email' => $email]);
        $staff = $staffStmt->fetch();

        $barberStmt = $pdo->prepare(
            'SELECT barber_id, full_name, email, password_hash
             FROM barbers
             WHERE lower(email) = lower(:email) AND is_active = TRUE
             LIMIT 1'
        );
        $barberStmt->execute([':email' => $email]);
        $barber = $barberStmt->fetch();

        $userStmt = $pdo->prepare(
            'SELECT user_id, full_name, email, password_hash
             FROM users
             WHERE lower(email) = lower(:email) AND is_active = TRUE
             LIMIT 1'
        );
        $userStmt->execute([':email' => $email]);
        $user = $userStmt->fetch();

        // Identity is which table the email lives in (users has no role column).
        // Staff > barber > customer — same order as find_account_by_email / Google.
        // A promoted customer still has an active users row, so customer must not win first.
        if ($staff && password_hash_matches($staff, $password)) {
            $user = attach_staff_portal_session($pdo, build_user_payload('staff', $staff), (int)$staff['staff_id']);
            json_response(['message' => 'Login successful', 'user' => $user, 'portalToken' => $user['portalToken']]);
        }

        // Mobile customers/barbers authenticate with Supabase Auth, not PHP hashes.
        // Web Admin/Receptionist login is unchanged. Legacy barber/customer PHP
        // password login remains only for non-mobile clients.
        if (!$isMobileClient) {
            if ($barber) {
                if (password_hash_matches($barber, $password) || ($user && password_hash_matches($user, $password))) {
                    json_response(['message' => 'Login successful', 'user' => build_user_payload('barber', $barber)]);
                }
            } elseif ($user && password_hash_matches($user, $password)) {
                json_response(['message' => 'Login successful', 'user' => build_user_payload('customer', $user)]);
            }
        }

        if ($staff) {
            json_response([
                'error' => empty($staff['password_hash'])
                    ? 'This staff account has no password set. Contact your administrator.'
                    : 'Invalid email or password.',
                'code' => empty($staff['password_hash']) ? 'NO_LOCAL_PASSWORD' : 'WRONG_PASSWORD',
                'accountType' => 'staff',
            ], 401);
        }

        if (!$isMobileClient && $barber) {
            json_response([
                'error' => empty($barber['password_hash'])
                    // Was leaking working demo credentials in an unauthenticated
                    // 401 body. Matches the staff branch above instead.
                    ? 'This barber account has no password set. Contact your administrator.'
                    : 'Invalid email or password.',
                'code' => empty($barber['password_hash']) ? 'NO_LOCAL_PASSWORD' : 'WRONG_PASSWORD',
                'accountType' => 'barber',
            ], 401);
        }

        if (!$isMobileClient && $user) {
            $kind = customer_password_kind((string)($user['password_hash'] ?? ''));
            if ($kind === 'oauth') {
                json_response([
                    'error' => 'This account uses Google/Facebook sign-in. Tap those buttons instead of email/password.',
                    'code' => 'OAUTH_ONLY',
                    'accountType' => 'customer',
                ], 401);
            }
            if ($kind === 'supabase') {
                json_response([
                    'error' => 'Use your email and password to sign in.',
                    'code' => 'SUPABASE_PASSWORD',
                    'accountType' => 'customer',
                ], 401);
            }
            json_response([
                'error' => 'Invalid email or password.',
                'code' => 'WRONG_PASSWORD',
                'accountType' => 'customer',
            ], 401);
        }

        json_response(['error' => 'Invalid credentials', 'code' => 'NOT_FOUND_LOCAL'], 401);
    }

    if ($action === 'googleLogin') {
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $fullName = sanitize_full_name(trim((string)($input['fullName'] ?? '')), $email);
        $googleUid = trim((string)($input['googleUid'] ?? ''));
        $idToken = trim((string)($input['idToken'] ?? ''));
        $accessToken = trim((string)($input['accessToken'] ?? ''));

        if ($email === '' || !is_valid_email($email)) {
            json_response(['error' => 'A valid Google email is required.'], 422);
        }
        if ($googleUid === '') {
            json_response(['error' => 'Google account identifier is missing.'], 422);
        }
        if ($idToken === '' && $accessToken === '') {
            json_response(['error' => 'Google authentication tokens are missing.'], 422);
        }

        if (!is_google_identity_valid($email, $googleUid, $idToken, $accessToken)) {
            json_response(['error' => 'Google token verification failed.'], 401);
        }

        $account = find_account_by_email($pdo, $email);
        if ($account !== null) {
            $user = build_user_payload((string)$account['type'], (array)$account['row']);
            if ((string)$account['type'] === 'staff') {
                $user = attach_staff_portal_session($pdo, $user, (int)$account['row']['staff_id']);
            }
            json_response([
                'message' => 'Google sign-in successful',
                'user' => $user,
                'portalToken' => $user['portalToken'] ?? null,
            ]);
        }

        $created = create_customer_account($pdo, $fullName, $email);
        json_response([
            'message' => 'Google sign-in successful',
            'user' => build_user_payload('customer', $created),
        ]);
    }

    if ($action === 'forgotPassword') {
        $email = strtolower(trim((string)($input['email'] ?? '')));
        if ($email === '' || !is_valid_email($email)) {
            json_response(['error' => 'Please provide a valid email address.'], 422);
        }

        ensure_auth_tables($pdo);

        $debugToken = null;
        $account = find_account_by_email($pdo, $email);
        if ($account !== null) {
            $accountType = (string)$account['type'];
            $row = (array)$account['row'];
            $accountId = $accountType === 'staff'
                ? (int)$row['staff_id']
                : ($accountType === 'barber' ? (int)$row['barber_id'] : (int)$row['user_id']);

            $token = bin2hex(random_bytes(24));
            $debugToken = $token;
            $insertStmt = $pdo->prepare(
                "INSERT INTO password_reset_requests (account_type, account_id, email, reset_token, expires_at)
                 VALUES (:account_type, :account_id, :email, :reset_token, NOW() + INTERVAL '30 minutes')"
            );
            $insertStmt->execute([
                ':account_type' => $accountType,
                ':account_id' => $accountId,
                ':email' => $email,
                ':reset_token' => $token,
            ]);

            $resetBaseUrl = trim((string)(getenv('PASSWORD_RESET_BASE_URL') ?: ''));
            $mailFrom = trim((string)(getenv('PASSWORD_RESET_MAIL_FROM') ?: ''));

            if ($resetBaseUrl !== '' && $mailFrom !== '') {
                $resetLink = rtrim($resetBaseUrl, '/') . '?token=' . urlencode($token);
                $subject = 'Password reset request';
                $message = "We received a password reset request for your account.\n\n"
                    . "Open this link to continue:\n"
                    . $resetLink
                    . "\n\nThis link expires in 30 minutes.";
                $headers = 'From: ' . $mailFrom . "\r\n" . 'Content-Type: text/plain; charset=UTF-8';
                @mail($email, $subject, $message, $headers);
            }
        }

        $response = [
            'message' => 'If an account exists for that email, a reset request was recorded. Please check your email or contact support.',
        ];
        $allowDebugToken = in_array(strtolower(trim((string)(getenv('PASSWORD_RESET_DEBUG_TOKEN') ?: ''))), ['1', 'true', 'yes'], true);
        if ($allowDebugToken && $debugToken !== null) {
            $response['resetToken'] = $debugToken;
        }

        json_response($response);
    }

    if ($action === 'verifyResetToken') {
        $token = trim((string)($input['token'] ?? ''));
        if ($token === '') {
            json_response(['error' => 'Reset token is required.'], 422);
        }

        ensure_auth_tables($pdo);
        $request = find_valid_reset_request($pdo, $token);
        if ($request === null) {
            json_response(['error' => 'Invalid or expired reset token.'], 400);
        }

        json_response([
            'message' => 'Reset token is valid.',
            'emailHint' => mask_email((string)$request['email']),
            'expiresAt' => (string)$request['expires_at'],
        ]);
    }

    if ($action === 'resetPassword') {
        $token = trim((string)($input['token'] ?? ''));
        $newPassword = (string)($input['newPassword'] ?? '');
        $confirmPassword = (string)($input['confirmPassword'] ?? '');

        if ($token === '' || $newPassword === '' || $confirmPassword === '') {
            json_response(['error' => 'Token and new passwords are required.'], 422);
        }
        if (strlen($newPassword) < 6) {
            json_response(['error' => 'Password must be at least 6 characters.'], 422);
        }
        if ($newPassword !== $confirmPassword) {
            json_response(['error' => 'Passwords do not match.'], 422);
        }

        ensure_auth_tables($pdo);
        $request = find_valid_reset_request($pdo, $token);
        if ($request === null) {
            json_response(['error' => 'Invalid or expired reset token.'], 400);
        }

        $pdo->beginTransaction();
        try {
            $requestId = (int)$request['request_id'];
            $accountType = (string)$request['account_type'];
            $accountId = (int)$request['account_id'];

            $passwordHash = password_hash($newPassword, PASSWORD_BCRYPT);
            update_account_password($pdo, $accountType, $accountId, $passwordHash);

            $markUsedStmt = $pdo->prepare('UPDATE password_reset_requests SET used_at = NOW() WHERE request_id = :request_id');
            $markUsedStmt->execute([':request_id' => $requestId]);

            $invalidateOthersStmt = $pdo->prepare(
                'UPDATE password_reset_requests
                 SET used_at = NOW()
                 WHERE account_type = :account_type
                   AND account_id = :account_id
                   AND used_at IS NULL
                   AND request_id <> :request_id'
            );
            $invalidateOthersStmt->execute([
                ':account_type' => $accountType,
                ':account_id' => $accountId,
                ':request_id' => $requestId,
            ]);

            $pdo->commit();
        } catch (Throwable $txError) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $txError;
        }

        json_response(['message' => 'Password has been reset successfully. You can now sign in.']);
    }

    if ($action === 'changePassword') {
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $userId = (int)($input['userId'] ?? 0);
        $currentPassword = (string)($input['currentPassword'] ?? '');
        $newPassword = (string)($input['newPassword'] ?? '');
        $confirmPassword = (string)($input['confirmPassword'] ?? '');

        if ($currentPassword === '' || $newPassword === '' || $confirmPassword === '') {
            json_response(['error' => 'Current password, new password, and confirmation are required.'], 422);
        }
        if ($newPassword !== $confirmPassword) {
            json_response(['error' => 'New password and confirmation do not match.'], 422);
        }
        if ($currentPassword === $newPassword) {
            json_response(['error' => 'New password must be different from your current password.'], 422);
        }

        $policyError = validate_password_policy($newPassword);
        if ($policyError !== null) {
            json_response(['error' => $policyError], 422);
        }

        $customer = null;
        if ($userId > 0) {
            $byId = $pdo->prepare(
                'SELECT user_id, email, password_hash, full_name
                 FROM users
                 WHERE user_id = :user_id AND is_active = TRUE
                 LIMIT 1'
            );
            $byId->execute([':user_id' => $userId]);
            $customer = $byId->fetch() ?: null;
        }

        if ($customer === null && $email !== '' && is_valid_email($email)) {
            $byEmail = $pdo->prepare(
                'SELECT user_id, email, password_hash, full_name
                 FROM users
                 WHERE lower(email) = lower(:email) AND is_active = TRUE
                 LIMIT 1'
            );
            $byEmail->execute([':email' => $email]);
            $customer = $byEmail->fetch() ?: null;
        }

        if ($customer === null) {
            json_response(['error' => 'Account not found.'], 404);
        }

        $storedHash = trim((string)($customer['password_hash'] ?? ''));
        $kind = customer_password_kind($storedHash);
        if ($kind === 'oauth') {
            json_response([
                'error' => 'This account uses Google or Facebook sign-in. Use those buttons, or Forgot password to set an email password.',
                'code' => 'OAUTH_ONLY',
            ], 400);
        }
        if ($kind === 'supabase') {
            json_response([
                'error' => 'This account password is managed in Supabase Auth.',
                'code' => 'SUPABASE_PASSWORD',
            ], 400);
        }

        if (!password_verify($currentPassword, $storedHash)) {
            json_response(['error' => 'Current password is incorrect.', 'code' => 'WRONG_PASSWORD'], 401);
        }

        $passwordHash = password_hash($newPassword, PASSWORD_BCRYPT);
        update_account_password($pdo, 'customer', (int)$customer['user_id'], $passwordHash);

        json_response([
            'message' => 'Password updated successfully.',
            'user' => [
                'userID' => (int)$customer['user_id'],
                'email' => (string)$customer['email'],
                'fullName' => (string)($customer['full_name'] ?? ''),
            ],
        ]);
    }

    if ($action === 'checkEmailExists') {
        $email = trim((string)($input['email'] ?? ''));
        if (empty($email) || !is_valid_email($email)) {
            json_response(['exists' => false, 'inPublicUsers' => false, 'inAuth' => false, 'authLookup' => 'skipped', 'providers' => [], 'oauthOnly' => false, 'hasPassword' => false]);
        }

        $pdo = get_db_connection();
        json_response(build_check_email_exists_payload($pdo, $email));
    }

    if ($action === 'resolveAccount') {
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $fullName = sanitize_full_name((string)($input['fullName'] ?? ''), $email);
        if ($email === '' || !is_valid_email($email)) {
            json_response(['error' => 'Invalid email'], 422);
        }

        $account = find_account_by_email($pdo, $email);
        if ($account === null) {
            $sync = sync_auth_to_public_users($email, $fullName);
            if (!$sync['success']) {
                json_response(['error' => $sync['message']], 500);
            }

            $account = find_account_by_email($pdo, $email);
            if ($account === null) {
                json_response(['error' => 'Unable to provision customer account'], 500);
            }
        }

        json_response([
            'accountType' => $account['type'],
            'user' => build_user_payload($account['type'], $account['row']),
            'provisioned' => $account['type'] === 'customer',
        ]);
    }
} catch (PDOException $e) {
    $sqlState = (string)$e->getCode();
    if ($sqlState === '23505') {
        json_response(['error' => 'Email is already in use.'], 409);
    }
    json_response(db_error_response_payload($e), 500);
} catch (Throwable $e) {
    json_response(['error' => 'Unexpected error', 'details' => $e->getMessage()], 500);
}
