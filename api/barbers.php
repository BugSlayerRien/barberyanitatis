<?php
// Barbers API (list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'list';

if (!in_array($action, ['list', 'detail', 'submitFeedback'], true)) {
    json_response(['error' => 'Invalid action'], 400);
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
    $pdo = get_db_connection();
    ensure_barber_feedback_table($pdo);

    if ($action === 'submitFeedback') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $barberID = (int)($input['barberID'] ?? 0);
        $userID = (int)($input['userID'] ?? 0);
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

    if ($action === 'detail') {
        $barberID = (int)($input['barberID'] ?? 0);
        if ($barberID <= 0) {
            json_response(['error' => 'Invalid barberID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name, specialty, years_experience, rating, profile_image, bio
             FROM barbers
             WHERE barber_id = :barber_id AND is_active = TRUE'
        );
        $stmt->execute([':barber_id' => $barberID]);
        $barber = $stmt->fetch();
        if (!$barber) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $todayStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments WHERE barber_id = :barber_id AND appointment_date = CURRENT_DATE"
        );
        $todayStmt->execute([':barber_id' => $barberID]);
        $todayCount = (int)$todayStmt->fetchColumn();

        json_response([
            'barber' => $barber,
            'appointmentsToday' => $todayCount,
        ]);
    }

    $stmt = $pdo->prepare(
        'SELECT barber_id, full_name, specialty, years_experience, rating, profile_image
         FROM barbers
         WHERE is_active = TRUE
         ORDER BY full_name'
    );
    $stmt->execute();

    json_response(['barbers' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
