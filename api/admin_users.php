<?php
// Admin users API (list users by role)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['error' => 'Method not allowed'], 405);
}

try {
    $pdo = get_db_connection();

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = get_json_input();
        $action = $input['action'] ?? 'update';
        $type = $input['type'] ?? '';

        if ($action !== 'update') {
            json_response(['error' => 'Invalid action'], 400);
        }

        if (!in_array($type, ['customer', 'barber', 'staff'], true)) {
            json_response(['error' => 'Invalid type'], 422);
        }

        if ($type === 'customer') {
            $id = (int)($input['id'] ?? 0);
            if ($id <= 0) {
                json_response(['error' => 'Invalid user ID'], 422);
            }
            $current = $pdo->prepare('SELECT full_name, email, phone, is_active FROM users WHERE user_id = :id');
            $current->execute([':id' => $id]);
            $row = $current->fetch();
            if (!$row) {
                json_response(['error' => 'User not found'], 404);
            }

            $fullName = trim((string)($input['fullName'] ?? $row['full_name']));
            $email = trim((string)($input['email'] ?? $row['email']));
            $phone = trim((string)($input['phone'] ?? $row['phone']));
            $isActive = isset($input['isActive']) ? (int)$input['isActive'] : (int)$row['is_active'];

            $stmt = $pdo->prepare('UPDATE users SET full_name = :full_name, email = :email, phone = :phone, is_active = :is_active WHERE user_id = :id');
            $stmt->execute([
                ':full_name' => $fullName,
                ':email' => $email,
                ':phone' => $phone !== '' ? $phone : null,
                ':is_active' => $isActive,
                ':id' => $id,
            ]);

            $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
                 VALUES ('Admin', 0, 'System', 'User updated', :message)"
            )->execute([':message' => $fullName . ' account updated']);
        }

        if ($type === 'barber') {
            $id = (int)($input['id'] ?? 0);
            if ($id <= 0) {
                json_response(['error' => 'Invalid barber ID'], 422);
            }
            $current = $pdo->prepare('SELECT full_name, email, specialty, years_experience, rating, is_active FROM barbers WHERE barber_id = :id');
            $current->execute([':id' => $id]);
            $row = $current->fetch();
            if (!$row) {
                json_response(['error' => 'Barber not found'], 404);
            }

            $fullName = trim((string)($input['fullName'] ?? $row['full_name']));
            $email = trim((string)($input['email'] ?? $row['email']));
            $specialty = trim((string)($input['specialty'] ?? $row['specialty']));
            $years = isset($input['yearsExperience']) ? (int)$input['yearsExperience'] : (int)$row['years_experience'];
            $rating = isset($input['rating']) ? (float)$input['rating'] : (float)$row['rating'];
            $isActive = isset($input['isActive']) ? (int)$input['isActive'] : (int)$row['is_active'];

            $stmt = $pdo->prepare(
                'UPDATE barbers SET full_name = :full_name, email = :email, specialty = :specialty,
                 years_experience = :years_experience, rating = :rating, is_active = :is_active
                 WHERE barber_id = :id'
            );
            $stmt->execute([
                ':full_name' => $fullName,
                ':email' => $email !== '' ? $email : null,
                ':specialty' => $specialty !== '' ? $specialty : null,
                ':years_experience' => $years,
                ':rating' => $rating,
                ':is_active' => $isActive,
                ':id' => $id,
            ]);

            $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
                 VALUES ('Admin', 0, 'System', 'Barber updated', :message)"
            )->execute([':message' => $fullName . ' profile updated']);
        }

        if ($type === 'staff') {
            $id = (int)($input['id'] ?? 0);
            if ($id <= 0) {
                json_response(['error' => 'Invalid staff ID'], 422);
            }
            $current = $pdo->prepare('SELECT full_name, email, role, is_active FROM staff_users WHERE staff_id = :id');
            $current->execute([':id' => $id]);
            $row = $current->fetch();
            if (!$row) {
                json_response(['error' => 'Staff not found'], 404);
            }

            $fullName = trim((string)($input['fullName'] ?? $row['full_name']));
            $email = trim((string)($input['email'] ?? $row['email']));
            $role = trim((string)($input['role'] ?? $row['role']));
            $isActive = isset($input['isActive']) ? (int)$input['isActive'] : (int)$row['is_active'];

            $stmt = $pdo->prepare(
                'UPDATE staff_users SET full_name = :full_name, email = :email, role = :role, is_active = :is_active WHERE staff_id = :id'
            );
            $stmt->execute([
                ':full_name' => $fullName,
                ':email' => $email,
                ':role' => $role !== '' ? $role : $row['role'],
                ':is_active' => $isActive,
                ':id' => $id,
            ]);

            $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
                 VALUES ('Admin', 0, 'System', 'Staff updated', :message)"
            )->execute([':message' => $fullName . ' staff record updated']);
        }

        json_response(['message' => 'Updated']);
    }

    $customers = $pdo->query(
        'SELECT user_id, full_name, email, phone, is_active, created_at
         FROM users
         ORDER BY created_at DESC'
    )->fetchAll();

    $barbers = $pdo->query(
        'SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at
         FROM barbers
         ORDER BY created_at DESC'
    )->fetchAll();

    $staff = $pdo->query(
        'SELECT staff_id, full_name, email, role, is_active, created_at
         FROM staff_users
         ORDER BY created_at DESC'
    )->fetchAll();

    $admins = array_values(array_filter($staff, fn($row) => strtolower((string)$row['role']) === 'admin'));
    $receptionists = array_values(array_filter($staff, fn($row) => strtolower((string)$row['role']) === 'receptionist'));

    json_response([
        'customers' => $customers,
        'barbers' => $barbers,
        'admins' => $admins,
        'receptionists' => $receptionists,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
