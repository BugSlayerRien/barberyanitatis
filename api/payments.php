<?php
// Payments API (payment intent flow + mock gateway compatibility)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

$allowed = ['createIntent', 'getIntentStatus', 'mockProviderWebhook', 'listWallet', 'capturePayment', 'confirmGatewayPayment'];
if (!in_array($action, $allowed, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

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

function get_appointment(PDO $pdo, int $appointmentID): array
{
    $stmt = $pdo->prepare(
        'SELECT appointment_id, user_id, booking_code, status
         FROM appointments
         WHERE appointment_id = :appointment_id
         LIMIT 1'
    );
    $stmt->execute([':appointment_id' => $appointmentID]);
    $row = $stmt->fetch();
    if (!$row) {
        json_response(['error' => 'Appointment not found'], 404);
    }
    return $row;
}

function get_latest_payment(PDO $pdo, int $appointmentID): ?array
{
    $stmt = $pdo->prepare(
        "SELECT payment_id, status, transaction_ref, created_at
         FROM appointment_payments
         WHERE appointment_id = :appointment_id
         ORDER BY payment_id DESC
         LIMIT 1"
    );
    $stmt->execute([':appointment_id' => $appointmentID]);
    $row = $stmt->fetch();
    return $row ?: null;
}

function get_latest_intent(PDO $pdo, int $appointmentID): ?array
{
    $stmt = $pdo->prepare(
        "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                failure_reason, expires_at, paid_at, created_at, updated_at
         FROM appointment_payment_intents
         WHERE appointment_id = :appointment_id
         ORDER BY intent_id DESC
         LIMIT 1"
    );
    $stmt->execute([':appointment_id' => $appointmentID]);
    $row = $stmt->fetch();
    return $row ?: null;
}

function build_payment_state(?array $payment, ?array $intent): string
{
    $paymentStatus = $payment ? trim((string)$payment['status']) : '';
    if ($paymentStatus !== '' && in_array(strtolower($paymentStatus), ['captured', 'paid', 'succeeded'], true)) {
        return 'Paid';
    }

    if ($intent) {
        $intentStatus = trim((string)$intent['status']);
        if (in_array($intentStatus, ['PendingGateway', 'Verifying', 'Processing'], true)) {
            return 'Verifying';
        }
        if (in_array($intentStatus, ['Failed', 'Expired', 'Cancelled'], true)) {
            return 'Failed';
        }
        if (in_array(strtolower($intentStatus), ['paid', 'succeeded', 'captured'], true)) {
            return 'Paid';
        }
    }

    return 'Unpaid';
}

function to_intent_payload(array $intent, string $paymentState): array
{
    return [
        'intentID' => (int)$intent['intent_id'],
        'appointmentID' => (int)$intent['appointment_id'],
        'amount' => (float)$intent['amount'],
        'method' => (string)$intent['method'],
        'provider' => (string)$intent['provider'],
        'status' => (string)$intent['status'],
        'intentToken' => (string)$intent['intent_token'],
        'providerRef' => $intent['provider_ref'] !== null ? (string)$intent['provider_ref'] : null,
        'failureReason' => $intent['failure_reason'] !== null ? (string)$intent['failure_reason'] : null,
        'expiresAt' => (string)$intent['expires_at'],
        'paidAt' => $intent['paid_at'] !== null ? (string)$intent['paid_at'] : null,
        'paymentState' => $paymentState,
    ];
}

function finalize_paid_intent(PDO $pdo, array $intent, array $appointment, string $method): array
{
    $latestPayment = get_latest_payment($pdo, (int)$intent['appointment_id']);
    if ($latestPayment && (string)$latestPayment['status'] === 'Captured') {
        return $latestPayment;
    }

    $paymentInsertStmt = $pdo->prepare(
        'INSERT INTO appointment_payments (appointment_id, amount, method, status, transaction_ref)
         VALUES (:appointment_id, :amount, :method, :status, :transaction_ref)
         RETURNING payment_id, status, transaction_ref, created_at'
    );
    $paymentInsertStmt->execute([
        ':appointment_id' => (int)$intent['appointment_id'],
        ':amount' => round((float)$intent['amount'], 2),
        ':method' => $method !== '' ? $method : (string)$intent['method'],
        ':status' => 'Captured',
        ':transaction_ref' => 'TXN-' . strtoupper(bin2hex(random_bytes(6))),
    ]);
    $payment = $paymentInsertStmt->fetch();

    $appointmentUpdateStmt = $pdo->prepare(
        "UPDATE appointments
         SET status = 'Scheduled', updated_at = CURRENT_TIMESTAMP
         WHERE appointment_id = :appointment_id"
    );
    $appointmentUpdateStmt->execute([':appointment_id' => (int)$intent['appointment_id']]);

    $notifyStmt = $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
         VALUES ('User', :recipient_id, 'Payment', :title, :message, TRUE)"
    );
    $notifyStmt->execute([
        ':recipient_id' => (int)$appointment['user_id'],
        ':title' => 'Payment received',
        ':message' => 'Payment for booking ' . (string)$appointment['booking_code'] . ' has been verified. Your appointment is now confirmed.',
    ]);

    return $payment;
}

try {
    $pdo = get_db_connection();
    ensure_financial_tables($pdo);

    if ($action === 'listWallet') {
        $userID = (int)($input['userID'] ?? 0);
        if ($userID <= 0) {
            json_response(['error' => 'Invalid userID'], 422);
        }

        $stmt = $pdo->prepare(
            "SELECT a.appointment_id, a.booking_code, a.appointment_date, a.start_time,
                    ap.payment_id, ap.status AS payment_status, ap.transaction_ref, ap.amount AS paid_amount, ap.created_at AS paid_at,
                    pi.intent_id, pi.status AS intent_status, pi.method AS intent_method, pi.failure_reason, pi.expires_at, pi.created_at AS intent_created_at
             FROM appointments a
             LEFT JOIN LATERAL (
                 SELECT payment_id, status, transaction_ref, amount, created_at
                 FROM appointment_payments
                 WHERE appointment_id = a.appointment_id
                 ORDER BY payment_id DESC
                 LIMIT 1
             ) ap ON TRUE
             LEFT JOIN LATERAL (
                 SELECT intent_id, status, method, failure_reason, expires_at, created_at
                 FROM appointment_payment_intents
                 WHERE appointment_id = a.appointment_id
                 ORDER BY intent_id DESC
                 LIMIT 1
             ) pi ON TRUE
             WHERE a.user_id = :user_id
             ORDER BY a.appointment_date DESC, a.start_time DESC
             LIMIT 40"
        );
        $stmt->execute([':user_id' => $userID]);
        $rows = $stmt->fetchAll();

        $history = array_map(static function ($row) {
            $payment = null;
            if ($row['payment_id'] !== null) {
                $payment = [
                    'status' => (string)$row['payment_status'],
                ];
            }
            $intent = null;
            if ($row['intent_id'] !== null) {
                $intent = [
                    'status' => (string)$row['intent_status'],
                ];
            }

            $state = build_payment_state($payment, $intent);
            $ref = $row['transaction_ref'] !== null ? (string)$row['transaction_ref'] : ((int)($row['intent_id'] ?? 0) > 0 ? 'INTENT-' . (string)$row['intent_id'] : null);
            return [
                'appointmentID' => (int)$row['appointment_id'],
                'bookingCode' => (string)$row['booking_code'],
                'appointmentDate' => (string)$row['appointment_date'],
                'appointmentTime' => (string)$row['start_time'],
                'paymentState' => $state,
                'receiptRef' => $ref,
                'amount' => $row['paid_amount'] !== null ? (float)$row['paid_amount'] : null,
                'method' => $row['intent_method'] !== null ? (string)$row['intent_method'] : null,
                'failedReason' => $row['failure_reason'] !== null ? (string)$row['failure_reason'] : null,
                'updatedAt' => $row['paid_at'] !== null ? (string)$row['paid_at'] : ($row['intent_created_at'] !== null ? (string)$row['intent_created_at'] : null),
            ];
        }, $rows);

        json_response(['history' => $history]);
    }

    if ($action === 'createIntent' || $action === 'capturePayment') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $amount = (float)($input['amount'] ?? 0);
        $method = trim((string)($input['method'] ?? 'Card'));
        $provider = trim((string)($input['provider'] ?? 'mock'));
        $expiresMinutes = (int)($input['expiresMinutes'] ?? 10);
        if ($expiresMinutes < 3 || $expiresMinutes > 30) {
            $expiresMinutes = 10;
        }

        if ($appointmentID <= 0 || $amount <= 0) {
            json_response(['error' => 'Invalid appointmentID or amount'], 422);
        }

        $appointment = get_appointment($pdo, $appointmentID);
        $latestPayment = get_latest_payment($pdo, $appointmentID);
        if ($latestPayment && (string)$latestPayment['status'] === 'Captured') {
            json_response([
                'message' => 'Payment already completed.',
                'paymentState' => 'Paid',
                'status' => 'Scheduled',
                'receiptRef' => (string)$latestPayment['transaction_ref'],
            ]);
        }

        $status = (string)$appointment['status'];
        if (!in_array($status, ['PendingPayment', 'Scheduled'], true)) {
            json_response(['error' => 'Appointment cannot be paid in its current status'], 409);
        }

        $expireStmt = $pdo->prepare(
            "UPDATE appointment_payment_intents
             SET status = 'Expired', updated_at = NOW()
             WHERE appointment_id = :appointment_id
               AND status IN ('PendingGateway', 'Verifying')
               AND expires_at < NOW()"
        );
        $expireStmt->execute([':appointment_id' => $appointmentID]);

        $existingStmt = $pdo->prepare(
            "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                    failure_reason, expires_at, paid_at, created_at, updated_at
             FROM appointment_payment_intents
             WHERE appointment_id = :appointment_id
               AND status IN ('PendingGateway', 'Verifying')
               AND expires_at > NOW()
             ORDER BY intent_id DESC
             LIMIT 1"
        );
        $existingStmt->execute([':appointment_id' => $appointmentID]);
        $existing = $existingStmt->fetch();
        if ($existing) {
            json_response([
                'message' => 'Payment intent already active.',
                'intent' => to_intent_payload($existing, build_payment_state(null, $existing)),
            ]);
        }

        $intentToken = 'pi_' . bin2hex(random_bytes(12));
        $insertStmt = $pdo->prepare(
            'INSERT INTO appointment_payment_intents (
                appointment_id, amount, method, provider, status, intent_token, expires_at, updated_at
             ) VALUES (
                     :appointment_id, :amount, :method, :provider, :status, :intent_token, NOW() + make_interval(mins => :expires_minutes::int), NOW()
             )
             RETURNING intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                       failure_reason, expires_at, paid_at, created_at, updated_at'
        );
        $insertStmt->execute([
            ':appointment_id' => $appointmentID,
            ':amount' => round($amount, 2),
            ':method' => $method !== '' ? $method : 'Card',
            ':provider' => $provider !== '' ? $provider : 'mock',
            ':status' => 'PendingGateway',
            ':intent_token' => $intentToken,
            ':expires_minutes' => (string)$expiresMinutes,
        ]);
        $intent = $insertStmt->fetch();

        $notifyStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Payment', :title, :message, TRUE)"
        );
        $notifyStmt->execute([
            ':recipient_id' => (int)$appointment['user_id'],
            ':title' => 'Payment started',
            ':message' => 'Payment intent created for booking ' . (string)$appointment['booking_code'] . '. Please complete checkout before expiry.',
        ]);

        // Log payment intent creation to audit trail
        audit_log($pdo, 'CREATE_INTENT', 'appointment_payment_intents', (string)$intent['intent_id'], null, [
            'appointment_id' => $appointmentID,
            'amount' => round($amount, 2),
            'method' => $method,
            'provider' => $provider,
            'status' => 'PendingGateway',
        ], (int)$appointment['user_id']);

        json_response([
            'message' => 'Payment intent created.',
            'intent' => to_intent_payload($intent, 'Verifying'),
            'gatewayMode' => 'mock',
        ]);
    }

    if ($action === 'confirmGatewayPayment') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $providerRef = trim((string)($input['providerRef'] ?? ''));
        if ($appointmentID <= 0) {
            json_response(['error' => 'Invalid appointmentID'], 422);
        }

        $appointment = get_appointment($pdo, $appointmentID);
        $latestPayment = get_latest_payment($pdo, $appointmentID);
        if ($latestPayment && (string)$latestPayment['status'] === 'Captured') {
            json_response([
                'message' => 'Payment already captured.',
                'paymentState' => 'Paid',
                'receiptRef' => (string)$latestPayment['transaction_ref'],
            ]);
        }

        if ($providerRef !== '') {
            $stmt = $pdo->prepare(
                "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                        failure_reason, expires_at, paid_at, created_at, updated_at
                 FROM appointment_payment_intents
                 WHERE appointment_id = :appointment_id
                    OR CAST(intent_token AS TEXT) = :provider_ref
                    OR CAST(provider_ref AS TEXT) = :provider_ref
                 ORDER BY intent_id DESC
                 LIMIT 1"
            );
            $stmt->execute([
                ':appointment_id' => $appointmentID,
                ':provider_ref' => $providerRef,
            ]);
            $intent = $stmt->fetch() ?: null;
        } else {
            $intent = get_latest_intent($pdo, $appointmentID);
        }

        if (!$intent) {
            json_response(['error' => 'Payment intent not found for this appointment'], 404);
        }

        if ((string)$intent['status'] === 'Paid') {
            $latestPayment = get_latest_payment($pdo, $appointmentID);
            if ($latestPayment && (string)$latestPayment['status'] === 'Captured') {
                json_response([
                    'message' => 'Payment already finalized.',
                    'paymentState' => 'Paid',
                    'receiptRef' => (string)$latestPayment['transaction_ref'],
                ]);
            }
        }

        $pdo->beginTransaction();
        try {
            $updStmt = $pdo->prepare(
                "UPDATE appointment_payment_intents
                 SET status = 'Paid',
                     provider_ref = CASE
                         WHEN :provider_ref <> '' THEN :provider_ref
                         ELSE provider_ref
                     END,
                     paid_at = COALESCE(paid_at, NOW()),
                     updated_at = NOW()
                 WHERE intent_id = :intent_id"
            );
            $updStmt->execute([
                ':provider_ref' => $providerRef,
                ':intent_id' => (int)$intent['intent_id'],
            ]);

            $intent['status'] = 'Paid';
            $payment = finalize_paid_intent($pdo, $intent, $appointment, (string)$intent['method']);
            $pdo->commit();

            json_response([
                'message' => 'Payment verified and captured.',
                'paymentState' => 'Paid',
                'receiptRef' => (string)$payment['transaction_ref'],
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            json_response(['error' => 'Failed to finalize payment', 'details' => $e->getMessage()], 500);
        }
    }

    if ($action === 'getIntentStatus') {
        $intentID = (int)($input['intentID'] ?? 0);
        $appointmentID = (int)($input['appointmentID'] ?? 0);

        if ($intentID <= 0 && $appointmentID <= 0) {
            json_response(['error' => 'intentID or appointmentID is required'], 422);
        }

        if ($intentID > 0) {
            $stmt = $pdo->prepare(
                "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                        failure_reason, expires_at, paid_at, created_at, updated_at
                 FROM appointment_payment_intents
                 WHERE intent_id = :intent_id
                 LIMIT 1"
            );
            $stmt->execute([':intent_id' => $intentID]);
            $intent = $stmt->fetch();
            if (!$intent) {
                json_response(['error' => 'Intent not found'], 404);
            }
            $appointmentID = (int)$intent['appointment_id'];
        } else {
            $intent = get_latest_intent($pdo, $appointmentID);
            if (!$intent) {
                json_response(['paymentState' => 'Unpaid', 'intent' => null]);
            }
        }

        if ((string)$intent['status'] === 'PendingGateway' && strtotime((string)$intent['expires_at']) < time()) {
            $upd = $pdo->prepare(
                "UPDATE appointment_payment_intents
                 SET status = 'Expired', updated_at = NOW()
                 WHERE intent_id = :intent_id"
            );
            $upd->execute([':intent_id' => (int)$intent['intent_id']]);
            $intent['status'] = 'Expired';
        }

        $latestPayment = get_latest_payment($pdo, $appointmentID);
        $paymentState = build_payment_state($latestPayment, $intent);

        json_response([
            'paymentState' => $paymentState,
            'intent' => to_intent_payload($intent, $paymentState),
            'receiptRef' => $latestPayment ? (string)$latestPayment['transaction_ref'] : null,
        ]);
    }

    if ($action === 'mockProviderWebhook') {
        $intentToken = trim((string)($input['intentToken'] ?? ''));
        $intentID = (int)($input['intentID'] ?? 0);
        $outcome = strtolower(trim((string)($input['outcome'] ?? 'paid')));
        $providerRef = trim((string)($input['providerRef'] ?? ''));

        if ($intentToken === '' && $intentID <= 0) {
            json_response(['error' => 'intentToken or intentID is required'], 422);
        }

        if (!in_array($outcome, ['paid', 'failed'], true)) {
            json_response(['error' => 'Invalid outcome'], 422);
        }

        if ($intentID > 0) {
            $stmt = $pdo->prepare(
                "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                        failure_reason, expires_at, paid_at, created_at, updated_at
                 FROM appointment_payment_intents
                 WHERE intent_id = :intent_id
                 LIMIT 1"
            );
            $stmt->execute([':intent_id' => $intentID]);
        } else {
            $stmt = $pdo->prepare(
                "SELECT intent_id, appointment_id, amount, method, provider, status, intent_token, provider_ref,
                        failure_reason, expires_at, paid_at, created_at, updated_at
                 FROM appointment_payment_intents
                 WHERE intent_token = :intent_token
                 LIMIT 1"
            );
            $stmt->execute([':intent_token' => $intentToken]);
        }
        $intent = $stmt->fetch();
        if (!$intent) {
            json_response(['error' => 'Intent not found'], 404);
        }

        $appointment = get_appointment($pdo, (int)$intent['appointment_id']);

        if (in_array((string)$intent['status'], ['Paid', 'Failed', 'Expired', 'Cancelled'], true)) {
            $latestPayment = get_latest_payment($pdo, (int)$intent['appointment_id']);
            $state = build_payment_state($latestPayment, $intent);
            json_response([
                'message' => 'Intent already finalized.',
                'paymentState' => $state,
                'intent' => to_intent_payload($intent, $state),
                'receiptRef' => $latestPayment ? (string)$latestPayment['transaction_ref'] : null,
            ]);
        }

        if (strtotime((string)$intent['expires_at']) < time() && $outcome !== 'paid') {
            $expStmt = $pdo->prepare(
                "UPDATE appointment_payment_intents
                 SET status = 'Expired', updated_at = NOW()
                 WHERE intent_id = :intent_id"
            );
            $expStmt->execute([':intent_id' => (int)$intent['intent_id']]);
            $intent['status'] = 'Expired';
            json_response([
                'message' => 'Intent expired.',
                'paymentState' => 'Failed',
                'intent' => to_intent_payload($intent, 'Failed'),
            ]);
        }

        $pdo->beginTransaction();

        if ($outcome === 'paid') {
            $updStmt = $pdo->prepare(
                "UPDATE appointment_payment_intents
                 SET status = 'Paid', provider_ref = :provider_ref, paid_at = NOW(), updated_at = NOW()
                 WHERE intent_id = :intent_id"
            );
            $updStmt->execute([
                ':provider_ref' => $providerRef !== '' ? $providerRef : ('MOCK-' . strtoupper(bin2hex(random_bytes(4)))),
                ':intent_id' => (int)$intent['intent_id'],
            ]);

            $payment = finalize_paid_intent($pdo, $intent, $appointment, (string)$intent['method']);

            // Log payment completion to audit trail
            audit_log($pdo, 'PAYMENT_CAPTURED', 'appointment_payment_intents', (string)$intent['intent_id'], [
                'status' => 'Verifying',
            ], [
                'status' => 'Paid',
                'provider_ref' => $providerRef !== '' ? $providerRef : ('MOCK-' . strtoupper(bin2hex(random_bytes(4)))),
            ], (int)$appointment['user_id']);

            $pdo->commit();

            $intent = get_latest_intent($pdo, (int)$intent['appointment_id']);
            json_response([
                'message' => 'Payment verified and captured.',
                'paymentState' => 'Paid',
                'intent' => to_intent_payload($intent, 'Paid'),
                'receiptRef' => (string)$payment['transaction_ref'],
            ]);
        }

        $updStmt = $pdo->prepare(
            "UPDATE appointment_payment_intents
             SET status = 'Failed', failure_reason = :failure_reason, provider_ref = :provider_ref, updated_at = NOW()
             WHERE intent_id = :intent_id"
        );
        $updStmt->execute([
            ':failure_reason' => (string)($input['failureReason'] ?? 'Payment failed on provider side.'),
            ':provider_ref' => $providerRef !== '' ? $providerRef : ('MOCK-' . strtoupper(bin2hex(random_bytes(4)))),
            ':intent_id' => (int)$intent['intent_id'],
        ]);

        $notifyStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Payment', :title, :message, TRUE)"
        );
        $notifyStmt->execute([
            ':recipient_id' => (int)$appointment['user_id'],
            ':title' => 'Payment failed',
            ':message' => 'Payment for booking ' . (string)$appointment['booking_code'] . ' failed. You can retry payment before your slot expires.',
        ]);

        // Log payment failure to audit trail
        audit_log($pdo, 'PAYMENT_FAILED', 'appointment_payment_intents', (string)$intent['intent_id'], [
            'status' => 'Verifying',
        ], [
            'status' => 'Failed',
            'failure_reason' => (string)($input['failureReason'] ?? 'Payment failed on provider side.'),
        ], (int)$appointment['user_id']);

        $pdo->commit();

        $intent = get_latest_intent($pdo, (int)$intent['appointment_id']);
        json_response([
            'message' => 'Payment marked as failed.',
            'paymentState' => 'Failed',
            'intent' => to_intent_payload($intent, 'Failed'),
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Unexpected error', 'details' => $e->getMessage()], 500);
}
