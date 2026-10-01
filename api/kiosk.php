<?php
// Walk-in kiosk API (queue + barber wait estimates)

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/service_channel.php';
require_once __DIR__ . '/kiosk_guest_name.php';
require_once __DIR__ . '/walkin_presentation.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

$allowedActions = ['barberQueue', 'createWalkin', 'services', 'todayQueue', 'checkGuestName', 'lookupQueue'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function kiosk_service_duration_minutes(PDO $pdo): int
{
    return shop_walkin_duration_minutes();
}

function estimate_barber_wait_minutes(PDO $pdo, ?int $barberId): int
{
    return shop_estimate_walkin_barber_wait_minutes($pdo, $barberId);
}

try {
    // Read-heavy actions: retry whole handler on TLS / "connection reset" (kiosk tablet Wi‑Fi).
    if ($action === 'services' || $action === 'barberQueue' || $action === 'todayQueue') {
        with_pdo_retry(function (PDO $pdo) use ($action): void {
            ensure_walkin_guest_name_column($pdo);
            ensure_walkin_kiosk_columns($pdo);
            ensure_barber_channel_column($pdo);
            run_tracking_automation($pdo, true);

            if ($action === 'todayQueue') {
                $queueStmt = $pdo->query(
                    "SELECT wq.queue_number,
                            COALESCE(NULLIF(TRIM(wq.guest_name), ''), 'Guest') AS guest_name,
                            wq.status,
                            wq.wait_time_minutes,
                            b.full_name AS barber_name
                     FROM walkin_queue wq
                     LEFT JOIN barbers b ON b.barber_id = wq.barber_id
                     WHERE DATE(wq.created_at) = CURRENT_DATE
                       AND wq.status IN ('Waiting', 'Assigned', 'InProgress')
                     ORDER BY wq.queue_id ASC"
                );
                json_response([
                    'queue' => $queueStmt->fetchAll(),
                    'serviceMinutes' => shop_walkin_duration_minutes(),
                ]);
            }

            if ($action === 'services') {
                require_once __DIR__ . '/service_channel.php';
                ensure_service_channel_column($pdo);
                $walkInFilter = service_channel_filter_sql('walk_in');
                $stmt = $pdo->prepare(
                    "SELECT service_id, service_name, description, base_duration, base_price, category, service_channel
                     FROM services
                     WHERE is_active = TRUE{$walkInFilter}
                     ORDER BY service_name"
                );
                $stmt->execute();
                json_response(['services' => $stmt->fetchAll()]);
            }

            $walkInFilter = barber_channel_filter_sql('walk_in');
            $barbersStmt = $pdo->query(
                "SELECT barber_id, full_name, specialty, rating, years_experience, is_active, barber_channel
                 FROM barbers
                 WHERE is_active = TRUE{$walkInFilter}
                 ORDER BY full_name"
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

    // Asked while the customer is still at the kiosk, so a second Mark can be
    // prompted for a surname before anything is written.
    if ($action === 'checkGuestName') {
        $pdo = get_db_connection();
        ensure_walkin_guest_name_column($pdo);
        ensure_walkin_kiosk_columns($pdo);

        $guestName = trim((string)($input['guestName'] ?? ''));
        $error = kiosk_guest_name_validation_error($guestName);
        if ($error !== null) {
            json_response(['error' => $error], 422);
        }

        $taken = kiosk_count_open_walkins_named($pdo, $guestName);
        json_response([
            'duplicate' => $taken > 0,
            'count' => $taken,
            'message' => $taken > 0
                ? 'Someone called ' . $guestName . ' is already waiting. Add your last name so the barber calls the right person.'
                : null,
        ]);
    }

    // "Check my queue": the kiosk is the recovery path, so nobody has to
    // carry, memorise or photograph anything to find their number again.
    if ($action === 'lookupQueue') {
        $pdo = get_db_connection();
        ensure_walkin_guest_name_column($pdo);
        ensure_walkin_kiosk_columns($pdo);

        $guestName = trim((string)($input['guestName'] ?? ''));
        if (mb_strlen($guestName, 'UTF-8') < 2) {
            json_response(['error' => 'Enter at least 2 letters of your name.'], 422);
        }

        $stmt = $pdo->prepare(
            "SELECT wq.queue_id, wq.queue_number, wq.claim_code, wq.status,
                    wq.wait_time_minutes, wq.guest_name,
                    COALESCE(NULLIF(string_agg(DISTINCT s.service_name, ', ' ORDER BY s.service_name), ''), 'Walk-in') AS service,
                    MAX(wsd.special_instructions) AS instructions,
                    b.full_name AS barber
             FROM walkin_queue wq
             LEFT JOIN walkin_service_details wsd ON wsd.queue_id = wq.queue_id
             LEFT JOIN services s ON s.service_id = wsd.service_id
             LEFT JOIN barbers b ON b.barber_id = wq.barber_id
             WHERE DATE(wq.created_at) = CURRENT_DATE
               AND wq.status IN ('Waiting', 'Assigned', 'InProgress')
               AND LOWER(TRIM(wq.guest_name)) LIKE LOWER(TRIM(:name)) || '%'
             GROUP BY wq.queue_id, wq.queue_number, wq.claim_code, wq.status,
                      wq.wait_time_minutes, wq.guest_name, b.full_name
             ORDER BY wq.queue_id ASC"
        );
        $stmt->execute([':name' => $guestName]);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        json_response([
            'matches' => array_map(static function (array $row): array {
                return [
                    'queueID' => (int)$row['queue_id'],
                    'queueNumber' => (string)$row['queue_number'],
                    'claimCode' => (string)($row['claim_code'] ?? ''),
                    'guestName' => (string)($row['guest_name'] ?? ''),
                    'status' => (string)$row['status'],
                    'service' => (string)$row['service'],
                    'style' => kiosk_style_from_instructions((string)($row['instructions'] ?? '')),
                    'barber' => (string)($row['barber'] ?? ''),
                    'waitMinutes' => (int)($row['wait_time_minutes'] ?? 0),
                ];
            }, $rows),
        ]);
    }

    if ($action === 'createWalkin') {
        $pdo = get_db_connection();
        ensure_walkin_guest_name_column($pdo);
        ensure_walkin_kiosk_columns($pdo);
        ensure_barber_channel_column($pdo);
        run_tracking_automation($pdo, true);

        $serviceIDs = $input['serviceIDs'] ?? [];
        $barberID = (int)($input['barberID'] ?? 0);
        $guestName = trim((string)($input['guestName'] ?? ''));
        $variantID = (int)($input['variantID'] ?? 0);
        $styleName = trim((string)($input['styleName'] ?? ''));
        $scanMode = trim((string)($input['scanMode'] ?? ''));
        // Kiosk guests have no account, so the scan session is the only way
        // back to the AI previews they generated before joining the queue.
        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));

        if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing serviceIDs'], 422);
        }

        $guestNameError = kiosk_guest_name_validation_error($guestName);
        if ($guestNameError !== null) {
            json_response(['error' => $guestNameError], 422);
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

        if ($barberID > 0) {
            $barberChannelStmt = $pdo->prepare(
                "SELECT COUNT(*) FROM barbers
                 WHERE barber_id = :barber_id
                   AND is_active = TRUE" . barber_channel_filter_sql('walk_in')
            );
            $barberChannelStmt->execute([':barber_id' => $barberID]);
            if ((int)$barberChannelStmt->fetchColumn() === 0) {
                json_response(['error' => 'This barber is not available for walk-in service.'], 422);
            }
        } else {
            $pickedBarber = shop_pick_least_busy_walkin_barber_id($pdo);
            if ($pickedBarber !== null) {
                $barberID = $pickedBarber;
            }
        }

        $waitMinutes = shop_estimate_walkin_barber_wait_minutes($pdo, $barberID > 0 ? $barberID : null);

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE');
        $countStmt->execute();
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $queueNumber = 'W-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);
        $claimCode = kiosk_generate_claim_code($pdo);

        $status = $barberID > 0 ? 'Assigned' : 'Waiting';

        // Consent and payment choice are captured at the kiosk but only reach
        // the database here: nothing exists to attach them to until the guest
        // actually joins the queue.
        $consentAccepted = !empty($input['consentAccepted']);
        $paymentMode = strtolower(trim((string)($input['paymentMode'] ?? '')));
        if (!in_array($paymentMode, ['counter', 'gcash'], true)) {
            $paymentMode = 'counter';
        }

        $insertQueue = $pdo->prepare(
            'INSERT INTO walkin_queue (queue_number, barber_id, status, wait_time_minutes, guest_name,
                                       consent_accepted_at, payment_mode, claim_code, scan_session_id)
             VALUES (:queue_number, :barber_id, :status, :wait_time_minutes, :guest_name,
                     :consent_accepted_at, :payment_mode, :claim_code, :scan_session_id)
             RETURNING queue_id'
        );
        $insertQueue->execute([
            ':queue_number' => $queueNumber,
            ':barber_id' => $barberID > 0 ? $barberID : null,
            ':status' => $status,
            ':wait_time_minutes' => $waitMinutes,
            ':guest_name' => $guestName,
            ':consent_accepted_at' => $consentAccepted ? date('c') : null,
            ':payment_mode' => $paymentMode,
            ':claim_code' => $claimCode,
            ':scan_session_id' => $scanSessionId !== '' ? $scanSessionId : null,
        ]);

        $queueID = (int)$insertQueue->fetchColumn();

        $validServiceIds = filter_walk_in_service_ids($pdo, $serviceIDs);
        if ($validServiceIds === []) {
            $fallbackId = default_walk_in_service_id($pdo);
            if ($fallbackId === null) {
                $pdo->rollBack();
                json_response(['error' => 'No walk-in (regular) service is configured. Add an active service with channel walk_in.'], 422);
            }
            $validServiceIds = [$fallbackId];
        }

        $serviceStmt = $pdo->prepare(
            'SELECT service_id, service_name, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = TRUE AND service_channel = \'walk_in\''
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

        foreach ($validServiceIds as $serviceID) {
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
            'claimCode' => $claimCode,
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(db_error_response_payload($e), 500);
}
