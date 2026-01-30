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
        $gender = trim((string)($input['gender'] ?? 'Male'));

        if ($fullName === '' || $email === '' || $password === '') {
            json_response(['error' => 'Missing required fields'], 422);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);

        $stmt = $pdo->prepare(
            'INSERT INTO users (email, password_hash, full_name, phone, gender)
             VALUES (:email, :password_hash, :full_name, :phone, :gender)'
        );
        $stmt->execute([
            ':email' => $email,
            ':password_hash' => $passwordHash,
            ':full_name' => $fullName,
            ':phone' => $phone !== '' ? $phone : null,
            ':gender' => $gender !== '' ? $gender : 'Male',
        ]);

        $userId = (int)$pdo->lastInsertId();

        json_response([
            'message' => 'Registration successful',
            'user' => [
                'userID' => $userId,
                'fullName' => $fullName,
                'email' => $email,
                'roles' => ['customer'],
            ],
        ], 201);
    }

    if ($action === 'login') {
        $email = trim((string)($input['email'] ?? ''));
        $password = (string)($input['password'] ?? '');

        if ($email === '' || $password === '') {
            json_response(['error' => 'Missing email or password'], 422);
        }

        $staffStmt = $pdo->prepare(
            'SELECT staff_id, full_name, email, password_hash, role
             FROM staff_users
             WHERE email = :email AND is_active = 1'
        );
        $staffStmt->execute([':email' => $email]);
        $staff = $staffStmt->fetch();

        if ($staff && password_verify($password, (string)$staff['password_hash'])) {
            json_response([
                'message' => 'Login successful',
                'user' => [
                    'userID' => (int)$staff['staff_id'],
                    'fullName' => $staff['full_name'],
                    'email' => $staff['email'],
                    'roles' => [strtolower((string)$staff['role'])],
                ],
            ]);
        }

        $stmt = $pdo->prepare(
            'SELECT user_id, full_name, email, password_hash
             FROM users
             WHERE email = :email AND is_active = 1'
        );
        $stmt->execute([':email' => $email]);
        $user = $stmt->fetch();

        if ($user && password_verify($password, (string)$user['password_hash'])) {
            json_response([
                'message' => 'Login successful',
                'user' => [
                    'userID' => (int)$user['user_id'],
                    'fullName' => $user['full_name'],
                    'email' => $user['email'],
                    'roles' => ['customer'],
                ],
            ]);
        }

        $barberStmt = $pdo->prepare(
            'SELECT barber_id, full_name, email, password_hash
             FROM barbers
             WHERE email = :email AND is_active = 1'
        );
        $barberStmt->execute([':email' => $email]);
        $barber = $barberStmt->fetch();

        if ($barber && !empty($barber['password_hash']) && password_verify($password, (string)$barber['password_hash'])) {
            json_response([
                'message' => 'Login successful',
                'user' => [
                    'userID' => (int)$barber['barber_id'],
                    'fullName' => $barber['full_name'],
                    'email' => $barber['email'],
                    'roles' => ['barber'],
                ],
            ]);
        }

        json_response(['error' => 'Invalid credentials'], 401);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
