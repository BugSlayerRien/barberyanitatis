<?php
// Customer API auth: Supabase access token → public.users.user_id.
// Body userID is never proof of identity.

declare(strict_types=1);

require_once __DIR__ . '/http.php';

class CustomerAuthException extends RuntimeException
{
    public int $httpStatus;

    public function __construct(string $message, int $httpStatus)
    {
        parent::__construct($message);
        $this->httpStatus = $httpStatus;
    }
}

function customer_bearer_token_from_request(): string
{
    $candidates = [
        (string)($_SERVER['HTTP_AUTHORIZATION'] ?? ''),
        (string)($_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? ''),
        (string)($_SERVER['HTTP_X_AUTHORIZATION'] ?? ''),
        (string)($_SERVER['HTTP_X_SUPABASE_ACCESS_TOKEN'] ?? ''),
    ];

    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers)) {
            foreach ($headers as $name => $value) {
                if (strcasecmp((string)$name, 'Authorization') === 0
                    || strcasecmp((string)$name, 'X-Authorization') === 0
                    || strcasecmp((string)$name, 'X-Supabase-Access-Token') === 0
                ) {
                    $candidates[] = (string)$value;
                }
            }
        }
    }

    foreach ($candidates as $header) {
        $header = trim($header);
        if ($header === '') {
            continue;
        }
        if (preg_match('/Bearer\s+(\S+)/i', $header, $matches) === 1) {
            return trim($matches[1]);
        }
        // X-Supabase-Access-Token may be the raw JWT without a Bearer prefix.
        if (substr_count($header, '.') === 2 && !str_contains($header, ' ')) {
            return $header;
        }
    }

    return '';
}

function customer_claimed_user_id(?array $input): int
{
    if ($input === null) {
        return 0;
    }

    return (int)($input['userID'] ?? $input['userId'] ?? 0);
}

function customer_jwt_secret(): string
{
    return trim((string)(getenv('SUPABASE_JWT_SECRET') ?: ($_ENV['SUPABASE_JWT_SECRET'] ?? '')));
}

function customer_b64url_decode(string $data): ?string
{
    $remainder = strlen($data) % 4;
    if ($remainder > 0) {
        $data .= str_repeat('=', 4 - $remainder);
    }

    $decoded = base64_decode(strtr($data, '-_', '+/'), true);

    return $decoded === false ? null : $decoded;
}

/**
 * @return array<string, mixed>|null
 */
function customer_decode_jwt_payload(string $jwt): ?array
{
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) {
        return null;
    }

    $payloadJson = customer_b64url_decode($parts[1]);
    if ($payloadJson === null) {
        return null;
    }

    $payload = json_decode($payloadJson, true);

    return is_array($payload) ? $payload : null;
}

/**
 * @return array<string, mixed>|null
 */
function customer_verify_jwt_hs256(string $jwt, string $secret): ?array
{
    if ($secret === '') {
        return null;
    }

    $parts = explode('.', $jwt);
    if (count($parts) !== 3) {
        return null;
    }

    [$headerB64, $payloadB64, $signatureB64] = $parts;
    $headerJson = customer_b64url_decode($headerB64);
    $payloadJson = customer_b64url_decode($payloadB64);
    $signature = customer_b64url_decode($signatureB64);
    if ($headerJson === null || $payloadJson === null || $signature === null) {
        return null;
    }

    $header = json_decode($headerJson, true);
    $payload = json_decode($payloadJson, true);
    if (!is_array($header) || !is_array($payload)) {
        return null;
    }

    $alg = strtoupper((string)($header['alg'] ?? ''));
    if ($alg !== 'HS256') {
        return null;
    }

    $expected = hash_hmac('sha256', $headerB64 . '.' . $payloadB64, $secret, true);
    if (!hash_equals($expected, $signature)) {
        return null;
    }

    if (!customer_jwt_claims_are_fresh($payload)) {
        return null;
    }

    if (!customer_jwt_role_is_authenticated($payload)) {
        return null;
    }

    return $payload;
}

/**
 * @param array<string, mixed> $payload
 */
function customer_jwt_claims_are_fresh(array $payload): bool
{
    $now = time();
    $skew = 30;

    if (isset($payload['exp']) && (int)$payload['exp'] < ($now - $skew)) {
        return false;
    }
    if (isset($payload['nbf']) && (int)$payload['nbf'] > ($now + $skew)) {
        return false;
    }
    if (isset($payload['iat']) && (int)$payload['iat'] > ($now + $skew)) {
        return false;
    }

    return true;
}

/**
 * Rejects the project anon / service_role JWTs. Customer access tokens use role=authenticated.
 *
 * @param array<string, mixed> $payload
 */
function customer_jwt_role_is_authenticated(array $payload): bool
{
    $role = strtolower(trim((string)($payload['role'] ?? '')));
    $aud = strtolower(trim((string)($payload['aud'] ?? '')));

    return $role === 'authenticated' || $aud === 'authenticated';
}

