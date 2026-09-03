<?php
// Barbers API (list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/customer_auth.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? 'list'));

if (!in_array($action, ['list', 'detail', 'submitFeedback', 'updateProfileImage'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function save_barber_profile_image(int $barberId, string $base64): string
{
    $raw = $base64;
    if (str_contains($raw, ',')) {
        $raw = substr($raw, (int)strpos($raw, ',') + 1);
    }
    $bytes = base64_decode($raw, true);
    if ($bytes === false || strlen($bytes) < 32) {
        throw new InvalidArgumentException('Invalid profile image data');
    }

    $filename = 'barber_' . $barberId . '_' . time() . '.jpg';
    $relative = 'uploads/barbers/' . $filename;
    storage_put_bytes($relative, $bytes, 'image/jpeg');

    return $relative;
}

function find_active_barber_id(PDO $pdo, int $barberID, string $email): int
{
    // Email is the logged-in identity. Resolve it first so a colliding
    // users.user_id / session ID cannot UPDATE a different barbers row
    // (file written, target profile_image left empty).
    if ($email !== '') {
        $stmt = $pdo->prepare(
            'SELECT barber_id FROM barbers WHERE lower(email) = lower(?) AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$email]);
        $id = (int)($stmt->fetchColumn() ?: 0);
        if ($id > 0) {
            return $id;
        }
    }

    if ($barberID > 0) {
        $stmt = $pdo->prepare(
            'SELECT barber_id FROM barbers WHERE barber_id = ? AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$barberID]);
        $id = (int)($stmt->fetchColumn() ?: 0);
        if ($id > 0) {
            return $id;
        }
    }

    return 0;
}

function ensure_barber_feedback_table(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS barber_feedback (
            feedback_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            barber_id BIGINT NOT NULL,
            user_id BIGINT NOT NULL,
            rating INT NOT NULL,
            comment TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT ck_barber_feedback_rating CHECK (rating >= 1 AND rating <= 5),
            CONSTRAINT uq_barber_feedback_appointment_user UNIQUE (appointment_id, user_id),
            CONSTRAINT fk_barber_feedback_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
            CONSTRAINT fk_barber_feedback_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id) ON DELETE CASCADE,
            CONSTRAINT fk_barber_feedback_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
        )"
    );
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $input): void {
    ensure_barber_feedback_table($pdo);
    ensure_barber_channel_column($pdo);

    if ($action === 'submitFeedback') {
        $customer = require_customer($pdo, $input);
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $barberID = (int)($input['barberID'] ?? 0);
        $userID = (int)$customer['user_id'];
        $rating = (int)($input['rating'] ?? 0);
        $comment = trim((string)($input['comment'] ?? ''));

        if ($appointmentID <= 0 || $barberID <= 0 || $userID <= 0 || $rating < 1 || $rating > 5) {
            json_response(['error' => 'Invalid feedback payload'], 422);
        }

        $apptStmt = $pdo->prepare(
            'SELECT appointment_id, status, barber_id, user_id
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }
        if ((int)$appt['barber_id'] !== $barberID || (int)$appt['user_id'] !== $userID) {
            json_response(['error' => 'Feedback does not match appointment ownership'], 403);
        }
        if ((string)$appt['status'] !== 'Completed') {
            json_response(['error' => 'Feedback is allowed only for completed appointments'], 409);
        }

        $pdo->beginTransaction();

        $insertStmt = $pdo->prepare(
            'INSERT INTO barber_feedback (appointment_id, barber_id, user_id, rating, comment)
             VALUES (:appointment_id, :barber_id, :user_id, :rating, :comment)
             ON CONFLICT (appointment_id, user_id)
             DO UPDATE SET
                rating = EXCLUDED.rating,
                comment = EXCLUDED.comment'
        );
        $insertStmt->execute([
            ':appointment_id' => $appointmentID,
            ':barber_id' => $barberID,
            ':user_id' => $userID,
            ':rating' => $rating,
            ':comment' => $comment !== '' ? $comment : null,
        ]);

        $avgStmt = $pdo->prepare('SELECT AVG(rating) AS avg_rating FROM barber_feedback WHERE barber_id = :barber_id');
        $avgStmt->execute([':barber_id' => $barberID]);
        $avgRating = (float)($avgStmt->fetch()['avg_rating'] ?? 5.0);

        $updateBarberStmt = $pdo->prepare('UPDATE barbers SET rating = :rating WHERE barber_id = :barber_id');
        $updateBarberStmt->execute([
            ':rating' => round($avgRating, 2),
            ':barber_id' => $barberID,
        ]);

        $pdo->commit();

        json_response([
            'message' => 'Feedback submitted',
            'barberRating' => round($avgRating, 2),
        ]);
    }

    if ($action === 'updateProfileImage') {
        $barberID = (int)($input['barberID'] ?? $input['barberId'] ?? $input['userID'] ?? 0);
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $imageBase64 = trim((string)($input['profileImageBase64'] ?? $input['profile_image_base64'] ?? ''));
        if ($imageBase64 === '') {
            json_response(['error' => 'Invalid barberID or image data'], 422);
        }

        $resolvedBarberID = find_active_barber_id($pdo, $barberID, $email);
        if ($resolvedBarberID <= 0) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $path = save_barber_profile_image($resolvedBarberID, $imageBase64);
        $updateStmt = $pdo->prepare(
            'UPDATE barbers SET profile_image = ? WHERE barber_id = ?'
        );
        $updateStmt->execute([$path, $resolvedBarberID]);

        $verifyStmt = $pdo->prepare(
            'SELECT barber_id, profile_image FROM barbers WHERE barber_id = ? LIMIT 1'
        );
        $verifyStmt->execute([$resolvedBarberID]);
        $updated = $verifyStmt->fetch(PDO::FETCH_ASSOC);
        $storedPath = trim((string)($updated['profile_image'] ?? ''));
        if ($storedPath !== $path) {
            json_response(['error' => 'Unable to save profile image path'], 500);
        }

        json_response([
            'message' => 'Profile image updated',
            'profileImage' => $storedPath,
            'barberID' => (int)$updated['barber_id'],
        ]);
    }

    if ($action === 'detail') {
        $barberID = (int)($input['barberID'] ?? $input['barberId'] ?? $input['userID'] ?? 0);
        $email = strtolower(trim((string)($input['email'] ?? '')));
        $resolvedBarberID = find_active_barber_id($pdo, $barberID, $email);
        if ($resolvedBarberID <= 0) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name, specialty, years_experience, rating, profile_image, bio
             FROM barbers
             WHERE barber_id = ? AND is_active = TRUE'
        );
        $stmt->execute([$resolvedBarberID]);
        $barber = $stmt->fetch();
        if (!$barber) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $todayStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments WHERE barber_id = :barber_id AND appointment_date = CURRENT_DATE"
        );
        $todayStmt->execute([':barber_id' => $resolvedBarberID]);
        $todayCount = (int)$todayStmt->fetchColumn();

        $ratingCountStmt = $pdo->prepare(
            'SELECT COUNT(DISTINCT user_id)::int AS rating_count FROM barber_feedback WHERE barber_id = :barber_id'
        );
        $ratingCountStmt->execute([':barber_id' => $resolvedBarberID]);
        $ratingCount = (int)($ratingCountStmt->fetchColumn() ?: 0);

        // Feedback comments were stored on submission but no endpoint ever
        // returned them to the barber they were about — this page previously
        // showed only the aggregate rating/ratingCount above. Customer identity
        // is intentionally not included.
        $feedbackStmt = $pdo->prepare(
            'SELECT rating, comment, created_at
             FROM barber_feedback
             WHERE barber_id = :barber_id
             ORDER BY created_at DESC
             LIMIT 20'
        );
        $feedbackStmt->execute([':barber_id' => $resolvedBarberID]);
        $recentFeedback = array_map(static function (array $row): array {
            return [
                'rating' => (int)$row['rating'],
                'comment' => $row['comment'] !== null ? (string)$row['comment'] : null,
                'createdAt' => (string)$row['created_at'],
            ];
        }, $feedbackStmt->fetchAll());

        json_response([
            'barber' => $barber,
            'appointmentsToday' => $todayCount,
            'ratingCount' => $ratingCount,
            'recentFeedback' => $recentFeedback,
        ]);
    }

    $channelRaw = $input['channel'] ?? $input['barberChannel'] ?? null;
    $channelSql = '';
    if ($channelRaw !== null && trim((string)$channelRaw) !== '' && strtolower(trim((string)$channelRaw)) !== 'all') {
        $channel = normalize_barber_channel((string)$channelRaw) ?? 'appointment';
        $channelSql = barber_channel_filter_sql($channel);
    }

    $stmt = $pdo->prepare(
        "SELECT barber_id, full_name, specialty, years_experience, rating, profile_image, barber_channel
         FROM barbers
         WHERE is_active = TRUE{$channelSql}
         ORDER BY full_name"
    );
    $stmt->execute();

    json_response(['barbers' => $stmt->fetchAll()]);
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
} catch (Throwable $e) {
    json_response(['error' => $e->getMessage()], 500);
}
