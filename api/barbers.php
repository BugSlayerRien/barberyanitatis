<?php
// Barbers API (list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'list';

if (!in_array($action, ['list', 'detail'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'detail') {
        $barberID = (int)($input['barberID'] ?? 0);
        if ($barberID <= 0) {
            json_response(['error' => 'Invalid barberID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name, specialty, years_experience, rating, profile_image, bio
             FROM barbers
             WHERE barber_id = :barber_id AND is_active = 1'
        );
        $stmt->execute([':barber_id' => $barberID]);
        $barber = $stmt->fetch();
        if (!$barber) {
            json_response(['error' => 'Barber not found'], 404);
        }

        $todayStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments WHERE barber_id = :barber_id AND appointment_date = CURDATE()"
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
         WHERE is_active = 1
         ORDER BY full_name'
    );
    $stmt->execute();

    json_response(['barbers' => $stmt->fetchAll()]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
