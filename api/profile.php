<?php
// Profile API

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'get';
$userID = (int)($input['userID'] ?? 0);
if ($userID <= 0) {
    json_response(['error' => 'Invalid userID'], 422);
}

if (!in_array($action, ['get', 'update'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function column_exists(PDO $pdo, string $table, string $column): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = :table AND COLUMN_NAME = :column'
    );
    $stmt->execute([':table' => $table, ':column' => $column]);
    return (int)$stmt->fetchColumn() > 0;
}

try {
    $pdo = get_db_connection();

    $hasProfileImage = column_exists($pdo, 'users', 'profile_image');

    if ($action === 'update') {
        $fullName = trim((string)($input['fullName'] ?? ''));
        $phone = trim((string)($input['phone'] ?? ''));
        $imageBase64 = trim((string)($input['profileImageBase64'] ?? ''));

        $userStmt = $pdo->prepare('SELECT full_name, email, phone' . ($hasProfileImage ? ', profile_image' : '') . ' FROM users WHERE user_id = :user_id');
        $userStmt->execute([':user_id' => $userID]);
        $user = $userStmt->fetch();
        if (!$user) {
            json_response(['error' => 'User not found'], 404);
        }

        $finalName = $fullName !== '' ? $fullName : ($user['full_name'] ?? '');
        $finalPhone = $phone !== '' ? $phone : ($user['phone'] ?? null);

        $profileImagePath = $hasProfileImage ? ($user['profile_image'] ?? '') : '';
        if ($hasProfileImage && $imageBase64 !== '') {
            if (strpos($imageBase64, 'base64,') !== false) {
                $imageBase64 = explode('base64,', $imageBase64, 2)[1];
            }
            $binary = base64_decode($imageBase64, true);
            if ($binary === false) {
                json_response(['error' => 'Invalid image data'], 422);
            }
            $dir = __DIR__ . '/../uploads/profile';
            if (!is_dir($dir)) {
                mkdir($dir, 0755, true);
            }
            $fileName = 'user_' . $userID . '.jpg';
            $filePath = $dir . '/' . $fileName;
            file_put_contents($filePath, $binary);
            $profileImagePath = '/uploads/profile/' . $fileName;
        }

        if ($hasProfileImage) {
            $updateStmt = $pdo->prepare(
                'UPDATE users SET full_name = :full_name, phone = :phone, profile_image = :profile_image WHERE user_id = :user_id'
            );
            $updateStmt->execute([
                ':full_name' => $finalName,
                ':phone' => $finalPhone,
                ':profile_image' => $profileImagePath !== '' ? $profileImagePath : null,
                ':user_id' => $userID,
            ]);
        } else {
            $updateStmt = $pdo->prepare(
                'UPDATE users SET full_name = :full_name, phone = :phone WHERE user_id = :user_id'
            );
            $updateStmt->execute([
                ':full_name' => $finalName,
                ':phone' => $finalPhone,
                ':user_id' => $userID,
            ]);
        }
    }

    $userStmt = $pdo->prepare(
        'SELECT full_name, email, phone, created_at' . ($hasProfileImage ? ', profile_image' : '') . ' FROM users WHERE user_id = :user_id'
    );
    $userStmt->execute([':user_id' => $userID]);
    $user = $userStmt->fetch();
    if (!$user) {
        json_response(['error' => 'User not found'], 404);
    }

    $completedStmt = $pdo->prepare("SELECT COUNT(*) FROM appointments WHERE user_id = :user_id AND status = 'Completed'");
    $completedStmt->execute([':user_id' => $userID]);
    $completedCount = (int)$completedStmt->fetchColumn();

    $createdAt = new DateTimeImmutable($user['created_at'] ?? 'now');
    $now = new DateTimeImmutable('now');
    $diff = $createdAt->diff($now);
    $ageLabel = $diff->y > 0
        ? $diff->y . 'y ' . $diff->m . 'm'
        : ($diff->m > 0 ? $diff->m . 'm ' . $diff->d . 'd' : $diff->d . 'd');

    json_response([
        'profile' => [
            'fullName' => $user['full_name'] ?? '',
            'email' => $user['email'] ?? '',
            'phone' => $user['phone'] ?? '',
            'accountAge' => $ageLabel,
            'haircutsDone' => $completedCount,
            'profileImage' => $hasProfileImage ? ($user['profile_image'] ?? '') : '',
        ],
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}