<?php
// Staff profile API (admin/receptionist self profile update)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

if ($action !== 'updateProfile') {
    json_response(['error' => 'Invalid action'], 400);
}

$pdo = get_db_connection();
// Had no gate at all: any caller could rewrite any staff member's name,
// email or role by passing their id. A receptionist may edit only their own
// profile; an admin may edit anyone (that is what admin_users.php is for).
$actor = require_staff($pdo);

$staffId = (int)($input['staffID'] ?? 0);
if (strtolower($actor['role']) !== 'admin' && $staffId !== (int)$actor['staff_id']) {
    json_response(['error' => 'You can only update your own profile.'], 403);
}
$fullName = trim((string)($input['fullName'] ?? ''));
$email = trim((string)($input['email'] ?? ''));
$role = strtolower(trim((string)($input['role'] ?? '')));

if ($staffId <= 0 || $fullName === '' || $email === '') {
    json_response(['error' => 'Missing required fields'], 422);
}

if (!in_array($role, ['admin', 'receptionist'], true)) {
    json_response(['error' => 'Invalid role'], 422);
}

try {
    $pdo = get_db_connection();

    $existingStmt = $pdo->prepare(
        'SELECT staff_id, full_name, email, role, is_active
         FROM staff_users
         WHERE staff_id = :id'
    );
    $existingStmt->execute([':id' => $staffId]);
    $existing = $existingStmt->fetch();

    if (!$existing) {
        json_response(['error' => 'Staff account not found'], 404);
    }

    if ((int)$existing['is_active'] !== 1) {
        json_response(['error' => 'Inactive account cannot be updated'], 403);
    }

    if (strtolower((string)$existing['role']) !== $role) {
        json_response(['error' => 'Role mismatch'], 403);
    }

    $updateStmt = $pdo->prepare(
        'UPDATE staff_users
         SET full_name = :full_name, email = :email
         WHERE staff_id = :id
         RETURNING staff_id, full_name, email, role'
    );
    $updateStmt->execute([
        ':full_name' => $fullName,
        ':email' => $email,
        ':id' => $staffId,
    ]);

    $updated = $updateStmt->fetch();

    $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
         VALUES ('Admin', 0, 'System', 'Profile updated', :message)"
    )->execute([':message' => $fullName . ' updated profile details']);

    json_response([
        'message' => 'Profile updated successfully',
        'user' => [
            'userID' => (int)$updated['staff_id'],
            'fullName' => $updated['full_name'],
            'email' => $updated['email'],
            'roles' => [strtolower((string)$updated['role'])],
        ],
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