function customer_is_usable_email(string $email): bool
{
    $email = strtolower(trim($email));
    if ($email === '' || str_contains($email, ' ')) {
        return false;
    }
    $parts = explode('@', $email);
    if (count($parts) !== 2) {
        return false;
    }
    [$local, $domain] = $parts;

    return $local !== '' && $domain !== '' && str_contains($domain, '.');
}

/**
 * @param array<string, mixed> $claims
 */
function customer_email_from_claims(array $claims): string
{
    $email = strtolower(trim((string)($claims['email'] ?? '')));
    if (customer_is_usable_email($email)) {
        return $email;
    }

    $metadata = $claims['user_metadata'] ?? null;
    if (is_array($metadata)) {
        $metaEmail = strtolower(trim((string)($metadata['email'] ?? '')));
        if (customer_is_usable_email($metaEmail)) {
            return $metaEmail;
        }
    }

    return '';
}

/**
 * Live check against GoTrue when the JWT secret is missing or the token is not HS256.
 *
 * @return array<string, mixed>|null
 */
function customer_introspect_supabase_user(string $accessToken): ?array
{
    $baseUrl = rtrim(trim((string)(getenv('SUPABASE_URL') ?: ($_ENV['SUPABASE_URL'] ?? ''))), '/');
    $anonKey = trim((string)(getenv('SUPABASE_ANON_KEY') ?: ($_ENV['SUPABASE_ANON_KEY'] ?? '')));
    if ($baseUrl === '' || $anonKey === '' || $accessToken === '') {
        return null;
    }

    $ch = curl_init($baseUrl . '/auth/v1/user');
    if ($ch === false) {
        return null;
    }

    $headers = [
        'Authorization: Bearer ' . $accessToken,
        'apikey: ' . $anonKey,
        'Content-Type: application/json',
    ];

    $options = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_TIMEOUT => 8,
        CURLOPT_CONNECTTIMEOUT => 5,
    ];
    foreach (api_curl_ssl_options() as $opt => $value) {
        $options[$opt] = $value;
    }
    curl_setopt_array($ch, $options);

    $body = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($status !== 200 || !is_string($body) || $body === '') {
        return null;
    }

    $data = json_decode($body, true);
    if (!is_array($data)) {
        return null;
    }

    $email = strtolower(trim((string)($data['email'] ?? '')));
    if ($email === '' && isset($data['user_metadata']) && is_array($data['user_metadata'])) {
        $email = strtolower(trim((string)($data['user_metadata']['email'] ?? '')));
    }
    if (!customer_is_usable_email($email)) {
        return null;
    }

    return [
        'sub' => (string)($data['id'] ?? ''),
        'email' => $email,
        'role' => 'authenticated',
        'aud' => 'authenticated',
        'user_metadata' => is_array($data['user_metadata'] ?? null) ? $data['user_metadata'] : [],
    ];
}

/**
 * @return array<string, mixed>
 */
function customer_verify_supabase_access_token(string $accessToken): array
{
    if ($accessToken === '') {
        throw new CustomerAuthException('Customer authentication required.', 401);
    }

    $secret = customer_jwt_secret();
    $headerJson = customer_b64url_decode((string)(explode('.', $accessToken)[0] ?? ''));
    $header = is_string($headerJson) ? json_decode($headerJson, true) : null;
    $alg = is_array($header) ? strtoupper((string)($header['alg'] ?? '')) : '';

    if ($secret !== '' && $alg === 'HS256') {
        $claims = customer_verify_jwt_hs256($accessToken, $secret);
        if ($claims !== null) {
            return $claims;
        }
        throw new CustomerAuthException('Invalid or expired customer session.', 401);
    }

    // Secret not configured, or asymmetric JWT (ES256/RS256): ask GoTrue.
    $claims = customer_introspect_supabase_user($accessToken);
    if ($claims === null) {
        throw new CustomerAuthException('Invalid or expired customer session.', 401);
    }

    return $claims;
}

/**
 * @param array<string, mixed>|null $input
 * @return array{user_id: int, email: string, supabase_sub: string}
 */
function resolve_authenticated_customer(PDO $pdo, ?array $input = null): array
{
    $token = customer_bearer_token_from_request();
    if ($token === '') {
        throw new CustomerAuthException('Customer authentication required.', 401);
    }

    $claims = customer_verify_supabase_access_token($token);
    $email = customer_email_from_claims($claims);
    if ($email === '') {
        throw new CustomerAuthException('Invalid or expired customer session.', 401);
    }

    $stmt = $pdo->prepare(
        'SELECT user_id, email, is_active
         FROM users
         WHERE lower(email) = lower(:email)
         LIMIT 1'
    );
    $stmt->execute([':email' => $email]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        throw new CustomerAuthException('Customer account was not found for this session.', 403);
    }

    $active = $row['is_active'] === true
        || $row['is_active'] === 't'
        || (int)$row['is_active'] === 1;
    if (!$active) {
        throw new CustomerAuthException('Customer account is inactive.', 403);
    }

    $userId = (int)$row['user_id'];
    $claimed = customer_claimed_user_id($input);
    if ($claimed > 0 && $claimed !== $userId) {
        throw new CustomerAuthException('You are not authorized to access this account.', 403);
    }

    return [
        'user_id' => $userId,
        'email' => strtolower(trim((string)$row['email'])),
        'supabase_sub' => (string)($claims['sub'] ?? ''),
    ];
}

