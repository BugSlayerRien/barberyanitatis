<?php
// Walk-in kiosk API (queue + barber wait estimates)

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

$allowedActions = ['barberQueue', 'createWalkin', 'services'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function kiosk_service_duration_minutes(PDO $pdo): int
{
    $stmt = $pdo->query(
        "SELECT COALESCE(MAX(base_duration), 0) AS max_duration
         FROM services
         WHERE is_active = TRUE"
    );
    $maxDuration = (int)($stmt->fetchColumn() ?: 0);
    if ($maxDuration > 0) {
        return max(30, min(120, $maxDuration));
    }

    return shop_slot_duration_minutes();
}

function estimate_barber_wait_minutes(PDO $pdo, ?int $barberId): int
{
    $serviceMinutes = kiosk_service_duration_minutes($pdo);

    if ($barberId !== null && $barberId > 0) {
        $walkinStmt = $pdo->prepare(
            "SELECT COUNT(*)::int
             FROM walkin_queue
             WHERE DATE(created_at) = CURRENT_DATE
               AND barber_id = :barber_id
               AND status IN ('Waiting', 'Assigned', 'InProgress')"
        );
        $walkinStmt->execute([':barber_id' => $barberId]);
        $walkinAhead = (int)$walkinStmt->fetchColumn();

        $apptStmt = $pdo->prepare(
            "SELECT COUNT(*)::int
             FROM appointments
             WHERE appointment_date = CURRENT_DATE
               AND barber_id = :barber_id
               AND status IN ('Scheduled', 'CheckedIn', 'InProgress')"
        );
        $apptStmt->execute([':barber_id' => $barberId]);
        $apptAhead = (int)$apptStmt->fetchColumn();

        return ($walkinAhead + $apptAhead) * $serviceMinutes;
    }

    $stmt = $pdo->query(
        "SELECT COUNT(*)::int
         FROM walkin_queue
         WHERE DATE(created_at) = CURRENT_DATE
           AND status IN ('Waiting', 'Assigned')"
    );

    return (int)$stmt->fetchColumn() * $serviceMinutes;
}

try {
    // Read-heavy actions: retry whole handler on TLS / "connection reset" (kiosk tablet Wi‑Fi).
    if ($action === 'services' || $action === 'barberQueue') {
        with_pdo_retry(function (PDO $pdo) use ($action): void {
            ensure_walkin_guest_name_column($pdo);
            auto_complete_due_appointments($pdo);

            if ($action === 'services') {
                $stmt = $pdo->prepare(
                    'SELECT service_id, service_name, description, base_duration,
                            CASE WHEN LOWER(category) = \'haircut\' THEN 100 ELSE base_price END AS base_price,
                            category
                     FROM services
                     WHERE is_active = TRUE
                     ORDER BY service_name'
                );
                $stmt->execute();
                json_response(['services' => $stmt->fetchAll()]);
            }

            $barbersStmt = $pdo->query(
                'SELECT barber_id, full_name, specialty, rating, years_experience, is_active
                 FROM barbers
                 WHERE is_active = TRUE
                 ORDER BY full_name'
            );
            $barbers = [];
            foreach ($barbersStmt->fetchAll() as $row) {
                $barberId = (int)$row['barber_id'];
                $waitMinutes = estimate_barber_wait_minutes($pdo, $barberId);

                $queueStmt = $pdo->prepare(
                    "SELECT COUNT(*)::int
                     FROM walkin_queue
                     WHERE DATE(created_at) = CURRENT_DATE
                       AND barber_id = :barber_id
                       AND status IN ('Waiting', 'Assigned', 'InProgress')"
                );
                $queueStmt->execute([':barber_id' => $barberId]);
                $queueCount = (int)$queueStmt->fetchColumn();

                $barbers[] = [
                    'barber_id' => $barberId,
                    'full_name' => $row['full_name'],
                    'specialty' => $row['specialty'],
                    'rating' => $row['rating'],
                    'years_experience' => $row['years_experience'],
                    'waitMinutes' => $waitMinutes,
                    'queueCount' => $queueCount,
                    'waitLabel' => $waitMinutes <= 0 ? 'Available now' : 'Available in ' . $waitMinutes . ' min',
                ];
            }

            $anyWait = estimate_barber_wait_minutes($pdo, null);

            json_response([
                'barbers' => $barbers,
                'firstAvailable' => [
                    'waitMinutes' => $anyWait,
                    'waitLabel' => $anyWait <= 0 ? 'Next available' : 'About ' . $anyWait . ' min',
                ],
                'serviceMinutes' => kiosk_service_duration_minutes($pdo),
            ]);
        });
    }

    if ($action === 'createWalkin') {
        $pdo = get_db_connection();
        ensure_walkin_guest_name_column($pdo);
        auto_complete_due_appointments($pdo);

        $serviceIDs = $input['serviceIDs'] ?? [];
        $barberID = (int)($input['barberID'] ?? 0);
        $guestName = trim((string)($input['guestName'] ?? ''));
        $variantID = (int)($input['variantID'] ?? 0);
        $styleName = trim((string)($input['styleName'] ?? ''));
        $scanMode = trim((string)($input['scanMode'] ?? ''));

        if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing serviceIDs'], 422);
        }

        if ($guestName === '') {
            json_response(['error' => 'guestName is required'], 422);
        }

        if ($variantID <= 0) {
            $variantStmt = $pdo->prepare(
                'SELECT hv.variant_id
                 FROM hairstyle_variants hv
                 JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
                 WHERE hs.is_active = TRUE
                 ORDER BY hv.confidence_score DESC, hv.variant_id ASC
                 LIMIT 1'
            );
            $variantStmt->execute();
            $variantID = (int)$variantStmt->fetchColumn();
        }

        if ($variantID <= 0) {
            json_response(['error' => 'No active hairstyle variants available'], 422);
        }

        $waitMinutes = estimate_barber_wait_minutes($pdo, $barberID > 0 ? $barberID : null);

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE');
        $countStmt->execute();
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $queueNumber = 'W-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

        $status = $barberID > 0 ? 'Assigned' : 'Waiting';

        $insertQueue = $pdo->prepare(
            'INSERT INTO walkin_queue (queue_number, barber_id, status, wait_time_minutes, guest_name)
             VALUES (:queue_number, :barber_id, :status, :wait_time_minutes, :guest_name)
             RETURNING queue_id'
        );
        $insertQueue->execute([
            ':queue_number' => $queueNumber,
            ':barber_id' => $barberID > 0 ? $barberID : null,
            ':status' => $status,
            ':wait_time_minutes' => $waitMinutes,
            ':guest_name' => $guestName,
        ]);

        $queueID = (int)$insertQueue->fetchColumn();

        $serviceStmt = $pdo->prepare(
            'SELECT service_id, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = TRUE'
        );
        $detailStmt = $pdo->prepare(
            'INSERT INTO walkin_service_details (queue_id, service_id, variant_id, selected_view, special_instructions, final_price)
             VALUES (:queue_id, :service_id, :variant_id, :selected_view, :special_instructions, :final_price)'
        );

        $entryPath = trim((string)($input['entryPath'] ?? ''));
        $instructions = trim(
            'Kiosk walk-in'
            . ($entryPath !== '' ? " | Path: {$entryPath}" : '')
            . ($styleName !== '' ? " | Style: {$styleName}" : '')
            . ($scanMode !== '' ? " | Scan: {$scanMode}" : '')
        );

        foreach ($serviceIDs as $serviceID) {
            $serviceID = (int)$serviceID;
            if ($serviceID <= 0) {
                continue;
            }
            $serviceStmt->execute([':service_id' => $serviceID]);
            $service = $serviceStmt->fetch();
            if (!$service) {
                continue;
            }
            $detailStmt->execute([
                ':queue_id' => $queueID,
                ':service_id' => $serviceID,
                ':variant_id' => $variantID,
                ':selected_view' => 'Front',
                ':special_instructions' => $instructions,
                ':final_price' => $service['base_price'],
            ]);
        }

        $pdo->commit();

        json_response([
            'message' => 'Walk-in created',
            'queueID' => $queueID,
            'queueNumber' => $queueNumber,
            'waitMinutes' => $waitMinutes,
            'waitLabel' => $waitMinutes <= 0 ? 'You are next' : 'About ' . $waitMinutes . ' min',
            'guestName' => $guestName,
            'styleName' => $styleName,
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(db_error_response_payload($e), 500);
}
