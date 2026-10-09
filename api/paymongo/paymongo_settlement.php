<?php
// Shared PayMongo settlement logic.
//
// These functions used to live inside payment-status.php, with webhook.php
// carrying its own near-duplicate copy. The copies had drifted: the webhook's
// sync_payment_row() returned early on a NULL appointment_id -- which is every
// AI-credit purchase -- while still marking the intent Paid, so the customer
// was charged, the database said paid, and the credits never arrived. One
// implementation, used by both, is the only way that stays fixed.

declare(strict_types=1);

require_once __DIR__ . '/paymongo_client.php';
require_once __DIR__ . '/../db.php';
// ai_tryon_provider.php is required lazily inside the credit branch below, as it
// was before the extraction -- it is only needed when a purchase is settling.

function paymongo_update_table_status(PDO $pdo, string $tableName, string $externalId, string $status, ?string $metadataRef = null): int {
    $colStmt = $pdo->prepare("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = :table");
    $colStmt->execute(['table' => $tableName]);
    $cols = $colStmt->fetchAll(PDO::FETCH_COLUMN);
    $cols = is_array($cols) ? $cols : [];
    if (empty($cols)) {
        return 0;
    }

    $colSet = array_fill_keys($cols, true);

    $statusCol = null;
    foreach (['payment_state', 'payment_status', 'intent_status', 'status'] as $candidate) {
        if (isset($colSet[$candidate])) {
            $statusCol = $candidate;
            break;
        }
    }
    if (!$statusCol) {
        return 0;
    }

    $updatedAtSql = isset($colSet['updated_at']) ? ', updated_at = NOW()' : '';
    $paidAtSql = '';
    if (isset($colSet['paid_at']) && in_array(strtolower($status), ['paid', 'succeeded'], true)) {
        $paidAtSql = ', paid_at = NOW()';
    }

    $whereByExternal = [];
    foreach (['intent_id', 'paymongo_intent_id', 'external_reference', 'order_reference', 'source_id', 'paymongo_source_id', 'provider_ref', 'intent_token', 'transaction_ref'] as $candidate) {
        if (isset($colSet[$candidate])) {
            $whereByExternal[] = "CAST($candidate AS TEXT) = :external";
        }
    }

    if (!empty($whereByExternal)) {
        $sql = "UPDATE {$tableName} SET {$statusCol} = :status{$updatedAtSql}{$paidAtSql} WHERE " . implode(' OR ', $whereByExternal);
        $stmt = $pdo->prepare($sql);
        $stmt->execute(['status' => $status, 'external' => $externalId]);
        $affected = $stmt->rowCount();
        if ($affected > 0) {
            return $affected;
        }
    }

    if ($metadataRef) {
        $whereByMeta = [];
        foreach (['appointment_id', 'order_id', 'id', 'external_reference', 'order_reference'] as $candidate) {
            if (isset($colSet[$candidate])) {
                $whereByMeta[] = "CAST($candidate AS TEXT) = :meta";
            }
        }
        if (!empty($whereByMeta)) {
            $sql2 = "UPDATE {$tableName} SET {$statusCol} = :status{$updatedAtSql}{$paidAtSql} WHERE " . implode(' OR ', $whereByMeta);
            $stmt2 = $pdo->prepare($sql2);
            $stmt2->execute(['status' => $status, 'meta' => $metadataRef]);
            $affected = $stmt2->rowCount();
            if ($affected > 0) {
                return $affected;
            }
        }
    }

    return 0;
}

