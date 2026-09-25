<?php
// Admin users API (customers, barbers, staff)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/auth_sync.php';
require_once __DIR__ . '/supabase_admin_auth.php';

function normalize_bool(mixed $value): bool
{
    return filter_var($value, FILTER_VALIDATE_BOOL, FILTER_NULL_ON_FAILURE) ?? ((int)$value === 1);
}

function fetch_account_row(PDO $pdo, string $type, int $id): ?array
{
    return match ($type) {
        'customer' => (function () use ($pdo, $id) {
            $stmt = $pdo->prepare("SELECT user_id, full_name, email, phone, is_active, created_at, 'customer' AS role FROM users WHERE user_id = :id LIMIT 1");
            $stmt->execute([':id' => $id]);
            $row = $stmt->fetch();
            return $row ?: null;
        })(),
        'barber' => (function () use ($pdo, $id) {
            $stmt = $pdo->prepare("SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, barber_channel, 'barber' AS role FROM barbers WHERE barber_id = :id LIMIT 1");
            $stmt->execute([':id' => $id]);
            $row = $stmt->fetch();
            return $row ?: null;
        })(),
        'staff' => (function () use ($pdo, $id) {
            $stmt = $pdo->prepare('SELECT staff_id, full_name, email, role, is_active, created_at FROM staff_users WHERE staff_id = :id LIMIT 1');
            $stmt->execute([':id' => $id]);
            $row = $stmt->fetch();
            return $row ?: null;
        })(),
        default => null,
    };
}

function fetch_accounts(PDO $pdo): array
{
    $customers = $pdo->query(
        "SELECT user_id, full_name, email, phone, is_active, created_at, 'customer' AS role
         FROM users
         ORDER BY full_name"
    )->fetchAll();

    $barbers = $pdo->query(
        "SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, barber_channel, 'barber' AS role
         FROM barbers
         ORDER BY full_name"
    )->fetchAll();

    $staffStmt = $pdo->prepare(
        'SELECT staff_id, full_name, email, role, is_active, created_at
         FROM staff_users
         WHERE role = :role
         ORDER BY full_name'
    );

    $staffStmt->execute([':role' => 'Receptionist']);
    $receptionists = $staffStmt->fetchAll();

    $staffStmt->execute([':role' => 'Admin']);
    $admins = $staffStmt->fetchAll();

    return [
        'customers' => $customers,
        'barbers' => $barbers,
        'receptionists' => $receptionists,
        'admins' => $admins,
    ];
}

function respond_accounts(PDO $pdo): void
{
    json_response(fetch_accounts($pdo));
}

function require_account_payload(array $input): array
{
    $type = strtolower(trim((string)($input['type'] ?? '')));
    $id = (int)($input['id'] ?? 0);

    if (!in_array($type, ['customer', 'barber', 'staff'], true) || $id <= 0) {
        json_response(['error' => 'Invalid account target'], 422);
    }

    return [$type, $id];
}

function generate_barber_code(PDO $pdo, int $userId): string
{
    $preferred = 'BRB' . str_pad((string)max(1, $userId), 4, '0', STR_PAD_LEFT);
    $check = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE barber_code = :barber_code');
    $check->execute([':barber_code' => $preferred]);
    if ((int)$check->fetchColumn() === 0) {
        return $preferred;
    }

    for ($i = 900; $i < 10000; $i++) {
        $candidate = 'BRB' . $i;
        $check->execute([':barber_code' => $candidate]);
        if ((int)$check->fetchColumn() === 0) {
            return $candidate;
        }
    }

    return 'BRB' . time();
}

