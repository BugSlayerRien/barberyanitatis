<?php
// Admin users API (customers, barbers, staff)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

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
            $stmt = $pdo->prepare("SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role FROM barbers WHERE barber_id = :id LIMIT 1");
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
        "SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role
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
        return $updated;
    }

    if ($type === 'barber') {
        $specialty = trim((string)($input['specialty'] ?? ''));
        $yearsExperience = (int)($input['yearsExperience'] ?? 0);
        $rating = (float)($input['rating'] ?? 5);
        $stmt = $pdo->prepare(
            "UPDATE barbers
             SET full_name = :full_name,
                 email = :email,
                 specialty = :specialty,
                 years_experience = :years_experience,
                 rating = :rating,
                 is_active = :is_active
             WHERE barber_id = :id
             RETURNING barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at, 'barber' AS role"
        );
        $stmt->execute([
            ':full_name' => $fullName,
            ':email' => $email,
            ':specialty' => $specialty !== '' ? $specialty : null,
            ':years_experience' => max(0, $yearsExperience),
            ':rating' => max(0, min(5, $rating)),
            ':is_active' => $isActive,
            ':id' => $id,
        ]);
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
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        respond_accounts($pdo);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = strtolower(trim((string)($input['action'] ?? '')));

    if (!in_array($action, ['update', 'delete', 'assignPortalRole', 'removePortalRole'], true)) {
        json_response(['error' => 'Invalid action'], 400);
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
