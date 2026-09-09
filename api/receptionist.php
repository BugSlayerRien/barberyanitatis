<?php
// Receptionist actions API (dashboard + updates)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/service_channel.php';
require_once __DIR__ . '/payment_recording.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/group_booking.php';
require_once __DIR__ . '/slot_locking.php';

function ensure_financial_tables(PDO $pdo): void
{
    // Columns added for the manual refund workflow; mirrors booking.php so
    // whichever endpoint runs first creates them.
    $addRefundColumns = static function (PDO $db): void {
        foreach ([
            'contact_phone VARCHAR(40)',
            'user_id BIGINT',
            'completed_at TIMESTAMPTZ',
            'completed_by VARCHAR(120)',
            'note TEXT',
        ] as $column) {
            try {
                $db->exec('ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS ' . $column);
            } catch (Throwable $e) {
                // Table may not exist yet on first run; created below.
            }
        }
    };
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payments (
            payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'Captured',
            transaction_ref VARCHAR(120),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_payments_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
        )"
    );

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_refunds (
            refund_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            payment_id BIGINT,
            amount NUMERIC(10,2) NOT NULL,
            reason VARCHAR(80),
            status VARCHAR(30) NOT NULL DEFAULT 'Completed',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_refunds_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
            CONSTRAINT fk_appointment_refunds_payment
                FOREIGN KEY (payment_id) REFERENCES appointment_payments(payment_id) ON DELETE SET NULL
        )"
    );

    $addRefundColumns($pdo);
}

// Browsers open the .php URL with GET (shows "Method not allowed"); the desk uses POST JSON.
if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')) === 'GET') {
    require_once __DIR__ . '/http.php';
    apply_api_cors_headers();
    json_response([
        'error' => 'Use POST from the receptionist dashboard',
        'hint' => 'Open web-admin/receptionist/ and sign in. This endpoint expects JSON POST with an action field.',
    ], 405);
}

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? 'dashboard';