function promote_customer_to_barber(PDO $pdo, int $userId, string $fullName, string $email): array
{
    $normalizedEmail = strtolower(trim($email));
    if ($normalizedEmail === '') {
        json_response(['error' => 'Email is required to promote a barber account'], 422);
    }

    $existingStmt = $pdo->prepare(
        'SELECT barber_id, barber_code, full_name, email, specialty, years_experience, rating, is_active, created_at
         FROM barbers
         WHERE lower(email) = lower(:email)
         LIMIT 1'
    );
    $existingStmt->execute([':email' => $normalizedEmail]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
        $reactivate = $pdo->prepare(
            "UPDATE barbers
             SET full_name = :full_name,
                 is_active = TRUE
             WHERE barber_id = :barber_id
             RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role"
        );
        $reactivate->execute([
            ':full_name' => $fullName,
            ':barber_id' => (int)$existing['barber_id'],
        ]);
        $updated = $reactivate->fetch(PDO::FETCH_ASSOC);
        audit_log($pdo, 'USER_PROMOTE_BARBER', 'barbers', (string)$existing['barber_id'], $existing, $updated, null);
        return $updated ?: $existing;
    }

    $barberCode = generate_barber_code($pdo, $userId);
    $insert = $pdo->prepare(
        "INSERT INTO barbers (barber_code, full_name, email, password_hash, specialty, years_experience, rating, is_active)
         VALUES (:barber_code, :full_name, :email, :password_hash, :specialty, :years_experience, 5.00, TRUE)
         RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role"
    );
    $insert->execute([
        ':barber_code' => $barberCode,
        ':password_hash' => USER_PASSWORD_HASH_SUPABASE,
        ':full_name' => $fullName,
        ':email' => $normalizedEmail,
        ':specialty' => 'General',
        ':years_experience' => 1,
    ]);
    $created = $insert->fetch(PDO::FETCH_ASSOC);
    if (!$created) {
        json_response(['error' => 'Unable to create barber account'], 500);
    }

    audit_log($pdo, 'USER_PROMOTE_BARBER', 'barbers', (string)$created['barber_id'], null, $created, null);
    return $created;
}

function update_account(PDO $pdo, string $type, int $id, array $input): array
{
    $existing = fetch_account_row($pdo, $type, $id);
    if (!$existing) {
        json_response(['error' => 'Account not found'], 404);
    }

    $fullName = trim((string)($input['fullName'] ?? ''));
    $email = trim((string)($input['email'] ?? ''));
    $isActive = normalize_bool($input['isActive'] ?? true);

    if ($fullName === '' || $email === '') {
        json_response(['error' => 'Name and email are required'], 422);
    }

    if ($type === 'customer') {
        $phone = trim((string)($input['phone'] ?? ''));
        $stmt = $pdo->prepare(
              "UPDATE users
             SET full_name = :full_name, email = :email, phone = :phone, is_active = :is_active, updated_at = NOW()
             WHERE user_id = :id
               RETURNING user_id, full_name, email, phone, is_active, created_at, 'customer' AS role"
        );
        $stmt->execute([
            ':full_name' => $fullName,
            ':email' => $email,
            ':phone' => $phone !== '' ? $phone : null,
            ':is_active' => $isActive,
            ':id' => $id,
        ]);
        $updated = $stmt->fetch();
        if (!$updated) {
            json_response(['error' => 'Unable to update customer account'], 500);
        }
        audit_log($pdo, 'USER_UPDATE', 'users', (string)$id, $existing, $updated, null);

        $appRole = strtolower(trim((string)($input['appRole'] ?? 'customer')));
        if ($appRole === 'barber') {
            promote_customer_to_barber($pdo, $id, $fullName, $email);
        }

        return $updated;
    }

    if ($type === 'barber') {
        ensure_barber_channel_column($pdo);
        $specialty = trim((string)($input['specialty'] ?? ''));
        $yearsExperience = (int)($input['yearsExperience'] ?? 0);
        $rating = (float)($input['rating'] ?? 5);
        $channel = normalize_barber_channel($input['barberChannel'] ?? null);

        $sql = "UPDATE barbers
             SET full_name = :full_name,
                 email = :email,
                 specialty = :specialty,
                 years_experience = :years_experience,
                 rating = :rating,
                 is_active = :is_active";
        $params = [
            ':full_name' => $fullName,
            ':email' => $email,
            ':specialty' => $specialty !== '' ? $specialty : null,
            ':years_experience' => max(0, $yearsExperience),
            ':rating' => max(0, min(5, $rating)),
            ':is_active' => $isActive,
            ':id' => $id,
        ];
        if ($channel !== null) {
            $sql .= ", barber_channel = :barber_channel";
            $params[':barber_channel'] = $channel;
        }
        $sql .= " WHERE barber_id = :id
             RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, barber_channel, 'barber' AS role";

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $updated = $stmt->fetch();
        if (!$updated) {
            json_response(['error' => 'Unable to update barber account'], 500);
        }
        audit_log($pdo, 'USER_UPDATE', 'barbers', (string)$id, $existing, $updated, null);
        return $updated;
    }

    $role = strtolower(trim((string)($input['role'] ?? '')));
    if (!in_array($role, ['admin', 'receptionist'], true)) {
        json_response(['error' => 'Role must be Admin or Receptionist'], 422);
    }

    $stmt = $pdo->prepare(
        'UPDATE staff_users
         SET full_name = :full_name, email = :email, role = :role, is_active = :is_active, updated_at = NOW()
         WHERE staff_id = :id
         RETURNING staff_id, full_name, email, role, is_active, created_at'
    );
    $stmt->execute([
        ':full_name' => $fullName,
        ':email' => $email,
        ':role' => ucfirst($role),
        ':is_active' => $isActive,
        ':id' => $id,
    ]);
    $updated = $stmt->fetch();
    if (!$updated) {
        json_response(['error' => 'Unable to update staff account'], 500);
    }
    audit_log($pdo, 'USER_UPDATE', 'staff_users', (string)$id, $existing, $updated, null);
    return $updated;
}

