<?php
// Booking API (create + list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['create', 'listByCustomer', 'cancel'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'create') {
        $userID = (int)($input['userID'] ?? 0);
        $barberID = (int)($input['barberID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $startTime = trim((string)($input['startTime'] ?? ''));
        $endTime = trim((string)($input['endTime'] ?? ''));
        $items = $input['items'] ?? null;
        $serviceIDs = $input['serviceIDs'] ?? [];
        $variantID = (int)($input['variantID'] ?? 0);

        if ($userID <= 0 || $barberID <= 0 || $appointmentDate === '' || $startTime === '' || $endTime === '') {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        if (!is_array($items)) {
            if ($variantID <= 0) {
                json_response(['error' => 'Missing variantID'], 422);
            }

            if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
                $defaultServiceId = (int)$pdo->query("SELECT service_id FROM services WHERE category = 'Haircut' AND is_active = 1 ORDER BY service_id LIMIT 1")->fetchColumn();
                if ($defaultServiceId <= 0) {
                    json_response(['error' => 'No haircut service configured'], 422);
                }
                $serviceIDs = [$defaultServiceId];
            }

            $items = array_map(fn($id) => ['serviceID' => (int)$id, 'variantID' => $variantID], $serviceIDs);
        }

        $activeStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE user_id = :user_id
               AND status IN ('Scheduled', 'CheckedIn', 'InProgress')"
        );
        $activeStmt->execute([':user_id' => $userID]);
        if ((int)$activeStmt->fetchColumn() > 0) {
            json_response(['error' => 'You already have an active appointment.'], 409);
        }

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointment_date = :appointment_date');
        $countStmt->execute([':appointment_date' => $appointmentDate]);
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $bookingCode = 'APP-' . date('Ymd', strtotime($appointmentDate)) . '-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

        $stmt = $pdo->prepare(
            'INSERT INTO appointments (booking_code, user_id, barber_id, appointment_date, start_time, end_time)
             VALUES (:booking_code, :user_id, :barber_id, :appointment_date, :start_time, :end_time)'
        );
        $stmt->execute([
            ':booking_code' => $bookingCode,
            ':user_id' => $userID,
            ':barber_id' => $barberID,
            ':appointment_date' => $appointmentDate,
            ':start_time' => $startTime,
            ':end_time' => $endTime,
        ]);

        $appointmentID = (int)$pdo->lastInsertId();

        $priceStmt = $pdo->prepare('SELECT base_price FROM services WHERE service_id = :service_id');
        $linkStmt = $pdo->prepare(
            'INSERT INTO appointment_details (appointment_id, service_id, variant_id, selected_view, special_instructions, final_price)
             VALUES (:appointment_id, :service_id, :variant_id, :selected_view, :special_instructions, :final_price)'
        );

        foreach ($items as $item) {
            $serviceID = (int)($item['serviceID'] ?? 0);
            $variantIDItem = (int)($item['variantID'] ?? 0);
            $selectedView = trim((string)($item['selectedView'] ?? 'Front'));
            $specialInstructions = trim((string)($item['specialInstructions'] ?? ''));
            $finalPrice = $item['finalPrice'] ?? null;

            if ($serviceID <= 0 || $variantIDItem <= 0) {
                continue;
            }

            if ($finalPrice === null || $finalPrice === '') {
                $priceStmt->execute([':service_id' => $serviceID]);
                $finalPrice = (float)($priceStmt->fetchColumn() ?: 0);
            }

            $linkStmt->execute([
                ':appointment_id' => $appointmentID,
                ':service_id' => $serviceID,
                ':variant_id' => $variantIDItem,
                ':selected_view' => $selectedView !== '' ? $selectedView : 'Front',
                ':special_instructions' => $specialInstructions !== '' ? $specialInstructions : null,
                ':final_price' => $finalPrice,
            ]);
        }

        $pdo->commit();

        json_response([
            'message' => 'Appointment created',
            'appointmentID' => $appointmentID,
            'bookingCode' => $bookingCode,
        ], 201);
    }

    if ($action === 'listByCustomer') {
        $userID = (int)($input['userID'] ?? 0);
        if ($userID <= 0) {
            json_response(['error' => 'Invalid userID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT a.appointment_id, a.booking_code, a.appointment_date, a.start_time, a.end_time, a.status,
                    b.barber_id, b.full_name AS barber_name
             FROM appointments a
             JOIN barbers b ON a.barber_id = b.barber_id
             WHERE a.user_id = :user_id
             ORDER BY a.appointment_date DESC, a.start_time DESC'
        );
        $stmt->execute([':user_id' => $userID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            json_response(['appointments' => []]);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointment_id'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $serviceStmt = $pdo->prepare(
            "SELECT ad.appointment_id, s.service_id, s.service_name, s.base_duration, s.base_price,
                    ad.variant_id, ad.selected_view, ad.final_price,
                    hv.face_shape, hv.hair_texture, hv.front_view_url, hs.style_name
             FROM appointment_details ad
             JOIN services s ON ad.service_id = s.service_id
             JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE ad.appointment_id IN ($inClause)"
        );
        $serviceStmt->execute($appointmentIds);
        $serviceRows = $serviceStmt->fetchAll();

        $serviceMap = [];
        foreach ($serviceRows as $row) {
            $aid = (int)$row['appointment_id'];
            if (!isset($serviceMap[$aid])) {
                $serviceMap[$aid] = [];
            }
            $serviceMap[$aid][] = [
                'serviceID' => (int)$row['service_id'],
                'serviceName' => $row['service_name'],
                'durationMinutes' => (int)$row['base_duration'],
                'price' => (string)$row['final_price'],
                'variantID' => (int)$row['variant_id'],
                'selectedView' => $row['selected_view'],
                'hairstyleName' => $row['style_name'],
                'faceShape' => $row['face_shape'],
                'hairTexture' => $row['hair_texture'],
                'frontViewUrl' => $row['front_view_url'],
            ];
        }

        $appointments = array_map(function ($row) use ($serviceMap) {
            $aid = (int)$row['appointment_id'];
            return [
                'appointmentID' => $aid,
                'bookingCode' => $row['booking_code'],
                'appointmentDate' => $row['appointment_date'],
                'startTime' => $row['start_time'],
                'endTime' => $row['end_time'],
                'status' => $row['status'],
                'barberID' => (int)$row['barber_id'],
                'barberName' => $row['barber_name'],
                'services' => $serviceMap[$aid] ?? [],
            ];
        }, $appointments);

        json_response(['appointments' => $appointments]);
    }

    if ($action === 'cancel') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        if ($appointmentID <= 0) {
            json_response(['error' => 'Invalid appointmentID'], 422);
        }

        $stmt = $pdo->prepare(
            "UPDATE appointments
             SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP
             WHERE appointment_id = :appointment_id"
        );
        $stmt->execute([':appointment_id' => $appointmentID]);

        json_response(['message' => 'Appointment cancelled']);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
