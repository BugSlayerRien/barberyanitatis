<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/hair_length.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/customer_auth.php';
require_once __DIR__ . '/slot_recommendation.php';

require_method('POST');

$data = get_json_input();
$action = strtolower(trim((string)($data['action'] ?? 'get')));

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

    $filename = 'user_' . $userId . '_' . time() . '.jpg';
    $relative = 'uploads/profiles/' . $filename;
    storage_put_bytes($relative, $bytes, 'image/jpeg');

    return $relative;
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
            up.hair_length,
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
        // Already written by every scan; nothing read it back, so a customer
        // who had not scanned in this app run was treated as short-haired by
        // default even though their own profile knew better.
        'hairLength' => (string)(normalize_hair_length($row['hair_length'] ?? null) ?? ''),
        'hairLengthLevel' => hair_length_label_to_level($row['hair_length'] ?? null),
        'profileImage' => (string)($row['profile_image'] ?? ''),
        'accountAge' => format_account_age($accountAgeDays),
        'accountAgeDays' => $accountAgeDays,
        'haircutsDone' => (int)($row['haircuts_done'] ?? 0),
    ];
}

function profile_booking_preferences(PDO $pdo, int $userId): array
{
    $history = slot_recommendation_load_history($pdo, $userId);
    $rated = slot_recommendation_load_rated_favorite($pdo, $userId);

    return slot_recommendation_profile_display(
        slot_recommendation_build_profile($history, $rated)
    );
}

function profile_payload(PDO $pdo, array $row): array
{
    $payload = profile_payload_from_row($row);
    $payload['bookingPreferences'] = profile_booking_preferences($pdo, (int)$row['user_id']);

    return $payload;
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $data): void {
    $customer = require_customer($pdo, $data);
    $userID = $customer['user_id'];

    if ($action === 'update') {
        $row = fetch_profile_row($pdo, $userID);
        if ($row === null) {
            json_response(['error' => 'User not found'], 404);
        }

        $fullName = trim((string)($data['fullName'] ?? $data['full_name'] ?? $row['full_name'] ?? ''));
        $phone = trim((string)($data['phone'] ?? $row['phone'] ?? ''));
        $gender = normalize_gender($data['gender'] ?? $row['gender'] ?? '');
        $hairTexture = normalize_hair_texture($data['hairTexture'] ?? $data['hair_texture'] ?? $row['hair_texture'] ?? null);
        $hairLength = normalize_hair_length(
            $data['hairLength'] ?? $data['hair_length'] ?? $row['hair_length'] ?? null
        );
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

        // COALESCE on length, not on texture: an unrecognised length means
        // "not sent", and a profile save that leaves the field alone must not
        // wipe what the last scan measured.
        $upsertProfile = $pdo->prepare(
            'INSERT INTO user_profiles (user_id, hair_texture, hair_length, created_at)
             VALUES (:user_id, :hair_texture, :hair_length, NOW())
             ON CONFLICT (user_id) DO UPDATE
             SET hair_texture = EXCLUDED.hair_texture,
                 hair_length = COALESCE(EXCLUDED.hair_length, user_profiles.hair_length)'
        );
        $upsertProfile->execute([
            ':user_id' => $userID,
            ':hair_texture' => $hairTexture,
            ':hair_length' => $hairLength,
        ]);

        $updated = fetch_profile_row($pdo, $userID);
        if ($updated === null) {
            json_response(['error' => 'User not found after update'], 404);
        }

        json_response([
            'message' => 'Profile updated',
            'profile' => profile_payload($pdo, $updated),
        ], 200);
    }

    $row = fetch_profile_row($pdo, $userID);
    if ($row === null) {
        json_response(['error' => 'User not found'], 404);
    }

    json_response(['profile' => profile_payload($pdo, $row)], 200);
    });
} catch (InvalidArgumentException $e) {
    json_response(['error' => $e->getMessage()], 422);
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
} catch (Throwable $e) {
    json_response(['error' => 'Error: ' . $e->getMessage()], 500);
}