function upsert_portal_staff(PDO $pdo, string $email, string $fullName, string $role, bool $isActive = true): array
{
    $normalizedRole = ucfirst(strtolower(trim($role)));
    if (!in_array($normalizedRole, ['Admin', 'Receptionist'], true)) {
        json_response(['error' => 'Portal role must be Admin or Receptionist'], 422);
    }

    $normalizedEmail = strtolower(trim($email));
    if ($normalizedEmail === '' || $fullName === '') {
        json_response(['error' => 'Name and email are required'], 422);
    }

    $existingStmt = $pdo->prepare(
        'SELECT staff_id, full_name, email, role, is_active, created_at
         FROM staff_users
         WHERE lower(email) = lower(:email)
         LIMIT 1'
    );
    $existingStmt->execute([':email' => $normalizedEmail]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);

    if ($existing) {
        $update = $pdo->prepare(
            'UPDATE staff_users
             SET full_name = :full_name,
                 role = :role,
                 is_active = :is_active,
                 updated_at = NOW()
             WHERE staff_id = :staff_id
             RETURNING staff_id, full_name, email, role, is_active, created_at'
        );
        $update->execute([
            ':full_name' => $fullName,
            ':role' => $normalizedRole,
            ':is_active' => $isActive,
            ':staff_id' => (int)$existing['staff_id'],
        ]);
        $updated = $update->fetch(PDO::FETCH_ASSOC);
        audit_log($pdo, 'USER_ROLE_UPDATE', 'staff_users', (string)$existing['staff_id'], $existing, $updated, null);
        return $updated ?: $existing;
    }

    $defaultPassword = password_hash('ChangeMe123!', PASSWORD_BCRYPT);
    $insert = $pdo->prepare(
        'INSERT INTO staff_users (email, password_hash, full_name, role, is_active)
         VALUES (:email, :password_hash, :full_name, :role, :is_active)
         RETURNING staff_id, full_name, email, role, is_active, created_at'
    );
    $insert->execute([
        ':email' => $normalizedEmail,
        ':password_hash' => $defaultPassword,
        ':full_name' => $fullName,
        ':role' => $normalizedRole,
        ':is_active' => $isActive,
    ]);
    $created = $insert->fetch(PDO::FETCH_ASSOC);
    if (!$created) {
        json_response(['error' => 'Unable to assign portal role'], 500);
    }

    audit_log($pdo, 'USER_ROLE_ASSIGN', 'staff_users', (string)$created['staff_id'], null, $created, null);
    return $created;
}

