<?php

declare(strict_types=1);

/**
 * Recovers appointments whose customer paid but whose payment was never
 * recorded here.
 *
 * The normal flow depends on the phone: payment_page.dart polls
 * paymongo/payment-status.php and then calls payments.php confirmGatewayPayment.
 * If that poll never finishes -- the connection drops on the way back from
 * GCash, the app is killed, the customer closes it -- nothing on this side ever
 * learns the money moved. The intent row stays 'PendingGateway', the
 * appointment stays 'PendingPayment', and the customer is asked to pay a second
 * time for a booking they already paid for.
 *
 * This asks PayMongo directly about intents still waiting, and finishes the job
 * the app started. A GCash source that the customer authorised sits at
 * 'chargeable' until a Payment is created against it, so this also performs
 * that capture -- otherwise the authorisation simply lapses and the shop never
 * gets paid.
 *
 * Runs from the customer booking list (booking.php), throttled, and is a no-op
 * when PAYMONGO_SECRET is absent.
 */

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/schema_cache.php';
require_once __DIR__ . '/slot_locking.php';
require_once __DIR__ . '/paymongo/paymongo_client.php';

/** Statuses that mean "still waiting on the gateway", so worth re-checking. */
const PAYMONGO_RECONCILE_OPEN_STATUSES = ['pendinggateway', 'pending', 'awaiting_payment_method', 'processing'];

function paymongo_reconcile_enabled(): bool
{
    $secret = getenv('PAYMONGO_SECRET') ?: ($_ENV['PAYMONGO_SECRET'] ?? '');

    return trim((string)$secret) !== '';
}

/**
 * @return array{status: string, raw: array}|null
 */
function paymongo_reconcile_fetch_resource(string $providerRef): ?array
{
    $isSource = str_starts_with($providerRef, 'src_');
    $path = $isSource
        ? '/sources/' . rawurlencode($providerRef)
        : '/payment_intents/' . rawurlencode($providerRef);

    $resp = paymongo_request('GET', $path);
    $code = (int)($resp['http_code'] ?? 0);
    if ($code < 200 || $code >= 300) {
        return null;
    }

    $data = $resp['body']['data'] ?? null;
    if (!is_array($data)) {
        return null;
    }

    return [
        'status' => strtolower((string)($data['attributes']['status'] ?? '')),
        'raw' => $data,
    ];
}

/**
 * Captures an authorised ('chargeable') GCash source. Mirrors
 * paymongo/payment-status.php's own source-to-payment conversion rather than
 * inventing a second one; that file is an endpoint and cannot be included here.
 *
 * @return bool True when the resulting payment is paid.
 */
function paymongo_reconcile_capture_source(array $sourceData): bool
{
    $attributes = $sourceData['attributes'] ?? [];
    $sourceId = $sourceData['id'] ?? null;
    $amount = isset($attributes['amount']) ? (int)$attributes['amount'] : 0;
    if (!$sourceId || $amount <= 0) {
        return false;
    }

    $payload = [
        'data' => [
            'attributes' => [
                'amount' => $amount,
                'currency' => isset($attributes['currency'])
                    ? strtoupper((string)$attributes['currency'])
                    : 'PHP',
                'description' => (string)($attributes['description'] ?? 'Appointment payment'),
                'source' => ['id' => $sourceId, 'type' => 'source'],
            ],
        ],
    ];
    if (!empty($attributes['metadata']) && is_array($attributes['metadata'])) {
        $payload['data']['attributes']['metadata'] = $attributes['metadata'];
    }

    $resp = paymongo_request('POST', '/payments', $payload);
    $code = (int)($resp['http_code'] ?? 0);
    if ($code < 200 || $code >= 300) {
        return false;
    }

    $status = strtolower((string)($resp['body']['data']['attributes']['status'] ?? ''));

    return in_array($status, ['paid', 'succeeded'], true);
}

/** Records the payment and promotes the booking, both idempotent. */
function paymongo_reconcile_mark_paid(PDO $pdo, int $appointmentId, int $intentId, string $providerRef, float $amount, string $method): void
{
    $pdo->prepare(
        "UPDATE appointment_payment_intents
         SET status = 'Paid'
         WHERE intent_id = :intent_id"
    )->execute([':intent_id' => $intentId]);

    $exists = $pdo->prepare(
        'SELECT payment_id FROM appointment_payments WHERE transaction_ref = :ref LIMIT 1'
    );
    $exists->execute([':ref' => $providerRef]);
    if ($exists->fetchColumn() === false) {
        $pdo->prepare(
            "INSERT INTO appointment_payments (appointment_id, amount, method, status, transaction_ref)
             VALUES (:appointment_id, :amount, :method, 'Captured', :ref)"
        )->execute([
            ':appointment_id' => $appointmentId,
            ':amount' => $amount,
            ':method' => $method !== '' ? $method : 'gcash',
            ':ref' => $providerRef,
        ]);
    }

    promote_paid_booking_unit($pdo, $appointmentId);
}

/**
 * @param int $maxChecks Cap on gateway calls per sweep, so a backlog can never
 *                       stall a customer's booking list.
 */