$allowedActions = ['dashboard', 'updateAppointmentStatus', 'updateWalkinStatus', 'createWalkin', 'listRefunds', 'completeRefund'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();
    ensure_walkin_guest_name_column($pdo);
    ensure_walkin_queue_timestamp_columns($pdo);
    ensure_barber_channel_column($pdo);
    ensure_financial_tables($pdo);
    $trackingAutomation = run_tracking_automation($pdo, true);

    if ($action === 'dashboard') {
        $deskStats = fetch_receptionist_front_desk_stats($pdo);
        $walkInsToday = $deskStats['walkInsToday'];
        $appointmentsToday = $deskStats['appointmentsToday'];
        $inProgress = $deskStats['inProgress'];
        $activeBarbers = $deskStats['availableBarbers'];
        $todayRevenue = $deskStats['todayRevenue'];

        ensure_group_booking_schema($pdo);
        sync_paid_groups_from_payments($pdo, true);
        sync_paid_appointments_from_payments($pdo, true);

        $appointmentsStmt = $pdo->prepare(
            'SELECT a.appointment_id, a.barber_id, a.booking_group_id, a.group_member_name, a.group_sequence,
                    u.full_name AS booker_name,
                    string_agg(s.service_name, \', \' ORDER BY s.service_name) AS service,
                    a.appointment_date,
                    a.start_time AS time,
                    a.end_time,
                    a.checkin_time,
                    COALESCE(NULLIF(SUM(s.base_duration), 0), :slot_duration_select)::int AS estimated_minutes,
                    SUM(ad.final_price) AS price,
                    a.status,
                    b.full_name AS barber,
                    pay.status AS payment_status,
                    intent.status AS intent_status
             FROM appointments a
             JOIN users u ON a.user_id = u.user_id
             JOIN barbers b ON a.barber_id = b.barber_id
             JOIN appointment_details ad ON a.appointment_id = ad.appointment_id
             JOIN services s ON ad.service_id = s.service_id
             LEFT JOIN LATERAL (
                 SELECT status
                 FROM appointment_payments
                 WHERE appointment_id = a.appointment_id
                 ORDER BY payment_id DESC
                 LIMIT 1
             ) pay ON TRUE
             LEFT JOIN LATERAL (
                 SELECT status
                 FROM appointment_payment_intents
                 WHERE appointment_id = a.appointment_id
                 ORDER BY intent_id DESC
                 LIMIT 1
             ) intent ON TRUE
             WHERE a.status NOT IN (\'Cancelled\', \'NoShow\', \'Completed\')
               AND (
                    a.status IN (\'PendingPayment\', \'CheckedIn\', \'InProgress\')
                    OR a.appointment_date::timestamp + a.start_time + make_interval(mins => :slot_duration_filter) > NOW()
               )
               AND b.barber_channel = \'appointment\'
             GROUP BY a.appointment_id, a.barber_id, a.booking_group_id, a.group_member_name, a.group_sequence,
                      u.full_name, a.appointment_date, a.start_time, a.end_time, a.checkin_time, a.status, b.full_name, pay.status, intent.status
             ORDER BY a.appointment_date ASC, a.start_time ASC'
        );
        $slotDuration = shop_appointment_duration_minutes();
        $appointmentsStmt->bindValue(':slot_duration_select', $slotDuration, PDO::PARAM_INT);
        $appointmentsStmt->bindValue(':slot_duration_filter', $slotDuration, PDO::PARAM_INT);
        $appointmentsStmt->execute();
        $appointmentRows = $appointmentsStmt->fetchAll();
        $appointments = collapse_receptionist_appointments($pdo, array_map(static function (array $row): array {
            return [
                'appointment_id' => (int)$row['appointment_id'],
                'barber_id' => (int)$row['barber_id'],
                'booking_group_id' => (int)($row['booking_group_id'] ?? 0),
                'group_member_name' => (string)($row['group_member_name'] ?? ''),
                'group_sequence' => (int)($row['group_sequence'] ?? 0),
                'name' => (string)$row['booker_name'],
                'booker_name' => (string)$row['booker_name'],
                'payment_status' => $row['payment_status'] !== null ? (string)$row['payment_status'] : null,
                'intent_status' => $row['intent_status'] !== null ? (string)$row['intent_status'] : null,
                'service' => (string)$row['service'],
                'appointment_date' => (string)$row['appointment_date'],
                'time' => (string)$row['time'],
                'end_time' => (string)$row['end_time'],
                'duration' => shop_appointment_duration_minutes() . ' min',
                'estimated_minutes' => (int)($row['estimated_minutes'] ?? shop_appointment_duration_minutes()),
                'checkin_time' => $row['checkin_time'] !== null ? (string)$row['checkin_time'] : null,
                'price' => $row['price'],
                'status' => (string)$row['status'],
                'barber' => (string)$row['barber'],
            ];
        }, $appointmentRows));

        $walkinsStmt = $pdo->prepare(
            'SELECT wq.queue_id, wq.queue_number, wq.barber_id, wq.actual_start,
                    COALESCE(NULLIF(TRIM(wq.guest_name), \'\'), \'Walk-in #\' || RIGHT(wq.queue_number, 3)) AS name,
                    COALESCE(NULLIF(string_agg(DISTINCT s.service_name, \', \' ORDER BY s.service_name), \'\'), \'Walk-in\') AS service,
                    COALESCE(NULLIF(SUM(s.base_duration), 0), :walkin_duration)::int AS estimated_minutes,
                    wq.wait_time_minutes,
                    wq.status,
                    b.full_name AS barber
             FROM walkin_queue wq
             LEFT JOIN walkin_service_details wsd ON wq.queue_id = wsd.queue_id
             LEFT JOIN services s ON wsd.service_id = s.service_id
             LEFT JOIN barbers b ON wq.barber_id = b.barber_id
             WHERE DATE(wq.created_at) = CURRENT_DATE
               AND (b.barber_id IS NULL OR b.barber_channel = \'walk_in\')
             GROUP BY wq.queue_id, wq.queue_number, wq.barber_id, wq.actual_start, wq.guest_name, wq.wait_time_minutes, wq.status, b.full_name
             ORDER BY wq.queue_id ASC'
        );
        $walkinsStmt->bindValue(':walkin_duration', shop_walkin_duration_minutes(), PDO::PARAM_INT);
        $walkinsStmt->execute();
        $walkins = $walkinsStmt->fetchAll();

        json_response([
            'stats' => [
                ['title' => 'Walk-ins', 'value' => (string)$walkInsToday, 'change' => '', 'changeType' => 'info'],
                ['title' => 'Appointments', 'value' => (string)$appointmentsToday, 'change' => '', 'changeType' => 'success'],
                ['title' => "Today's revenue", 'value' => 'PHP ' . number_format($todayRevenue, 2, '.', ''), 'change' => '', 'changeType' => 'gold'],
                ['title' => 'In Progress', 'value' => (string)$inProgress, 'change' => '', 'changeType' => 'warning'],
                ['title' => 'Available Barbers', 'value' => (string)$activeBarbers, 'change' => '', 'changeType' => 'success'],
            ],
            'todayRevenue' => $todayRevenue,
            'appointments' => array_map(static function (array $row): array {
                return [
                    'appointment_id' => (int)$row['appointment_id'],
                    'barber_id' => (int)$row['barber_id'],
                    'is_group' => (bool)($row['is_group'] ?? false),
                    'people_count' => (int)($row['people_count'] ?? 1),
                    'name' => (string)$row['name'],
                    'member_names' => $row['member_names'] ?? [],
                    'member_label' => (string)($row['member_label'] ?? $row['name']),
                    'service' => (string)$row['service'],
                    'appointment_date' => (string)$row['appointment_date'],
                    'time' => (string)$row['time'],
                    'end_time' => (string)($row['end_time'] ?? ''),
                    'time_range' => (string)($row['time_range'] ?? ''),
                    'duration' => (string)($row['duration'] ?? '60 min'),
                    'estimated_minutes' => (int)($row['estimated_minutes'] ?? shop_appointment_duration_minutes()),
                    'checkin_time' => $row['checkin_time'] ?? null,
                    'price' => $row['price'],
                    'status' => (string)$row['status'],
                    'barber' => (string)$row['barber'],
                ];
            }, $appointments),
            'walkins' => array_map(function ($row) {
                return [
                    'queue_id' => (int)$row['queue_id'],
                    'queue_number' => $row['queue_number'],
                    'barber_id' => $row['barber_id'] !== null ? (int)$row['barber_id'] : null,
                    'name' => $row['name'],
                    'service' => $row['service'] ?? 'Walk-in',
                    'waitTime' => $row['wait_time_minutes'] !== null ? $row['wait_time_minutes'] . ' min' : '',
                    'status' => $row['status'],
                    'barber' => $row['barber'],
                    'actual_start' => $row['actual_start'] ?? null,
                    'estimated_minutes' => (int)($row['estimated_minutes'] ?? shop_walkin_duration_minutes()),
                ];
            }, $walkins),
            'automation' => $trackingAutomation,
        ]);
    }

    // --- Refunds -----------------------------------------------------------
    // Cancelling a paid booking raises a Pending row (see booking.php 'cancel').
    // There is no payment-gateway refund in this system: a receptionist sends
    // the money by hand and marks it done here, which is what tells the
    // customer their refund has been sent.
    if ($action === 'listRefunds') {
        ensure_financial_tables($pdo);
        $status = strtolower(trim((string)($input['status'] ?? 'pending')));
        $where = $status === 'all'
            ? '1=1'
            : ($status === 'completed' ? "r.status = 'Completed'" : "r.status = 'Pending'");

        $rows = $pdo->query(
            "SELECT r.refund_id, r.appointment_id, r.amount, r.reason, r.status,
                    r.contact_phone, r.created_at, r.completed_at, r.completed_by, r.note,
                    u.full_name, u.email, u.phone AS profile_phone,
                    a.appointment_date, a.start_time
             FROM appointment_refunds r
             LEFT JOIN users u ON u.user_id = r.user_id
             LEFT JOIN appointments a ON a.appointment_id = r.appointment_id
             WHERE {$where}
             ORDER BY r.status ASC, r.created_at DESC
             LIMIT 200"
        )->fetchAll(PDO::FETCH_ASSOC);

        json_response([
            'refunds' => array_map(static function (array $row): array {
                $phone = trim((string)($row['contact_phone'] ?? ''));
                if ($phone === '') {
                    $phone = trim((string)($row['profile_phone'] ?? ''));
                }
                return [
                    'refundId' => (int)$row['refund_id'],
                    'appointmentId' => (int)$row['appointment_id'],
                    'customerName' => (string)($row['full_name'] ?? 'Customer'),
                    'customerEmail' => (string)($row['email'] ?? ''),
                    'contactPhone' => $phone,
                    'amount' => (float)$row['amount'],
                    'reason' => (string)($row['reason'] ?? ''),
                    'status' => (string)$row['status'],
                    'appointmentDate' => (string)($row['appointment_date'] ?? ''),
                    'startTime' => (string)($row['start_time'] ?? ''),
                    'createdAt' => (string)$row['created_at'],
                    'completedAt' => (string)($row['completed_at'] ?? ''),
                    'completedBy' => (string)($row['completed_by'] ?? ''),
                    'note' => (string)($row['note'] ?? ''),
                ];
            }, $rows),
        ]);
    }

    if ($action === 'completeRefund') {
        ensure_financial_tables($pdo);
        $refundId = (int)($input['refundId'] ?? 0);
        if ($refundId <= 0) {
            json_response(['error' => 'Invalid refundId'], 422);
        }

        $lookup = $pdo->prepare(
            'SELECT appointment_id, user_id, amount, status FROM appointment_refunds WHERE refund_id = :id LIMIT 1'
        );
        $lookup->execute([':id' => $refundId]);
        $refund = $lookup->fetch(PDO::FETCH_ASSOC);
        if (!$refund) {
            json_response(['error' => 'Refund not found'], 404);
        }
        if ((string)$refund['status'] === 'Completed') {
            json_response(['message' => 'Refund already marked as sent']);
        }

        $pdo->prepare(
            "UPDATE appointment_refunds
             SET status = 'Completed', completed_at = NOW(), completed_by = :by, note = :note
             WHERE refund_id = :id"
        )->execute([
            ':id' => $refundId,
            ':by' => substr(trim((string)($input['completedBy'] ?? 'Receptionist')), 0, 120),
            ':note' => trim((string)($input['note'] ?? '')) ?: null,
        ]);

        // This notification IS the customer-facing confirmation.
        if ((int)($refund['user_id'] ?? 0) > 0) {
            $pdo->prepare(
                // notification_type is constrained to
                // ('Appointment','Reminder','Queue','Promotion','System') and
                // recipient_type to ('User','Barber','Admin'). 'Refund' is not a
                // member, so this insert violated
                // notifications_notification_type_check. A refund notice is
                // about the customer's appointment, so 'Appointment' fits and
                // needs no schema change.
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
                 VALUES ('User', :recipient_id, 'Appointment', 'Refund sent', :message, TRUE)"
            )->execute([
                ':recipient_id' => (int)$refund['user_id'],
                ':message' => 'Your refund of P' . number_format((float)$refund['amount'], 2)
                    . ' for cancelled appointment #' . (int)$refund['appointment_id'] . ' has been sent.',
            ]);
        }

        json_response(['message' => 'Refund marked as sent']);
    }

    if ($action === 'updateAppointmentStatus') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $status = trim((string)($input['status'] ?? ''));

        $allowed = ['PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow'];
        if ($appointmentID <= 0 || !in_array($status, $allowed, true)) {
            json_response(['error' => 'Invalid appointmentID or status'], 422);
        }

        $checkinTime = null;
        $completionTime = null;
        if ($status === 'CheckedIn' || $status === 'InProgress') {
            $checkinTime = date('Y-m-d H:i:s');
        }
        if ($status === 'Completed') {
            $completionTime = date('Y-m-d H:i:s');
        }

        ensure_group_booking_schema($pdo);

        $apptLookupStmt = $pdo->prepare(
            'SELECT appointment_id, user_id, barber_id, booking_code, appointment_date, start_time, booking_group_id, status
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptLookupStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptLookupStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }

        if ($status === 'Completed'
            && !shop_appointment_may_complete_now((string)$appt['appointment_date'], (string)($appt['status'] ?? ''))
        ) {
            json_response(['error' => 'This appointment is scheduled for a future date and cannot be marked completed yet.'], 422);
        }

        $groupId = (int)($appt['booking_group_id'] ?? 0);
        $pdo->beginTransaction();

        if ($status === 'Completed') {
            complete_booking_unit($pdo, $appointmentID, $completionTime);
        } elseif ($groupId > 0 && in_array($status, ['Cancelled', 'NoShow'], true)) {
            $cancelStmt = $pdo->prepare(
                "UPDATE appointments
                 SET status = :status,
                     checkin_time = COALESCE(checkin_time, :checkin_time),
                     completion_time = COALESCE(:completion_time, completion_time),
                     updated_at = CURRENT_TIMESTAMP
                 WHERE booking_group_id = :group_id
                   AND status NOT IN ('Cancelled', 'NoShow', 'Completed')"
            );
            $cancelStmt->execute([
                ':status' => $status,
                ':checkin_time' => $checkinTime,
                ':completion_time' => $completionTime,
                ':group_id' => $groupId,
            ]);

            $membersStmt = $pdo->prepare(
                'SELECT appointment_id FROM appointments WHERE booking_group_id = :group_id'
            );
            $membersStmt->execute([':group_id' => $groupId]);
            foreach ($membersStmt->fetchAll(PDO::FETCH_ASSOC) as $member) {
                release_slots_for_appointment($pdo, (int)$member['appointment_id']);
            }

            $pdo->prepare(
                "UPDATE appointment_groups
                 SET status = :status
                 WHERE group_id = :group_id"
            )->execute([':status' => $status, ':group_id' => $groupId]);
        } elseif ($groupId > 0) {
            $groupUpdate = $pdo->prepare(
                "UPDATE appointments
                 SET status = :status,
                     checkin_time = COALESCE(checkin_time, :checkin_time),
                     completion_time = COALESCE(:completion_time, completion_time),
                     updated_at = CURRENT_TIMESTAMP
                 WHERE booking_group_id = :group_id
                   AND status NOT IN ('Cancelled', 'NoShow', 'Completed')"
            );
            $groupUpdate->execute([
                ':status' => $status,
                ':checkin_time' => $checkinTime,
                ':completion_time' => $completionTime,
                ':group_id' => $groupId,
            ]);
        } else {
            $stmt = $pdo->prepare(
                'UPDATE appointments
                 SET status = :status,
                     checkin_time = COALESCE(checkin_time, :checkin_time),
                     completion_time = COALESCE(:completion_time, completion_time)
                 WHERE appointment_id = :appointment_id'
            );
            $stmt->execute([
                ':status' => $status,
                ':checkin_time' => $checkinTime,
                ':completion_time' => $completionTime,
                ':appointment_id' => $appointmentID,
            ]);

            $slotStatus = in_array($status, ['Cancelled', 'NoShow', 'Completed'], true) ? 'Available' : 'Booked';
            $slotStmt = $pdo->prepare(
                "UPDATE time_slots
                 SET status = :status
                 WHERE barber_id = :barber_id
                   AND slot_date = :slot_date
                   AND slot_time = :slot_time"
            );
            $slotStmt->execute([
                ':status' => $slotStatus,
                ':barber_id' => (int)$appt['barber_id'],
                ':slot_date' => (string)$appt['appointment_date'],
                ':slot_time' => (string)$appt['start_time'],
            ]);
        }

        $notifyStatusStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', :title, :message, TRUE)"
        );
        $notifyStatusStmt->execute([
            ':recipient_id' => (int)$appt['user_id'],
            ':title' => 'Appointment status updated',
            ':message' => 'Booking ' . (string)$appt['booking_code'] . ' is now ' . $status . '.',
        ]);

        $pdo->commit();

        json_response(['message' => 'Appointment updated']);
    }

    if ($action === 'updateWalkinStatus') {
        $queueID = (int)($input['queueID'] ?? 0);
        $status = trim((string)($input['status'] ?? ''));
        $barberID = (int)($input['barberID'] ?? 0);

        $allowed = ['Waiting', 'Assigned', 'InProgress', 'Completed', 'Cancelled'];
        if ($queueID <= 0 || !in_array($status, $allowed, true)) {
            json_response(['error' => 'Invalid queueID or status'], 422);
        }

        $actualStart = null;
        $actualEnd = null;
        if ($status === 'InProgress') {
            $actualStart = date('Y-m-d H:i:s');
        }
        if ($status === 'Completed' || $status === 'Cancelled') {
            $actualEnd = date('Y-m-d H:i:s');
        }

        $setParts = ['status = :status'];
        $params = [
            ':status' => $status,
            ':queue_id' => $queueID,
        ];

        if ($barberID > 0) {
            $setParts[] = 'barber_id = :assign_barber_id';
            $params[':assign_barber_id'] = $barberID;
        }
        if ($actualStart !== null) {
            $setParts[] = 'actual_start = COALESCE(actual_start, :actual_start)';
            $params[':actual_start'] = $actualStart;
        }
        if ($actualEnd !== null) {
            $setParts[] = 'actual_end = :actual_end';
            $params[':actual_end'] = $actualEnd;
        }

        $sql = 'UPDATE walkin_queue SET ' . implode(', ', $setParts) . ' WHERE queue_id = :queue_id';
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);

        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Walk-in not found'], 404);
        }

        if ($status === 'Completed') {
            try {
                record_completion_payment($pdo, null, $queueID);
            } catch (Throwable $paymentError) {
                error_log('Walk-in payment record skipped: ' . $paymentError->getMessage());
            }
        }

        json_response(['message' => 'Walk-in updated']);
    }

    if ($action === 'createWalkin') {
        $serviceIDs = $input['serviceIDs'] ?? [];
        $barberID = (int)($input['barberID'] ?? 0);

        if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
            json_response(['error' => 'Missing serviceIDs'], 422);
        }

        ensure_service_channel_column($pdo);
        $validServiceIds = filter_walk_in_service_ids($pdo, $serviceIDs);
        if ($validServiceIds === []) {
            $fallbackId = default_walk_in_service_id($pdo);
            if ($fallbackId === null) {
                json_response(['error' => 'No walk-in service configured. Use a service with channel walk_in.'], 422);
            }
            $validServiceIds = [$fallbackId];
        }

        if ($barberID > 0) {
            $barberChannelStmt = $pdo->prepare(
                "SELECT COUNT(*) FROM barbers
                 WHERE barber_id = :barber_id AND is_active = TRUE AND barber_channel = 'walk_in'"
            );
            $barberChannelStmt->execute([':barber_id' => $barberID]);
            if ((int)$barberChannelStmt->fetchColumn() === 0) {
                json_response(['error' => 'Selected barber is not on the walk-in (regular) channel.'], 422);
            }
        } else {
            $pickedBarber = shop_pick_least_busy_walkin_barber_id($pdo);
            if ($pickedBarber !== null) {
                $barberID = $pickedBarber;
            }
        }

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
        if ($variantID <= 0) {
            json_response(['error' => 'No active hairstyle variants available'], 422);
        }

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM walkin_queue WHERE DATE(created_at) = CURRENT_DATE');
        $countStmt->execute();
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $queueNumber = 'W-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

        $status = $barberID > 0 ? 'Assigned' : 'Waiting';

        $insertQueue = $pdo->prepare(
            'INSERT INTO walkin_queue (queue_number, barber_id, status)
             VALUES (:queue_number, :barber_id, :status)
             RETURNING queue_id'
        );
        $insertQueue->execute([
            ':queue_number' => $queueNumber,
            ':barber_id' => $barberID > 0 ? $barberID : null,
            ':status' => $status,
        ]);

        $queueID = (int)$insertQueue->fetchColumn();

        $serviceStmt = $pdo->prepare(
            'SELECT service_id, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = TRUE AND service_channel = \'walk_in\''
        );
        $detailStmt = $pdo->prepare(
            'INSERT INTO walkin_service_details (queue_id, service_id, variant_id, selected_view, final_price)
             VALUES (:queue_id, :service_id, :variant_id, :selected_view, :final_price)'
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
                ':final_price' => $service['base_price'],
            ]);
        }

        $pdo->commit();

        json_response([
            'message' => 'Walk-in created',
            'queueID' => $queueID,
            'queueNumber' => $queueNumber,
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('receptionist.php PDO: ' . $e->getMessage());
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    error_log('receptionist.php: ' . $e->getMessage());
    json_response(['error' => 'Server error', 'details' => $e->getMessage()], 500);
}