function remove_portal_staff(PDO $pdo, string $email): void
{
    $normalizedEmail = strtolower(trim($email));
    if ($normalizedEmail === '') {
        return;
    }

    $existingStmt = $pdo->prepare(
        'SELECT staff_id, full_name, email, role, is_active, created_at
         FROM staff_users
         WHERE lower(email) = lower(:email)
         LIMIT 1'
    );
    $existingStmt->execute([':email' => $normalizedEmail]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);
    if (!$existing) {
        return;
    }

    $update = $pdo->prepare(
        'UPDATE staff_users
         SET is_active = FALSE, updated_at = NOW()
         WHERE staff_id = :staff_id
         RETURNING staff_id, full_name, email, role, is_active, created_at'
    );
    $update->execute([':staff_id' => (int)$existing['staff_id']]);
    $updated = $update->fetch(PDO::FETCH_ASSOC);
    audit_log($pdo, 'USER_ROLE_REMOVE', 'staff_users', (string)$existing['staff_id'], $existing, $updated, null);
}

function assert_email_unique_across_tables(PDO $pdo, string $email): void
{
    $e = strtolower(trim($email));
    if ($e === '') {
        json_response(['error' => 'Email is required'], 422);
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
            json_response(['error' => 'That email is already in use'], 422);
        }
    }
}

function create_account(PDO $pdo, array $input): array
{
    $kind = strtolower(trim((string)($input['accountKind'] ?? '')));
    $fullName = trim((string)($input['fullName'] ?? ''));
    $email = strtolower(trim((string)($input['email'] ?? '')));
    $password = (string)($input['password'] ?? '');

    if ($fullName === '' || $email === '' || strlen($password) < 8) {
        json_response(['error' => 'Full name, email, and password (8+ characters) are required'], 422);
    }

    assert_email_unique_across_tables($pdo, $email);
    $hash = password_hash($password, PASSWORD_BCRYPT);

    if ($kind === 'barber') {
        $authEnsure = supabase_admin_ensure_user($email, $password, $fullName);
        if (!$authEnsure['ok'] && ($authEnsure['error'] ?? '') !== 'not_configured') {
            json_response([
                'error' => 'Could not create the barber login in Supabase Auth. Use an email that already has a customer account, or try again.',
            ], 502);
        }
        $hash = USER_PASSWORD_HASH_SUPABASE;
    }

    if ($kind === 'customer') {
        $phone = trim((string)($input['phone'] ?? ''));
        $stmt = $pdo->prepare(
            "INSERT INTO users (email, password_hash, full_name, phone, is_active)
             VALUES (:email, :password_hash, :full_name, :phone, TRUE)
             RETURNING user_id, full_name, email, phone, is_active, created_at, 'customer' AS role"
        );
        $stmt->execute([
            ':email' => $email,
            ':password_hash' => $hash,
            ':full_name' => $fullName,
            ':phone' => $phone !== '' ? $phone : null,
        ]);
        $created = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$created) {
            json_response(['error' => 'Unable to create customer'], 500);
        }
        audit_log($pdo, 'USER_CREATE', 'users', (string)$created['user_id'], null, $created, null);

        return $created;
    }

    if ($kind === 'barber') {
        ensure_barber_channel_column($pdo);
        $channel = normalize_barber_channel($input['barberChannel'] ?? 'appointment') ?? 'appointment';
        $specialty = trim((string)($input['specialty'] ?? ''));
        if ($specialty === '') {
            $specialty = 'General';
        }
        $years = max(0, (int)($input['yearsExperience'] ?? 1));
        $barberCode = generate_barber_code($pdo, 1);
        $stmt = $pdo->prepare(
            "INSERT INTO barbers (barber_code, full_name, email, password_hash, specialty, years_experience, rating, barber_channel, is_active)
             VALUES (:barber_code, :full_name, :email, :password_hash, :specialty, :years_experience, 5.00, :barber_channel, TRUE)
             RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, barber_channel, 'barber' AS role"
        );
        $stmt->execute([
            ':barber_code' => $barberCode,
            ':full_name' => $fullName,
            ':email' => $email,
            ':password_hash' => $hash,
            ':specialty' => $specialty,
            ':years_experience' => $years,
            ':barber_channel' => $channel,
        ]);
        $created = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$created) {
            json_response(['error' => 'Unable to create barber'], 500);
        }
        audit_log($pdo, 'USER_CREATE', 'barbers', (string)$created['barber_id'], null, $created, null);

        return $created;
    }

    if ($kind === 'staff') {
        $role = ucfirst(strtolower(trim((string)($input['role'] ?? 'Receptionist'))));
        if (!in_array($role, ['Admin', 'Receptionist'], true)) {
            json_response(['error' => 'Staff role must be Admin or Receptionist'], 422);
        }

        $stmt = $pdo->prepare(
            "INSERT INTO staff_users (email, password_hash, full_name, role, is_active)
             VALUES (:email, :password_hash, :full_name, :role, TRUE)
             RETURNING staff_id, full_name, email, role, is_active, created_at"
        );
        $stmt->execute([
            ':email' => $email,
            ':password_hash' => $hash,
            ':full_name' => $fullName,
            ':role' => $role,
        ]);
        $created = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$created) {
            json_response(['error' => 'Unable to create staff user'], 500);
        }
        audit_log($pdo, 'USER_CREATE', 'staff_users', (string)$created['staff_id'], null, $created, null);

        return $created;
    }

    json_response(['error' => 'accountKind must be customer, barber, or staff'], 422);
}

