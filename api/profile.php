<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';

require_method('POST');

$data = get_json_input();
$action = strtolower(trim((string)($data['action'] ?? 'get')));
$userID = (int)($data['userID'] ?? $data['userId'] ?? 0);

if ($userID <= 0) {
    json_response(['error' => 'userID is required'], 400);
}

function normalize_gender(?string $value): string
{
    $v = trim((string)$value);
    if ($v === '' || strcasecmp($v, 'prefer not to tell') === 0) {
        return 'Other';
    }
    foreach (['Male', 'Female', 'Other'] as $allowed) {
        if (strcasecmp($v, $allowed) === 0) {
            return $allowed;
        }
    }
    return 'Other';
}

function normalize_hair_texture(?string $value): ?string
{
    $v = trim((string)$value);
    if ($v === '' || strcasecmp($v, 'prefer not to tell') === 0) {
        return null;
    }
    foreach (['Straight', 'Wavy', 'Curly'] as $allowed) {
        if (strcasecmp($v, $allowed) === 0) {
            return $allowed;
        }
    }
    return null;
}

function format_account_age(int $days): string
{
    if ($days < 1) {
        return 'Less than 1 day';
    }

    return $days . ' day' . ($days === 1 ? '' : 's');
}

function save_profile_image_file(int $userId, string $base64): string
{
    $bytes = base64_decode($base64, true);
    if ($bytes === false || strlen($bytes) < 32) {
        throw new InvalidArgumentException('Invalid profile image data');
    }

    $dir = api_project_root() . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'profiles';
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
        throw new RuntimeException('Could not create profile upload directory');
    }

    $filename = 'user_' . $userId . '_' . time() . '.jpg';
    $fullPath = $dir . DIRECTORY_SEPARATOR . $filename;
    if (file_put_contents($fullPath, $bytes) === false) {
        throw new RuntimeException('Could not save profile image');
    }

    return 'uploads/profiles/' . $filename;
}

function fetch_profile_row(PDO $pdo, int $userID): ?array
{
    $stmt = $pdo->prepare(
        'SELECT
            u.user_id,
            u.email,
            u.full_name,
            u.phone,
            u.gender,
            u.profile_image,
            u.created_at,
            up.hair_texture,
            COALESCE(ac.haircuts_done, 0) AS haircuts_done
        FROM users u
        LEFT JOIN user_profiles up ON up.user_id = u.user_id
        LEFT JOIN (
            SELECT user_id, COUNT(*)::int AS haircuts_done
            FROM appointments
            WHERE status = ?
            GROUP BY user_id
        ) ac ON ac.user_id = u.user_id
        WHERE u.user_id = ?'
    );
    $stmt->execute(['Completed', $userID]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    return $row ?: null;
}

function profile_payload_from_row(array $row): array
{
    $createdDate = new DateTime((string)$row['created_at']);
    $now = new DateTime();
    $accountAgeDays = max(0, (int)$now->diff($createdDate)->days);

    return [
        'userID' => (int)$row['user_id'],
        'email' => (string)($row['email'] ?? ''),
        'fullName' => (string)($row['full_name'] ?? ''),
        'phone' => (string)($row['phone'] ?? ''),
        'gender' => (string)($row['gender'] ?? ''),
        'hairTexture' => (string)($row['hair_texture'] ?? ''),
        'profileImage' => (string)($row['profile_image'] ?? ''),
        'accountAge' => format_account_age($accountAgeDays),
        'accountAgeDays' => $accountAgeDays,
        'haircutsDone' => (int)($row['haircuts_done'] ?? 0),
    ];
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $data, $userID): void {

    if ($action === 'update') {
        $row = fetch_profile_row($pdo, $userID);
        if ($row === null) {
            json_response(['error' => 'User not found'], 404);
        }

        $fullName = trim((string)($data['fullName'] ?? $data['full_name'] ?? $row['full_name'] ?? ''));
        $phone = trim((string)($data['phone'] ?? $row['phone'] ?? ''));
        $gender = normalize_gender($data['gender'] ?? $row['gender'] ?? '');
        $hairTexture = normalize_hair_texture($data['hairTexture'] ?? $data['hair_texture'] ?? $row['hair_texture'] ?? null);
        $profileImage = (string)($row['profile_image'] ?? '');

        $imageBase64 = trim((string)($data['profile_image_base64'] ?? $data['profileImageBase64'] ?? ''));
        if ($imageBase64 !== '') {
            $profileImage = save_profile_image_file($userID, $imageBase64);
        }

        if ($fullName === '') {
            json_response(['error' => 'Full name is required'], 422);
        }

        $updateUser = $pdo->prepare(
            'UPDATE users
             SET full_name = :full_name,
                 phone = :phone,
                 gender = :gender,
                 profile_image = :profile_image,
                 updated_at = NOW()
             WHERE user_id = :user_id'
        );
        $updateUser->execute([
            ':full_name' => $fullName,
            ':phone' => $phone !== '' ? $phone : null,
            ':gender' => $gender,
            ':profile_image' => $profileImage !== '' ? $profileImage : null,
            ':user_id' => $userID,
        ]);

        $upsertProfile = $pdo->prepare(
            'INSERT INTO user_profiles (user_id, hair_texture, created_at)
             VALUES (:user_id, :hair_texture, NOW())
             ON CONFLICT (user_id) DO UPDATE
             SET hair_texture = EXCLUDED.hair_texture'
        );
        $upsertProfile->execute([
            ':user_id' => $userID,
            ':hair_texture' => $hairTexture,
        ]);

        $updated = fetch_profile_row($pdo, $userID);
        if ($updated === null) {
            json_response(['error' => 'User not found after update'], 404);
        }

        json_response([
            'message' => 'Profile updated',
            'profile' => profile_payload_from_row($updated),
        ], 200);
    }

    $row = fetch_profile_row($pdo, $userID);
    if ($row === null) {
        json_response(['error' => 'User not found'], 404);
    }

    json_response(['profile' => profile_payload_from_row($row)], 200);
    });
} catch (InvalidArgumentException $e) {
    json_response(['error' => $e->getMessage()], 422);
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
} catch (Throwable $e) {
    json_response(['error' => 'Error: ' . $e->getMessage()], 500);
}
