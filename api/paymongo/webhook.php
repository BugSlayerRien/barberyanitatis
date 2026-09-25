<?php
// Webhook receiver for PayMongo events
header('Content-Type: application/json');
require_once __DIR__ . '/http_bootstrap.php';

paymongo_bootstrap(true);

require_once __DIR__ . '/paymongo_client.php';
// Provides get_db_connection() (DB_URL-aware) and audit_log().
require_once __DIR__ . '/../db.php';

$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);

// Read signature header (common names)
$sigHeader = null;
$possible = ['HTTP_PAYMONGO_SIGNATURE', 'HTTP_PAYMONGO_SIGNATURES', 'HTTP_PAYMONGO_SIGNATURE-1', 'HTTP_SIGNATURE', 'HTTP_X_PAYMONGO_SIGNATURE'];
foreach ($possible as $h) {
    if (isset($_SERVER[$h])) {
        $sigHeader = $_SERVER[$h];
        break;
    }
}

$webhookSecret = getenv('PAYMONGO_WEBHOOK_SECRET');
if ($webhookSecret) {
    if (!$sigHeader) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing signature header']);
        exit;
    }

    // Support two common formats:
    // 1) simple raw-signature header (legacy)
    // 2) structured header like `t=TIMESTAMP,v1=SIGNATURE` (parse and verify)
    $verified = false;

    // structured header: look for v1= and t=
    if (is_string($sigHeader) && strpos($sigHeader, 'v1=') !== false) {
        // parse pairs
        $parts = explode(',', $sigHeader);
        $sigMap = [];
        foreach ($parts as $p) {
            [$k, $v] = array_map('trim', explode('=', $p, 2) + [1 => '']);
            $sigMap[$k] = $v;
        }
        if (!empty($sigMap['t']) && !empty($sigMap['v1'])) {
            $signedPayload = $sigMap['t'] . '.' . $raw;
            $expected = hash_hmac('sha256', $signedPayload, $webhookSecret);
            if (hash_equals($expected, $sigMap['v1'])) {
                $verified = true;
            }
        }
    }

    // fallback: raw signature header (HMAC of body)
    if (!$verified && is_string($sigHeader)) {
        $expected = hash_hmac('sha256', $raw, $webhookSecret);
        if (hash_equals($expected, $sigHeader)) {
            $verified = true;
        }
    }

    if (!$verified) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid signature']);
        exit;
    }
}

// Log webhook for debugging (rotate/remove in production)
@file_put_contents(__DIR__ . '/paymongo_webhooks.log', date('c') . " " . json_encode($payload) . PHP_EOL, FILE_APPEND);

// Determine event type and act
$eventType = $payload['type'] ?? ($payload['data']['type'] ?? null);

// Example: extract payment intent id or source id
// Try to extract relevant identifiers from the webhook payload
$objectId = null; // e.g. payment intent id or source id
$metadataRef = null; // e.g. order id stored in metadata
if (isset($payload['data']['id'])) {
    $objectId = $payload['data']['id'];
}

// attributes can hold nested references
if (empty($objectId) && isset($payload['data']['attributes'])) {
    $attrs = $payload['data']['attributes'];
    if (is_array($attrs) && isset($attrs['payment_intent'])) {
        // payment_intent may be id string or object
        if (is_array($attrs['payment_intent']) && isset($attrs['payment_intent']['id'])) {
            $objectId = $attrs['payment_intent']['id'];
        } else if (is_string($attrs['payment_intent'])) {
            $objectId = $attrs['payment_intent'];
        }
    }

    if (empty($objectId) && is_array($attrs) && isset($attrs['source'])) {
        if (is_array($attrs['source']) && isset($attrs['source']['id'])) {
            $objectId = $attrs['source']['id'];
        } else if (is_string($attrs['source'])) {
            $objectId = $attrs['source'];
        }
    }

    // metadata often contains an order reference
    if (is_array($attrs) && isset($attrs['metadata']) && is_array($attrs['metadata'])) {
        $meta = $attrs['metadata'];
        if (!empty($meta['order_id'])) $metadataRef = $meta['order_id'];
        else if (!empty($meta['external_reference'])) $metadataRef = $meta['external_reference'];
    }
}