function delete_account(PDO $pdo, string $type, int $id): array
{
    $existing = fetch_account_row($pdo, $type, $id);
    if (!$existing) {
        json_response(['error' => 'Account not found'], 404);
    }

    if ($type === 'customer') {
        $stmt = $pdo->prepare("UPDATE users SET is_active = FALSE, updated_at = NOW() WHERE user_id = :id RETURNING user_id, full_name, email, phone, is_active, created_at, 'customer' AS role");
        $stmt->execute([':id' => $id]);
        $updated = $stmt->fetch();
        audit_log($pdo, 'USER_DELETE', 'users', (string)$id, $existing, $updated, null);
        return $updated ?: $existing;
    }

    if ($type === 'barber') {
        $stmt = $pdo->prepare("UPDATE barbers SET is_active = FALSE WHERE barber_id = :id RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role");
        $stmt->execute([':id' => $id]);
        $updated = $stmt->fetch();
        audit_log($pdo, 'USER_DELETE', 'barbers', (string)$id, $existing, $updated, null);
        return $updated ?: $existing;
    }

    $stmt = $pdo->prepare('UPDATE staff_users SET is_active = FALSE, updated_at = NOW() WHERE staff_id = :id RETURNING staff_id, full_name, email, role, is_active, created_at');
    $stmt->execute([':id' => $id]);
    $updated = $stmt->fetch();
    audit_log($pdo, 'USER_DELETE', 'staff_users', (string)$id, $existing, $updated, null);
    return $updated ?: $existing;
}

try {
    $pdo = get_db_connection();
    ensure_barber_channel_column($pdo);
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        respond_accounts($pdo);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = strtolower(trim((string)($input['action'] ?? '')));

    if (!in_array($action, ['update', 'delete', 'assignPortalRole', 'removePortalRole', 'create'], true)) {
        json_response(['error' => 'Invalid action'], 400);
    }

    if ($action === 'create') {
        $record = create_account($pdo, $input);
        json_response(['message' => 'Account created successfully', 'record' => $record], 201);
    }

    if ($action === 'assignPortalRole') {
        $result = upsert_portal_staff(
            $pdo,
            (string)($input['email'] ?? ''),
            trim((string)($input['fullName'] ?? '')),
            (string)($input['role'] ?? ''),
            normalize_bool($input['isActive'] ?? true)
        );
        json_response([
            'message' => 'Portal role assigned successfully',
            'record' => $result,
        ]);
    }

    if ($action === 'removePortalRole') {
        remove_portal_staff($pdo, (string)($input['email'] ?? ''));
        json_response(['message' => 'Portal role removed successfully']);
    }

    [$type, $id] = require_account_payload($input);

    $result = $action === 'delete'
        ? delete_account($pdo, $type, $id)
        : update_account($pdo, $type, $id, $input);

    json_response([
        'message' => $action === 'delete' ? 'Account deactivated successfully' : 'Account updated successfully',
        'record' => $result,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
