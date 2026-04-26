<?php
// Booking API (create + list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

function ensure_financial_tables(PDO $pdo): void
{
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

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payment_intents (
            intent_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            provider VARCHAR(30) NOT NULL DEFAULT 'mock',
            status VARCHAR(30) NOT NULL DEFAULT 'PendingGateway',
            intent_token VARCHAR(120) NOT NULL UNIQUE,
            provider_ref VARCHAR(120),
            failure_reason TEXT,
            expires_at TIMESTAMPTZ NOT NULL,
            paid_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_payment_intents_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
        )"
    );
}

function derive_payment_state(?string $paymentStatus, ?string $intentStatus): string
{
    if ($paymentStatus === 'Captured') {
        return 'Paid';
    }

    if ($intentStatus !== null) {
        if (in_array($intentStatus, ['PendingGateway', 'Verifying'], true)) {
            return 'Verifying';
        }
        if (in_array($intentStatus, ['Failed', 'Expired', 'Cancelled'], true)) {
            return 'Failed';
        }
    }

    return 'Unpaid';
}

function ensure_appointments_status_constraint(PDO $pdo): void
{
    // Older schemas miss PendingPayment in appointments_status_check, causing booking inserts to fail.
    $constraintStmt = $pdo->prepare(
        "SELECT pg_get_constraintdef(c.oid) AS def
         FROM pg_constraint c
         JOIN pg_class t ON c.conrelid = t.oid
         JOIN pg_namespace n ON t.relnamespace = n.oid
         WHERE n.nspname = 'public'
           AND t.relname = 'appointments'
           AND c.conname = 'appointments_status_check'
         LIMIT 1"
    );
    $constraintStmt->execute();
    $row = $constraintStmt->fetch();

    if (!$row) {
        return;
    }

    $definition = (string)($row['def'] ?? '');
    if (stripos($definition, 'PendingPayment') !== false) {
        return;
    }

    $pdo->exec('ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_status_check');
    $pdo->exec(
        "ALTER TABLE appointments
         ADD CONSTRAINT appointments_status_check
         CHECK (
            status = ANY (
                ARRAY[
                    'PendingPayment'::text,
                    'Scheduled'::text,
                    'CheckedIn'::text,
                    'InProgress'::text,
                    'Completed'::text,
                    'Cancelled'::text,
                    'NoShow'::text
                ]
            )
         )"
    );
}

function normalize_time_string(string $value): ?string
{
    $value = trim($value);
    if ($value === '') {
        return null;
    }

    if (!preg_match('/^\d{2}:\d{2}(:\d{2})?$/', $value)) {
        return null;
    }

    $parts = explode(':', $value);
    $hour = (int)$parts[0];
    $minute = (int)$parts[1];
    $second = isset($parts[2]) ? (int)$parts[2] : 0;

    if ($hour < 0 || $hour > 23 || $minute < 0 || $minute > 59 || $second < 0 || $second > 59) {
        return null;
    }

    return sprintf('%02d:%02d:%02d', $hour, $minute, $second);
}

