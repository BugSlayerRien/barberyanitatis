<?php
// Basic auth API (register/login)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if ($action !== 'register' && $action !== 'login') {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'register') {
        $fullName = trim((string)($input['fullName'] ?? ''));
        $email = trim((string)($input['email'] ?? ''));
        $password = (string)($input['password'] ?? '');
        $phone = trim((string)($input['phone'] ?? ''));
        $roleName = trim((string)($input['roleName'] ?? 'Customer'));

        if ($fullName === '' || $email === '' || $password === '') {
            json_response(['error' => 'Missing required fields'], 422);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);

        $pdo->beginTransaction();

        $stmt = $pdo->prepare('INSERT INTO users (fullName, email, passwordHash, phone) VALUES (:fullName, :email, :passwordHash, :phone)');
        $stmt->execute([
            ':fullName' => $fullName,
            ':email' => $email,
            ':passwordHash' => $passwordHash,
            ':phone' => $phone !== '' ? $phone : null,
        ]);

        $userId = (int)$pdo->lastInsertId();

        $roleStmt = $pdo->prepare('SELECT roleID FROM roles WHERE roleName = :roleName');
        $roleStmt->execute([':roleName' => $roleName]);
        $roleId = (int)($roleStmt->fetchColumn() ?: 0);

        if ($roleId === 0) {
            $insertRole = $pdo->prepare('INSERT INTO roles (roleName) VALUES (:roleName)');
            $insertRole->execute([':roleName' => $roleName]);
            $roleId = (int)$pdo->lastInsertId();
        }

        $linkStmt = $pdo->prepare('INSERT INTO userRoles (userID, roleID) VALUES (:userID, :roleID)');
        $linkStmt->execute([':userID' => $userId, ':roleID' => $roleId]);

        $pdo->commit();

        json_response([
            'message' => 'Registration successful',
            'user' => [
                'userID' => $userId,
                'fullName' => $fullName,
                'email' => $email,
                'phone' => $phone,
                'role' => $roleName,
            ],
        ], 201);
    }

    if ($action === 'login') {
        $email = trim((string)($input['email'] ?? ''));
        $password = (string)($input['password'] ?? '');

        if ($email === '' || $password === '') {
            json_response(['error' => 'Missing email or password'], 422);
        }

        $stmt = $pdo->prepare('SELECT userID, fullName, email, passwordHash FROM users WHERE email = :email AND isActive = 1');
        $stmt->execute([':email' => $email]);
        $user = $stmt->fetch();

        if (!$user || !password_verify($password, (string)$user['passwordHash'])) {
            json_response(['error' => 'Invalid credentials'], 401);
        }

        $rolesStmt = $pdo->prepare('SELECT r.roleName FROM userRoles ur JOIN roles r ON ur.roleID = r.roleID WHERE ur.userID = :userID');
        $rolesStmt->execute([':userID' => $user['userID']]);
        $roles = $rolesStmt->fetchAll();

        json_response([
            'message' => 'Login successful',
            'user' => [
                'userID' => (int)$user['userID'],
                'fullName' => $user['fullName'],
                'email' => $user['email'],
                'roles' => array_map(fn($row) => $row['roleName'], $roles),
            ],
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