function paymongo_find_intent_context(PDO $pdo, string $externalId, ?string $metadataRef = null): ?array {
    // purpose/user_id/credits are absent for pre-existing rows created before
    // ensure_ai_credit_columns() ran; PDO returns null for them there, which
    // paymongo_sync_payment_row() below already treats as "not an ai_credits
    // row" via the purpose default.
    $sql = "SELECT appointment_id, amount, method, purpose, user_id, credits
            FROM appointment_payment_intents
            WHERE CAST(intent_token AS TEXT) = :external
               OR CAST(provider_ref AS TEXT) = :external
            ORDER BY created_at DESC
            LIMIT 1";
    $stmt = $pdo->prepare($sql);
    $stmt->execute(['external' => $externalId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (is_array($row)) {
        return $row;
    }

    // Metadata-ref fallback is booking-only: an ai_credits intent is always
    // found by intent_token/provider_ref above (the PayMongo resource id is
    // stored there at creation time regardless of purpose), so there is no
    // equivalent single-id fallback needed for a credit purchase.
    if ($metadataRef !== null && $metadataRef !== '') {
        $metaStmt = $pdo->prepare(
            "SELECT appointment_id, amount, method, purpose, user_id, credits
             FROM appointment_payment_intents
             WHERE CAST(appointment_id AS TEXT) = :meta
             ORDER BY created_at DESC
             LIMIT 1"
        );
        $metaStmt->execute(['meta' => $metadataRef]);
        $metaRow = $metaStmt->fetch(PDO::FETCH_ASSOC);
        if (is_array($metaRow)) {
            return $metaRow;
        }
    }

    return null;
}

function paymongo_is_success_status(string $status): bool
{
    return in_array(strtolower(trim($status)), ['paid', 'succeeded', 'captured'], true);
}

function paymongo_payment_row_status(string $gatewayStatus): string
{
    return paymongo_is_success_status($gatewayStatus) ? 'Captured' : $gatewayStatus;
}

function paymongo_intent_row_status(string $gatewayStatus): string
{
    if (paymongo_is_success_status($gatewayStatus)) {
        return 'Paid';
    }

    $normalized = strtolower(trim($gatewayStatus));
    if (in_array($normalized, ['failed', 'expired', 'canceled', 'cancelled'], true)) {
        return 'Failed';
    }

    return $gatewayStatus;
}

function paymongo_get_pdo(): ?PDO
{
    try {
        require_once dirname(__DIR__) . '/db.php';
        require_once dirname(__DIR__) . '/ai_tryon_provider.php';
        load_repository_env();

        $pdo = get_db_connection();
        // Must run before paymongo_find_intent_context()'s SELECT below, which
        // names purpose/user_id/credits unconditionally.
        schema_ensure_once('ai_credit_columns', static function () use ($pdo): void {
            ensure_ai_credit_columns($pdo);
        });

        return $pdo;
    } catch (Throwable $e) {
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . ' DB connect error: ' . $e->getMessage() . PHP_EOL, FILE_APPEND);

        return null;
    }
}

function paymongo_sync_payment_row(PDO $pdo, string $externalId, string $status, ?string $metadataRef = null): void {
    $intentContext = paymongo_find_intent_context($pdo, $externalId, $metadataRef);

    $isAiCreditPurchase = $intentContext
        && ($intentContext['purpose'] ?? 'booking') === 'ai_credits'
        && (int)($intentContext['user_id'] ?? 0) > 0;

    $appointmentId = null;
    if (!$isAiCreditPurchase) {
        if ($intentContext && isset($intentContext['appointment_id'])) {
            $appointmentId = intval($intentContext['appointment_id']);
        }

        if (($appointmentId === null || $appointmentId <= 0) && $metadataRef !== null && ctype_digit((string) $metadataRef)) {
            $appointmentId = intval($metadataRef);
        }

        if ($appointmentId === null || $appointmentId <= 0) {
            return;
        }
    }

    $paymentStatus = paymongo_payment_row_status($status);
    $existingStmt = $pdo->prepare('SELECT payment_id FROM appointment_payments WHERE transaction_ref = :ref LIMIT 1');
    $existingStmt->execute(['ref' => $externalId]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);

    $amount = isset($intentContext['amount']) ? floatval($intentContext['amount']) : 0;
    $method = isset($intentContext['method']) ? (string) $intentContext['method'] : 'unknown';

    if (is_array($existing)) {
        $updateStmt = $pdo->prepare(
            'UPDATE appointment_payments
             SET status = :status
             WHERE payment_id = :payment_id'
        );
        $updateStmt->execute([
            'status' => $paymentStatus,
            'payment_id' => $existing['payment_id'],
        ]);
        return;
    }

    if ($isAiCreditPurchase) {
        // No appointment side effects (no promote_paid_booking_unit-equivalent
        // needed): ai_tryon_purchased_credits() sums this row directly, so
        // landing it here as Captured is the whole job.
        $credits = (int)($intentContext['credits'] ?? 0);
        $userId = (int)$intentContext['user_id'];

        $insertStmt = $pdo->prepare(
            'INSERT INTO appointment_payments (appointment_id, purpose, user_id, credits, amount, method, status, transaction_ref)
             VALUES (NULL, \'ai_credits\', :user_id, :credits, :amount, :method, :status, :transaction_ref)'
        );
        $insertStmt->execute([
            'user_id' => $userId,
            'credits' => $credits,
            'amount' => $amount,
            'method' => $method,
            'status' => $paymentStatus,
            'transaction_ref' => $externalId,
        ]);

        // Only once the money actually landed, and only on the insert: a
        // repeat call takes the $existing branch above and returns before
        // reaching here, so the webhook and the poll cannot both notify.
        if ($paymentStatus === 'Captured') {
            paymongo_notify_credit_purchase($pdo, $userId, $credits, $amount, $externalId);
        }

        return;
    }

    $insertStmt = $pdo->prepare(
        'INSERT INTO appointment_payments (appointment_id, amount, method, status, transaction_ref)
         VALUES (:appointment_id, :amount, :method, :status, :transaction_ref)'
    );
    $insertStmt->execute([
        'appointment_id' => $appointmentId,
        'amount' => $amount,
        'method' => $method,
        'status' => $paymentStatus,
        'transaction_ref' => $externalId,
    ]);
}

/**
 * Tells the customer their previews arrived, and the owner that a sale happened.
 *
 * A credit purchase left no trace anywhere a person would look: the customer
 * had only a count that silently changed, and the shop had no record of the
 * sale outside the payments table, which the portal does not show. Both sides
 * now get a notification, and the admin one doubles as the receipt record.
 *
 * Notification failures are swallowed on purpose -- the payment is already
 * settled and the credits already granted, so a notification problem must
 * never turn a successful purchase into an error.
 */
function paymongo_notify_credit_purchase(
    PDO $pdo,
    int $userId,
    int $credits,
    float $amount,
    string $reference
): void {
    if ($userId <= 0) {
        return;
    }

    try {
        $customerName = '';
        $nameStmt = $pdo->prepare('SELECT full_name FROM users WHERE user_id = :id LIMIT 1');
        $nameStmt->execute([':id' => $userId]);
        $customerName = trim((string)($nameStmt->fetchColumn() ?: ''));

        $peso = '₱' . number_format($amount, 2);
        $noun = $credits === 1 ? 'preview' : 'previews';

        $insert = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES (:type, :id, 'Payment', :title, :message, TRUE)"
        );

        $insert->execute([
            ':type' => 'User',
            ':id' => $userId,
            ':title' => 'Previews added',
            ':message' => 'Your ' . $peso . ' payment went through. ' . $credits . ' AI '
                . $noun . ' were added to your account. Reference ' . $reference . '.',
        ]);

        // recipient_id 0 is the shop-wide admin inbox, matching the System
        // notifications admin_settings.php already writes.
        $insert->execute([
            ':type' => 'Admin',
            ':id' => 0,
            ':title' => 'Preview credits sold',
            ':message' => ($customerName !== '' ? $customerName : 'A customer')
                . ' bought ' . $credits . ' AI ' . $noun . ' for ' . $peso
                . '. Reference ' . $reference . '.',
        ]);
    } catch (Throwable $e) {
        error_log('Credit purchase notification failed: ' . $e->getMessage());
    }
}

function paymongo_finalize_successful_payment(PDO $pdo, string $externalId, ?string $metadataRef = null): void
{
    $intentStatus = paymongo_intent_row_status('paid');
    $affected = paymongo_update_table_status($pdo, 'appointment_payment_intents', $externalId, $intentStatus, $metadataRef);

    paymongo_sync_payment_row($pdo, $externalId, 'paid', $metadataRef);

    $intentContext = paymongo_find_intent_context($pdo, $externalId, $metadataRef);
    $appointmentId = null;
    if ($intentContext && isset($intentContext['appointment_id'])) {
        $appointmentId = (int) $intentContext['appointment_id'];
    } elseif ($metadataRef !== null && ctype_digit((string) $metadataRef)) {
        $appointmentId = (int) $metadataRef;
    }

    if ($appointmentId !== null && $appointmentId > 0) {
        $promoteStmt = $pdo->prepare(
            "UPDATE appointments
             SET status = 'Scheduled', updated_at = CURRENT_TIMESTAMP
             WHERE appointment_id = :appointment_id
               AND status = 'PendingPayment'"
        );
        $promoteStmt->execute([':appointment_id' => $appointmentId]);
    }

    @file_put_contents(
        __DIR__ . '/paymongo_events.log',
        date('c') . " Finalized payment {$externalId} => Captured/Paid (intent rows: {$affected}, appointment: {$appointmentId})" . PHP_EOL,
        FILE_APPEND
    );
}

function paymongo_update_order_status(string $externalId, string $status, ?string $metadataRef = null): void {
    $pdo = paymongo_get_pdo();
    if (!$pdo instanceof PDO) {
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " DB config missing. {$externalId} => {$status}\n", FILE_APPEND);
        return;
    }

    try {
        if (paymongo_is_success_status($status)) {
            paymongo_finalize_successful_payment($pdo, $externalId, $metadataRef);
            return;
        }

        $intentStatus = paymongo_intent_row_status($status);
        $affected = paymongo_update_table_status($pdo, 'appointment_payment_intents', $externalId, $intentStatus, $metadataRef);
        if ($affected <= 0) {
            paymongo_update_table_status($pdo, 'appointment_payments', $externalId, paymongo_payment_row_status($status), $metadataRef);
        }

        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Updated payment rows for {$externalId} => {$intentStatus}\n", FILE_APPEND);
    } catch (PDOException $e) {
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " DB error: {$e->getMessage()}\n", FILE_APPEND);
    }
}