function reconcile_pending_gateway_payments(PDO $pdo, int $maxChecks = 5): void
{
    if (!paymongo_reconcile_enabled()) {
        return;
    }
    if (!schema_cache_should_run('reconcile_pending_gateway_payments', 120)) {
        return;
    }

    try {
        $stmt = $pdo->prepare(
            "SELECT i.intent_id, i.appointment_id, i.provider_ref, i.amount, i.method, i.status
             FROM appointment_payment_intents i
             INNER JOIN appointments a ON a.appointment_id = i.appointment_id
             WHERE a.status = 'PendingPayment'
               AND i.provider_ref IS NOT NULL
               AND i.provider_ref <> ''
               AND i.created_at > NOW() - INTERVAL '3 days'
             ORDER BY i.created_at DESC
             LIMIT :limit"
        );
        $stmt->bindValue(':limit', $maxChecks, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as $row) {
            $status = strtolower(trim((string)($row['status'] ?? '')));
            if (!in_array($status, PAYMONGO_RECONCILE_OPEN_STATUSES, true)) {
                continue;
            }

            $providerRef = (string)$row['provider_ref'];
            $resource = paymongo_reconcile_fetch_resource($providerRef);
            if ($resource === null) {
                continue;
            }

            $paid = in_array($resource['status'], ['paid', 'succeeded'], true);
            if (!$paid && $resource['status'] === 'chargeable') {
                // Customer authorised in GCash but the capture never happened.
                $paid = paymongo_reconcile_capture_source($resource['raw']);
            }

            if ($paid) {
                paymongo_reconcile_mark_paid(
                    $pdo,
                    (int)$row['appointment_id'],
                    (int)$row['intent_id'],
                    $providerRef,
                    (float)($row['amount'] ?? 0),
                    (string)($row['method'] ?? '')
                );
                continue;
            }

            if (in_array($resource['status'], ['failed', 'expired', 'cancelled', 'canceled'], true)) {
                $pdo->prepare(
                    "UPDATE appointment_payment_intents
                     SET status = 'Failed'
                     WHERE intent_id = :intent_id"
                )->execute([':intent_id' => (int)$row['intent_id']]);
            }
        }
    } catch (Throwable $e) {
        error_log('Gateway reconcile skipped: ' . $e->getMessage());
    }

    reconcile_pending_credit_purchases($pdo, $maxChecks);

    schema_cache_done('reconcile_pending_gateway_payments');
}

/**
 * The same safety net, for AI credit purchases.
 *
 * The sweep above joins appointments, and a credit purchase has no appointment
 * -- so bookings had a recovery path and purchases had none. A customer who
 * took longer in GCash than the app's foreground poll lost the credits with
 * nothing anywhere to notice.
 */
function reconcile_pending_credit_purchases(PDO $pdo, int $maxChecks = 5): void
{
    try {
        require_once __DIR__ . '/ai_tryon_provider.php';
        schema_ensure_once('ai_credit_columns', static function () use ($pdo): void {
            ensure_ai_credit_columns($pdo);
        });

        $stmt = $pdo->prepare(
            "SELECT i.intent_id, i.provider_ref, i.amount, i.method, i.status,
                    i.user_id, i.credits
             FROM appointment_payment_intents i
             WHERE i.purpose = 'ai_credits'
               AND i.user_id IS NOT NULL
               AND i.provider_ref IS NOT NULL
               AND i.provider_ref <> ''
               AND i.created_at > NOW() - INTERVAL '3 days'
               -- Not yet settled into a credit row. This is the real test: an
               -- intent marked Paid with no payment row is exactly the state
               -- the old webhook left behind, and it still owes credits.
               AND NOT EXISTS (
                   SELECT 1 FROM appointment_payments p
                   WHERE p.transaction_ref = i.provider_ref
                     AND p.purpose = 'ai_credits'
               )
             ORDER BY i.created_at DESC
             LIMIT :limit"
        );
        $stmt->bindValue(':limit', $maxChecks, PDO::PARAM_INT);
        $stmt->execute();
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        foreach ($rows as $row) {
            $providerRef = (string)$row['provider_ref'];
            $resource = paymongo_reconcile_fetch_resource($providerRef);
            if ($resource === null) {
                continue;
            }

            $paid = in_array($resource['status'], ['paid', 'succeeded'], true);
            if (!$paid && $resource['status'] === 'chargeable') {
                $paid = paymongo_reconcile_capture_source($resource['raw']);
            }

            if (!$paid) {
                continue;
            }

            // Hand it to the one settlement implementation rather than writing
            // a credit row here, so there is still only one place that grants.
            require_once __DIR__ . '/paymongo/paymongo_settlement.php';
            paymongo_finalize_successful_payment($pdo, $providerRef, null);

            error_log('Recovered AI credit purchase ' . $providerRef
                . ' for user ' . (int)$row['user_id']);
        }
    } catch (Throwable $e) {
        error_log('Credit reconcile skipped: ' . $e->getMessage());
    }
}