/**
 * @param array<string, mixed>|null $input
 * @return array{user_id: int, email: string, supabase_sub: string}
 */
function require_customer(PDO $pdo, ?array $input = null): array
{
    try {
        return resolve_authenticated_customer($pdo, $input);
    } catch (CustomerAuthException $e) {
        json_response(['error' => $e->getMessage()], $e->httpStatus);
    }
}

/**
 * Walk-in kiosk / guest: no token and no claimed userID → null.
 * Any claimed userID or presented token uses the same identity rules as require_customer().
 *
 * @param array<string, mixed>|null $input
 * @return array{user_id: int, email: string, supabase_sub: string}|null
 */
function resolve_customer_or_guest(PDO $pdo, ?array $input = null): ?array
{
    $token = customer_bearer_token_from_request();
    $claimed = customer_claimed_user_id($input);
    if ($token === '' && $claimed <= 0) {
        return null;
    }

    return resolve_authenticated_customer($pdo, $input);
}

/**
 * @param array<string, mixed>|null $input
 * @return array{user_id: int, email: string, supabase_sub: string}|null
 */
function require_customer_or_guest(PDO $pdo, ?array $input = null): ?array
{
    try {
        return resolve_customer_or_guest($pdo, $input);
    } catch (CustomerAuthException $e) {
        json_response(['error' => $e->getMessage()], $e->httpStatus);
    }
}

function assert_scan_session_access(PDO $pdo, string $scanSessionId, ?int $customerUserId): void
{
    if ($scanSessionId === '') {
        return;
    }

    $stmt = $pdo->prepare(
        'SELECT user_id
         FROM face_scan_sessions
         WHERE scan_session_id = :scan_session_id
         LIMIT 1'
    );
    $stmt->execute([':scan_session_id' => $scanSessionId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }

    $ownerId = (int)($row['user_id'] ?? 0);
    if ($ownerId <= 0) {
        return;
    }
    if ($customerUserId === null || $customerUserId <= 0) {
        throw new CustomerAuthException('Customer authentication required.', 401);
    }
    if ($ownerId !== $customerUserId) {
        throw new CustomerAuthException('You are not authorized to access this scan.', 403);
    }
}

function require_scan_session_access(PDO $pdo, string $scanSessionId, ?int $customerUserId): void
{
    try {
        assert_scan_session_access($pdo, $scanSessionId, $customerUserId);
    } catch (CustomerAuthException $e) {
        json_response(['error' => $e->getMessage()], $e->httpStatus);
    }
}

/**
 * @return array<string, mixed>
 */
function assert_customer_owns_appointment(PDO $pdo, int $customerUserId, int $appointmentId): array
{
    if ($appointmentId <= 0) {
        throw new CustomerAuthException('Invalid appointmentID', 422);
    }

    $stmt = $pdo->prepare(
        'SELECT appointment_id, user_id, barber_id, booking_code, status,
                appointment_date, start_time, end_time, booking_group_id
         FROM appointments
         WHERE appointment_id = :appointment_id
         LIMIT 1'
    );
    $stmt->execute([':appointment_id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        throw new CustomerAuthException('Appointment not found', 404);
    }
    if ((int)$row['user_id'] !== $customerUserId) {
        throw new CustomerAuthException('You are not authorized to access this appointment.', 403);
    }

    return $row;
}

/**
 * @return array<string, mixed>
 */
function require_customer_owns_appointment(PDO $pdo, int $customerUserId, int $appointmentId): array
{
    try {
        return assert_customer_owns_appointment($pdo, $customerUserId, $appointmentId);
    } catch (CustomerAuthException $e) {
        json_response(['error' => $e->getMessage()], $e->httpStatus);
    }
}

function assert_customer_owns_notification(PDO $pdo, int $customerUserId, int $notificationId): void
{
    if ($notificationId <= 0) {
        throw new CustomerAuthException('Invalid notificationID', 422);
    }

    $stmt = $pdo->prepare(
        'SELECT notification_id, recipient_type, recipient_id
         FROM notifications
         WHERE notification_id = :notification_id
         LIMIT 1'
    );
    $stmt->execute([':notification_id' => $notificationId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        throw new CustomerAuthException('Notification not found', 404);
    }

    $type = strtolower(trim((string)$row['recipient_type']));
    if ($type !== 'user' || (int)$row['recipient_id'] !== $customerUserId) {
        throw new CustomerAuthException('You are not authorized to access this notification.', 403);
    }
}

function require_customer_owns_notification(PDO $pdo, int $customerUserId, int $notificationId): void
{
    try {
        assert_customer_owns_notification($pdo, $customerUserId, $notificationId);
    } catch (CustomerAuthException $e) {
        json_response(['error' => $e->getMessage()], $e->httpStatus);
    }
}