// Placeholder: update order status in your DB. Implement this with your schema.
function try_update_table_status(PDO $pdo, $tableName, $externalId, $status, $metadataRef = null) {
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

function find_intent_context(PDO $pdo, $externalId, $metadataRef = null) {
    $sql = "SELECT appointment_id, amount, method
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

    if ($metadataRef !== null && $metadataRef !== '') {
        $metaStmt = $pdo->prepare(
            "SELECT appointment_id, amount, method
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

function sync_payment_row(PDO $pdo, $externalId, $status, $metadataRef = null) {
    $intentContext = find_intent_context($pdo, $externalId, $metadataRef);
    $appointmentId = null;

    if ($intentContext && isset($intentContext['appointment_id'])) {
        $appointmentId = intval($intentContext['appointment_id']);
    }

    if (($appointmentId === null || $appointmentId <= 0) && $metadataRef !== null && ctype_digit((string) $metadataRef)) {
        $appointmentId = intval($metadataRef);
    }

    if ($appointmentId === null || $appointmentId <= 0) {
        return;
    }

    $existingStmt = $pdo->prepare('SELECT payment_id FROM appointment_payments WHERE transaction_ref = :ref LIMIT 1');
    $existingStmt->execute(['ref' => $externalId]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);

    $amount = isset($intentContext['amount']) ? floatval($intentContext['amount']) : 0;
    $method = isset($intentContext['method']) ? strval($intentContext['method']) : 'unknown';

    if (is_array($existing)) {
        $updateStmt = $pdo->prepare(
            'UPDATE appointment_payments
             SET status = :status
             WHERE payment_id = :payment_id'
        );
        $updateStmt->execute([
            'status' => $status,
            'payment_id' => $existing['payment_id'],
        ]);
        audit_log($pdo, 'WEBHOOK_PAYMENT_UPDATED', 'appointment_payments', (string)$existing['payment_id'], null, [
            'appointment_id' => $appointmentId,
            'status' => $status,
            'transaction_ref' => $externalId,
        ], null, audit_actor_webhook());
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
        'status' => $status,
        'transaction_ref' => $externalId,
    ]);

    // Gateway-initiated money movement, with no human and no app involved.
    audit_log($pdo, 'WEBHOOK_PAYMENT_RECORDED', 'appointment_payments', $externalId, null, [
        'appointment_id' => $appointmentId,
        'amount' => round((float)$amount, 2),
        'method' => $method,
        'status' => $status,
        'transaction_ref' => $externalId,
    ], null, audit_actor_webhook());
}

function update_order_status($externalId, $status, $metadataRef = null) {
    // Was building its own DSN from DB_HOST/DB_NAME/DB_USER. This project
    // configures Postgres with DB_URL (see db.php), so on the deployed API
    // those were empty and every webhook bailed out at "DB config missing" --
    // the webhook could not have been recording anything. get_db_connection()
    // understands both, and brings audit_log() into scope.
    try {
        $pdo = get_db_connection();

        // Priority update order against project tables.
        $affected = try_update_table_status($pdo, 'appointment_payment_intents', $externalId, $status, $metadataRef);
        if ($affected <= 0) {
            $affected = try_update_table_status($pdo, 'appointment_payments', $externalId, $status, $metadataRef);
        }

        sync_payment_row($pdo, $externalId, $status, $metadataRef);

        if ($affected > 0) {
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Updated payment rows for $externalId => $status (rows: $affected)\n", FILE_APPEND);
            return;
        }

        // Fallback: insert into payment_events for reconciliation, but only if table exists.
        $eventColsStmt = $pdo->prepare("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'payment_events'");
        $eventColsStmt->execute();
        $eventCols = $eventColsStmt->fetchAll(PDO::FETCH_COLUMN);
        $eventCols = is_array($eventCols) ? $eventCols : [];

        if (empty($eventCols)) {
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " payment_events table not found. External: $externalId, status: $status\n", FILE_APPEND);
            return;
        }

        $eventColSet = array_fill_keys($eventCols, true);
        $insertCols = [];
        $insertVals = [];
        $params = [];

        $mapping = [
            'external_id' => $externalId,
            'event_type' => $status,
            'metadata_ref' => $metadataRef,
            'paymongo_id' => $externalId,
            'status' => $status,
        ];

        foreach ($mapping as $col => $value) {
            if (isset($eventColSet[$col])) {
                $insertCols[] = $col;
                $insertVals[] = ':' . $col;
                $params[$col] = $value;
            }
        }

        if (isset($eventColSet['created_at'])) {
            $insertCols[] = 'created_at';
            $insertVals[] = 'NOW()';
        }

        if (!empty($insertCols)) {
            $insSql = 'INSERT INTO payment_events (' . implode(', ', $insertCols) . ') VALUES (' . implode(', ', $insertVals) . ')';
            $ins = $pdo->prepare($insSql);
            $ins->execute($params);
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Logged event for $externalId => $status\n", FILE_APPEND);
        }

    } catch (PDOException $e) {
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " DB error: {$e->getMessage()}\n", FILE_APPEND);
    }
}

function try_create_payment_from_source($payload) {
    $attrs = $payload['data']['attributes'] ?? [];
    $sourceId = $payload['data']['id'] ?? null;
    $amount = isset($attrs['amount']) ? intval($attrs['amount']) : 0;
    $currency = isset($attrs['currency']) ? strtoupper($attrs['currency']) : 'PHP';
    $description = isset($attrs['description']) ? strval($attrs['description']) : 'Wallet source charge';

    if (!$sourceId || $amount <= 0) {
        return null;
    }

    $paymentPayload = [
        'data' => [
            'attributes' => [
                'amount' => $amount,
                'currency' => $currency,
                'description' => $description,
                'source' => [
                    'id' => $sourceId,
                    'type' => 'source',
                ],
            ],
        ],
    ];

    $resp = paymongo_request('POST', '/payments', $paymentPayload);
    @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " source.chargeable create payment http={$resp['http_code']} source={$sourceId}\n", FILE_APPEND);
    return $resp;
}

if ($eventType === 'payment_intent.paid' || ($payload['data']['attributes']['status'] ?? '') === 'paid') {
    if ($objectId) update_order_status($objectId, 'Paid', $metadataRef);
} else if ($eventType === 'payment_intent.failed' || ($payload['data']['attributes']['status'] ?? '') === 'failed') {
    if ($objectId) update_order_status($objectId, 'Failed', $metadataRef);
} else if ($eventType === 'source.chargeable') {
    // Attempt charge now that source is chargeable.
    $resp = try_create_payment_from_source($payload);
    if ($objectId) {
        $nextStatus = ($resp && ($resp['http_code'] >= 200 && $resp['http_code'] < 300)) ? 'Processing' : 'Chargeable';
        update_order_status($objectId, $nextStatus, $metadataRef);
    }
} else if ($eventType === 'payment.paid') {
    if ($objectId) update_order_status($objectId, 'Paid', $metadataRef);
} else if ($eventType === 'payment.failed') {
    if ($objectId) update_order_status($objectId, 'Failed', $metadataRef);
}

http_response_code(200);
echo json_encode(['received' => true]);