function is_valid_ymd_date(string $value): bool
{
    $date = DateTimeImmutable::createFromFormat('Y-m-d', $value);
    return $date !== false && $date->format('Y-m-d') === $value;
}

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['create', 'listByCustomer', 'listByBarber', 'cancel', 'reschedule'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();
    ensure_financial_tables($pdo);
    ensure_appointments_status_constraint($pdo);

    if ($action === 'create') {
        $userID = (int)($input['userID'] ?? 0);
        $barberID = (int)($input['barberID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $startTimeRaw = trim((string)($input['startTime'] ?? ''));
        $endTimeRaw = trim((string)($input['endTime'] ?? ''));
        $items = $input['items'] ?? null;
        $serviceIDs = $input['serviceIDs'] ?? [];
        $variantID = (int)($input['variantID'] ?? 0);

        $startTime = normalize_time_string($startTimeRaw);
        $endTime = normalize_time_string($endTimeRaw);

        if ($userID <= 0 || $barberID <= 0 || $appointmentDate === '' || $startTime === null || $endTime === null) {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        if (!is_valid_ymd_date($appointmentDate)) {
            json_response(['error' => 'Invalid appointmentDate format (expected YYYY-MM-DD).'], 422);
        }

        $appointmentDateTimeStart = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $appointmentDate . ' ' . $startTime);
        $appointmentDateTimeEnd = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $appointmentDate . ' ' . $endTime);
        if ($appointmentDateTimeStart === false || $appointmentDateTimeEnd === false) {
            json_response(['error' => 'Invalid appointment date/time value.'], 422);
        }

        if ($appointmentDateTimeEnd <= $appointmentDateTimeStart) {
            json_response(['error' => 'endTime must be later than startTime.'], 422);
        }

        $durationMinutes = (int)floor(($appointmentDateTimeEnd->getTimestamp() - $appointmentDateTimeStart->getTimestamp()) / 60);
        if ($durationMinutes < 10 || $durationMinutes > 240) {
            json_response(['error' => 'Invalid appointment duration.'], 422);
        }

        $now = new DateTimeImmutable('now');
        if ($appointmentDateTimeStart < $now) {
            json_response(['error' => 'Cannot book an appointment in the past.'], 422);
        }

        $userCheck = $pdo->prepare('SELECT COUNT(*) FROM users WHERE user_id = :user_id AND is_active = TRUE');
        $userCheck->execute([':user_id' => $userID]);
        if ((int)$userCheck->fetchColumn() === 0) {
            json_response(['error' => 'Invalid or inactive customer account.'], 422);
        }

        $barberCheck = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE barber_id = :barber_id AND is_active = TRUE');
        $barberCheck->execute([':barber_id' => $barberID]);
        if ((int)$barberCheck->fetchColumn() === 0) {
            json_response(['error' => 'Invalid or inactive barber account.'], 422);
        }

        if (!is_array($items)) {
            if ($variantID <= 0) {
                json_response(['error' => 'Missing variantID'], 422);
            }

            if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
                $defaultServiceId = (int)$pdo->query("SELECT service_id FROM services WHERE category = 'Haircut' AND is_active = TRUE ORDER BY service_id LIMIT 1")->fetchColumn();
                if ($defaultServiceId <= 0) {
                    json_response(['error' => 'No haircut service configured'], 422);
                }
                $serviceIDs = [$defaultServiceId];
            }

            $items = array_map(fn($id) => ['serviceID' => (int)$id, 'variantID' => $variantID], $serviceIDs);
        }

        $serviceInfoStmt = $pdo->prepare(
            'SELECT service_id, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = TRUE'
        );
        $variantExistsStmt = $pdo->prepare(
            'SELECT COUNT(*)
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hv.variant_id = :variant_id
               AND hs.is_active = TRUE'
        );

        $validatedItems = [];
        foreach ($items as $index => $item) {
            $serviceID = (int)($item['serviceID'] ?? 0);
            $variantIDItem = (int)($item['variantID'] ?? 0);

            if ($serviceID <= 0 || $variantIDItem <= 0) {
                continue;
            }

            $serviceInfoStmt->execute([':service_id' => $serviceID]);
            $serviceInfo = $serviceInfoStmt->fetch();
            if (!$serviceInfo) {
                json_response(['error' => 'Selected service is unavailable. Please refresh and try again.'], 422);
            }

            $variantExistsStmt->execute([':variant_id' => $variantIDItem]);
            if ((int)$variantExistsStmt->fetchColumn() === 0) {
                json_response(['error' => 'Selected haircut is unavailable. Please select another style and try again.'], 422);
            }

            $finalPrice = $item['finalPrice'] ?? null;
            if ($finalPrice === null || $finalPrice === '') {
                $finalPrice = $serviceInfo['base_price'];
            }

            $validatedItems[] = [
                'serviceID' => $serviceID,
                'variantID' => $variantIDItem,
                'selectedView' => $item['selectedView'] ?? 'Front',
                'specialInstructions' => $item['specialInstructions'] ?? '',
                'finalPrice' => $finalPrice,
            ];
        }

        if (count($validatedItems) === 0) {
            json_response(['error' => 'No valid booking items were provided.'], 422);
        }

        $activeStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE user_id = :user_id
             AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')"
        );
        $activeStmt->execute([':user_id' => $userID]);
        if ((int)$activeStmt->fetchColumn() > 0) {
            json_response(['error' => 'You already have an active appointment.'], 409);
        }

        $barberOverlapStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE barber_id = :barber_id
               AND appointment_date = :appointment_date
                AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')
               AND (
                    (start_time < :end_time AND end_time > :start_time)
               )"
        );
        $barberOverlapStmt->execute([
            ':barber_id' => $barberID,
            ':appointment_date' => $appointmentDate,
            ':start_time' => $startTime,
            ':end_time' => $endTime,
        ]);
        if ((int)$barberOverlapStmt->fetchColumn() > 0) {
            json_response(['error' => 'Selected time overlaps with another appointment for this barber.'], 409);
        }

        $slotAvailableStmt = $pdo->prepare(
            "SELECT slot_id FROM time_slots
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time
               AND status = 'Available'
             LIMIT 1"
        );
        $slotAvailableStmt->execute([
            ':barber_id' => $barberID,
            ':slot_date' => $appointmentDate,
            ':slot_time' => $startTime,
        ]);
        $slotRow = $slotAvailableStmt->fetch();
        if (!$slotRow) {
            json_response(['error' => 'Selected time slot is no longer available.'], 409);
        }

        $pdo->beginTransaction();

        $countStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointment_date = :appointment_date');
        $countStmt->execute([':appointment_date' => $appointmentDate]);
        $sequence = (int)$countStmt->fetchColumn() + 1;
        $bookingCode = 'APP-' . date('Ymd', strtotime($appointmentDate)) . '-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

        $stmt = $pdo->prepare(
              'INSERT INTO appointments (booking_code, user_id, barber_id, appointment_date, start_time, end_time, status)
               VALUES (:booking_code, :user_id, :barber_id, :appointment_date, :start_time, :end_time, :status)
             RETURNING appointment_id'
        );
        $stmt->execute([
            ':booking_code' => $bookingCode,
            ':user_id' => $userID,
            ':barber_id' => $barberID,
            ':appointment_date' => $appointmentDate,
            ':start_time' => $startTime,
            ':end_time' => $endTime,
            ':status' => 'PendingPayment',
        ]);

        $appointmentID = (int)$stmt->fetchColumn();

        $detailStmt = $pdo->prepare(
            'INSERT INTO appointment_details (appointment_id, service_id, variant_id, selected_view, final_price)
             VALUES (:appointment_id, :service_id, :variant_id, :selected_view, :final_price)'
        );

        foreach ($validatedItems as $item) {
            $serviceID = (int)($item['serviceID'] ?? 0);
            $variantIDItem = (int)($item['variantID'] ?? 0);
            $selectedView = trim((string)($item['selectedView'] ?? 'Front'));
            $specialInstructions = trim((string)($item['specialInstructions'] ?? ''));
            $finalPrice = $item['finalPrice'] ?? null;

            if ($serviceID <= 0 || $variantIDItem <= 0) {
                continue;
            }

            $detailStmt->execute([
                ':appointment_id' => $appointmentID,
                ':service_id' => $serviceID,
                ':variant_id' => $variantIDItem,
                ':selected_view' => $selectedView !== '' ? $selectedView : 'Front',
                ':final_price' => $finalPrice,
            ]);
        }

        $bookSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Booked'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $bookSlotStmt->execute([
            ':barber_id' => $barberID,
            ':slot_date' => $appointmentDate,
            ':slot_time' => $startTime,
        ]);

        $notifyCreateStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', :title, :message, TRUE)"
        );
        $notifyCreateStmt->execute([
            ':recipient_id' => $userID,
            ':title' => 'Appointment booked',
            ':message' => 'Your booking ' . $bookingCode . ' is scheduled on ' . $appointmentDate . ' at ' . $startTime . '.',
        ]);

        $pdo->commit();

        json_response([
            'message' => 'Appointment created',
            'appointmentID' => $appointmentID,
            'bookingCode' => $bookingCode,
            'status' => 'PendingPayment',
        ], 201);
    }

    if ($action === 'listByCustomer') {
        $userID = (int)($input['userID'] ?? 0);
        if ($userID <= 0) {
            json_response(['error' => 'Invalid userID'], 422);
        }

        $stmt = $pdo->prepare(
            "SELECT a.appointment_id, a.booking_code, a.appointment_date, a.start_time, a.end_time, a.status,
                    b.barber_id, b.full_name AS barber_name,
                    ap.status AS payment_status, ap.transaction_ref, ap.created_at AS paid_at,
                    pi.intent_id, pi.status AS intent_status, pi.method AS intent_method, pi.expires_at AS intent_expires_at,
                    pi.failure_reason, pi.updated_at AS intent_updated_at
             FROM appointments a
             JOIN barbers b ON a.barber_id = b.barber_id
             LEFT JOIN LATERAL (
                 SELECT payment_id, status, transaction_ref, created_at
                 FROM appointment_payments
                 WHERE appointment_id = a.appointment_id
                 ORDER BY payment_id DESC
                 LIMIT 1
             ) ap ON TRUE
             LEFT JOIN LATERAL (
                 SELECT intent_id, status, method, expires_at, failure_reason, updated_at
                 FROM appointment_payment_intents
                 WHERE appointment_id = a.appointment_id
                 ORDER BY intent_id DESC
                 LIMIT 1
             ) pi ON TRUE
             WHERE a.user_id = :user_id
             ORDER BY a.appointment_date DESC, a.start_time DESC"
        );
           $stmt->execute([':user_id' => $userID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            json_response(['appointments' => []]);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointment_id'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $serviceStmt = $pdo->prepare(
            "SELECT ad.appointment_id, ad.service_id, ad.variant_id, ad.final_price,
                    s.service_name, s.base_duration,
                    hs.style_name AS hairstyle_name
             FROM appointment_details ad
             JOIN services s ON ad.service_id = s.service_id
             LEFT JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
             LEFT JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
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
                'hairstyleName' => $row['hairstyle_name'],
                'variantID' => (int)($row['variant_id'] ?? 0),
                'durationMinutes' => (int)$row['base_duration'],
                'price' => (string)($row['final_price'] ?? '0'),
            ];
        }

        $appointments = array_map(function ($row) use ($serviceMap) {
            $aid = (int)$row['appointment_id'];
            $intentStatus = $row['intent_status'] !== null ? (string)$row['intent_status'] : null;
            $paymentStatus = $row['payment_status'] !== null ? (string)$row['payment_status'] : null;
            $paymentState = derive_payment_state($paymentStatus, $intentStatus);
            $canRetryPayment = in_array($paymentState, ['Unpaid', 'Failed'], true);
            if ($intentStatus === 'PendingGateway' && $row['intent_expires_at'] !== null) {
                $canRetryPayment = strtotime((string)$row['intent_expires_at']) < time();
            }
            return [
                'appointmentID' => $aid,
                'bookingCode' => $row['booking_code'],
                'appointmentDate' => $row['appointment_date'],
                'startTime' => $row['start_time'],
                'endTime' => $row['end_time'],
                'status' => $row['status'],
                'barberID' => (int)$row['barber_id'],
                'barberName' => $row['barber_name'],
                'paymentState' => $paymentState,
                'paymentStatus' => $paymentStatus,
                'receiptRef' => $row['transaction_ref'] !== null ? (string)$row['transaction_ref'] : null,
                'paidAt' => $row['paid_at'] !== null ? (string)$row['paid_at'] : null,
                'intentID' => $row['intent_id'] !== null ? (int)$row['intent_id'] : null,
                'intentStatus' => $intentStatus,
                'intentMethod' => $row['intent_method'] !== null ? (string)$row['intent_method'] : null,
                'intentExpiresAt' => $row['intent_expires_at'] !== null ? (string)$row['intent_expires_at'] : null,
                'intentFailureReason' => $row['failure_reason'] !== null ? (string)$row['failure_reason'] : null,
                'intentUpdatedAt' => $row['intent_updated_at'] !== null ? (string)$row['intent_updated_at'] : null,
                'canRetryPayment' => $canRetryPayment,
                'canReschedule' => $paymentState === 'Paid' && in_array((string)$row['status'], ['Scheduled', 'PendingPayment'], true),
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

        $apptStmt = $pdo->prepare(
            'SELECT appointment_id, user_id, barber_id, appointment_date, start_time, status
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }

        if ((string)$appt['status'] === 'Cancelled') {
            json_response(['message' => 'Appointment already cancelled']);
        }

        $pdo->beginTransaction();

        $stmt = $pdo->prepare(
            "UPDATE appointments
             SET status = 'Cancelled', updated_at = CURRENT_TIMESTAMP
             WHERE appointment_id = :appointment_id"
        );
        $stmt->execute([':appointment_id' => $appointmentID]);

        $releaseSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Available'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $releaseSlotStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => (string)$appt['appointment_date'],
            ':slot_time' => (string)$appt['start_time'],
        ]);

        $notifyCancelStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', 'Appointment cancelled', :message, TRUE)"
        );

        $notifyCancelStmt->execute([
            ':recipient_id' => (int)$appt['user_id'],
            ':message' => 'Your appointment on ' . (string)$appt['appointment_date'] . ' at ' . (string)$appt['start_time'] . ' was cancelled.',
        ]);

        $pdo->commit();

        json_response(['message' => 'Appointment cancelled']);
    }

    if ($action === 'reschedule') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $newDate = trim((string)($input['appointmentDate'] ?? ''));
        $newStartTimeRaw = trim((string)($input['startTime'] ?? ''));
        $newEndTimeRaw = trim((string)($input['endTime'] ?? ''));

        $newStartTime = normalize_time_string($newStartTimeRaw);
        $newEndTime = normalize_time_string($newEndTimeRaw);

        if ($appointmentID <= 0 || $newDate === '' || $newStartTime === null || $newEndTime === null) {
            json_response(['error' => 'Missing or invalid reschedule details'], 422);
        }

        if (!is_valid_ymd_date($newDate)) {
            json_response(['error' => 'Invalid appointmentDate format (expected YYYY-MM-DD).'], 422);
        }

        $newStartDt = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $newDate . ' ' . $newStartTime);
        $newEndDt = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $newDate . ' ' . $newEndTime);
        if ($newStartDt === false || $newEndDt === false || $newEndDt <= $newStartDt) {
            json_response(['error' => 'Invalid reschedule time range.'], 422);
        }
        if ($newStartDt < new DateTimeImmutable('now')) {
            json_response(['error' => 'Cannot reschedule to a past timeslot.'], 422);
        }

        $apptStmt = $pdo->prepare(
            'SELECT appointment_id, booking_code, user_id, barber_id, appointment_date, start_time, end_time, status
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }

        if (!in_array((string)$appt['status'], ['Scheduled', 'PendingPayment'], true)) {
            json_response(['error' => 'Only upcoming appointments can be rescheduled.'], 409);
        }

        $paidCheckStmt = $pdo->prepare(
            "SELECT COUNT(*)
             FROM appointment_payments
             WHERE appointment_id = :appointment_id
               AND status = 'Captured'"
        );
        $paidCheckStmt->execute([':appointment_id' => $appointmentID]);
        if ((int)$paidCheckStmt->fetchColumn() === 0) {
            json_response(['error' => 'Reschedule is allowed only after payment is confirmed.'], 409);
        }

        $overlapStmt = $pdo->prepare(
            "SELECT COUNT(*)
             FROM appointments
             WHERE barber_id = :barber_id
               AND appointment_date = :appointment_date
               AND appointment_id <> :appointment_id
               AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')
               AND (start_time < :end_time AND end_time > :start_time)"
        );
        $overlapStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':appointment_date' => $newDate,
            ':appointment_id' => $appointmentID,
            ':start_time' => $newStartTime,
            ':end_time' => $newEndTime,
        ]);
        if ((int)$overlapStmt->fetchColumn() > 0) {
            json_response(['error' => 'Selected time overlaps with another appointment for this barber.'], 409);
        }

        $slotCheckStmt = $pdo->prepare(
            "SELECT slot_id
             FROM time_slots
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time
               AND status = 'Available'
             LIMIT 1"
        );
        $slotCheckStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => $newDate,
            ':slot_time' => $newStartTime,
        ]);
        if (!$slotCheckStmt->fetch()) {
            json_response(['error' => 'Target slot is not available anymore.'], 409);
        }

        $pdo->beginTransaction();

        $releaseOldSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Available'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $releaseOldSlotStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => (string)$appt['appointment_date'],
            ':slot_time' => (string)$appt['start_time'],
        ]);

        $bookNewSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Booked'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $bookNewSlotStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => $newDate,
            ':slot_time' => $newStartTime,
        ]);

        $updateApptStmt = $pdo->prepare(
            "UPDATE appointments
             SET appointment_date = :appointment_date,
                 start_time = :start_time,
                 end_time = :end_time,
                 status = 'Scheduled',
                 updated_at = CURRENT_TIMESTAMP
             WHERE appointment_id = :appointment_id"
        );
        $updateApptStmt->execute([
            ':appointment_date' => $newDate,
            ':start_time' => $newStartTime,
            ':end_time' => $newEndTime,
            ':appointment_id' => $appointmentID,
        ]);

        $notifyStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', :title, :message, TRUE)"
        );
        $notifyStmt->execute([
            ':recipient_id' => (int)$appt['user_id'],
            ':title' => 'Appointment rescheduled',
            ':message' => 'Booking ' . (string)$appt['booking_code'] . ' was moved to ' . $newDate . ' at ' . $newStartTime . '.',
        ]);

        $pdo->commit();

        json_response([
            'message' => 'Appointment rescheduled successfully.',
            'appointmentID' => $appointmentID,
            'appointmentDate' => $newDate,
            'startTime' => $newStartTime,
            'endTime' => $newEndTime,
            'status' => 'Scheduled',
        ]);
    }

    if ($action === 'listByBarber') {
        $barberID = (int)($input['barberID'] ?? 0);
        if ($barberID <= 0) {
            json_response(['error' => 'Invalid barberID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT a.appointment_id, a.booking_code, a.appointment_date, a.start_time, a.end_time, a.status,
                    u.user_id AS customer_id, u.full_name AS customer_name
             FROM appointments a
             JOIN users u ON a.user_id = u.user_id
             WHERE a.barber_id = :barber_id
             ORDER BY a.appointment_date DESC, a.start_time DESC'
        );
        $stmt->execute([':barber_id' => $barberID]);
        $appointments = $stmt->fetchAll();

        $appointments = array_map(function ($row) {
            return [
                'appointmentID' => (int)$row['appointment_id'],
                'bookingCode' => $row['booking_code'],
                'appointmentDate' => $row['appointment_date'],
                'startTime' => $row['start_time'],
                'endTime' => $row['end_time'],
                'status' => $row['status'],
                'customerID' => (int)$row['customer_id'],
                'customerName' => $row['customer_name'],
            ];
        }, $appointments);

        json_response(['appointments' => $appointments]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response([
        'error' => 'Server error',
        'details' => $e->getMessage(),
        'line' => $e->getLine(),
        'file' => basename((string)$e->getFile()),
    ], 500);
}