function paymongo_charge_cache_dir(): string {
    return __DIR__ . '/.source_charge_cache';
}

function paymongo_cached_payment_id(string $sourceId): ?string {
    $file = paymongo_charge_cache_dir() . '/' . preg_replace('/[^a-zA-Z0-9_\-]/', '_', $sourceId) . '.txt';
    if (!is_file($file)) {
        return null;
    }

    $value = trim((string) @file_get_contents($file));
    return $value !== '' ? $value : null;
}

function paymongo_store_payment_id(string $sourceId, string $paymentId): void {
    $dir = paymongo_charge_cache_dir();
    if (!is_dir($dir)) {
        @mkdir($dir, 0777, true);
    }

    $file = $dir . '/' . preg_replace('/[^a-zA-Z0-9_\-]/', '_', $sourceId) . '.txt';
    @file_put_contents($file, $paymentId, LOCK_EX);
}

function paymongo_create_payment_from_source(array $sourceData): ?array {
    $attributes = $sourceData['attributes'] ?? [];
    $sourceId = $sourceData['id'] ?? null;
    $amount = isset($attributes['amount']) ? intval($attributes['amount']) : 0;
    $currency = isset($attributes['currency']) ? strtoupper((string) $attributes['currency']) : 'PHP';

    if (!$sourceId || $amount <= 0) {
        return null;
    }

    $paymentPayload = [
        'data' => [
            'attributes' => [
                'amount' => $amount,
                'currency' => $currency,
                'description' => (string) ($attributes['description'] ?? 'Wallet source charge'),
                'source' => [
                    'id' => $sourceId,
                    'type' => 'source',
                ],
            ],
        ],
    ];

    if (!empty($attributes['metadata']) && is_array($attributes['metadata'])) {
        $paymentPayload['data']['attributes']['metadata'] = $attributes['metadata'];
    }

    $resp = paymongo_request('POST', '/payments', $paymentPayload);
    if (($resp['http_code'] ?? 0) < 200 || ($resp['http_code'] ?? 0) >= 300) {
        return [
            'error' => 'Unable to create payment from source',
            'response' => $resp,
        ];
    }

    $payment = $resp['body']['data'] ?? null;
    $paymentId = is_array($payment) ? ($payment['id'] ?? null) : null;
    if ($paymentId) {
        paymongo_store_payment_id($sourceId, (string) $paymentId);
    }

    return [
        'data' => $payment,
        'raw' => $resp['body'],
    ];
}

function paymongo_extract_metadata_ref(array $data): ?string {
    $attrs = $data['attributes'] ?? [];
    if (!is_array($attrs)) {
        return null;
    }

    $metadata = $attrs['metadata'] ?? null;
    if (!is_array($metadata)) {
        return null;
    }

    if (!empty($metadata['appointment_id'])) {
        return (string) $metadata['appointment_id'];
    }

    if (!empty($metadata['order_id'])) {
        return (string) $metadata['order_id'];
    }

    if (!empty($metadata['external_reference'])) {
        return (string) $metadata['external_reference'];
    }

    return null;
}
