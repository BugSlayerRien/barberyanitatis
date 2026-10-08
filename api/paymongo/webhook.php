<?php
// Webhook receiver for PayMongo events
header('Content-Type: application/json');
require_once __DIR__ . '/http_bootstrap.php';

paymongo_bootstrap(true);

require_once __DIR__ . '/paymongo_client.php';
// Provides get_db_connection() (DB_URL-aware) and audit_log().
require_once __DIR__ . '/../db.php';
// One settlement implementation, shared with payment-status.php. This file used
// to carry its own copy, and the copies had drifted apart in the one way that
// mattered: the local sync_payment_row() bailed out on a NULL appointment_id --
// every AI-credit purchase -- while still flipping the intent to Paid.
require_once __DIR__ . '/paymongo_settlement.php';

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
function update_order_status($externalId, $status, $metadataRef = null) {
    // Was building its own DSN from DB_HOST/DB_NAME/DB_USER. This project
    // configures Postgres with DB_URL (see db.php), so on the deployed API
    // those were empty and every webhook bailed out at "DB config missing" --
    // the webhook could not have been recording anything. get_db_connection()
    // understands both, and brings audit_log() into scope.
    try {
        // paymongo_get_pdo(), not get_db_connection(): the shared settlement
        // SELECT names purpose/user_id/credits unconditionally, and only that
        // helper guarantees ensure_ai_credit_columns() has run first.
        $pdo = paymongo_get_pdo();
        if ($pdo === null) {
            return;
        }

        // Priority update order against project tables.
        $affected = paymongo_update_table_status($pdo, 'appointment_payment_intents', (string)$externalId, (string)$status, $metadataRef);
        if ($affected <= 0) {
            $affected = paymongo_update_table_status($pdo, 'appointment_payments', (string)$externalId, (string)$status, $metadataRef);
        }

        // The shared version understands `purpose`: a booking lands an
        // appointment payment row, an ai_credits purchase lands a credit row
        // that ai_tryon_purchased_credits() can actually see.
        paymongo_sync_payment_row($pdo, (string)$externalId, (string)$status, $metadataRef);

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

/**
 * Charge a source the moment PayMongo says it is chargeable.
 *
 * Two things here are not optional, and both were missing:
 *
 *  - `metadata` must be forwarded. It carries purpose/user_id/credits, and
 *    without it the resulting payment object cannot be recognised as a credit
 *    purchase by anything downstream.
 *  - the resulting payment id must be cached. A source can only be charged
 *    once, so when the app's poll reached payment-status.php afterwards it
 *    tried a second charge, PayMongo refused, and the poll never saw "paid" --
 *    the webhook was silently breaking the only path that grants credits.
 *
 * paymongo_create_payment_from_source() in paymongo_settlement.php already does
 * both, so this now delegates rather than reimplementing.
 */
function try_create_payment_from_source($payload) {
    $sourceData = $payload['data'] ?? null;
    if (!is_array($sourceData)) {
        return null;
    }

    $resp = paymongo_create_payment_from_source($sourceData);
    $sourceId = $sourceData['id'] ?? '';
    $code = is_array($resp) ? ($resp['http_code'] ?? ($resp['response']['http_code'] ?? 0)) : 0;
    @file_put_contents(
        __DIR__ . '/paymongo_events.log',
        date('c') . " source.chargeable create payment http={$code} source={$sourceId}\n",
        FILE_APPEND
    );

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
        // paymongo_create_payment_from_source() returns the decoded body on
        // success and ['error' => ...] on failure, so test for the payload
        // rather than an http_code it does not surface.
        $charged = is_array($resp) && isset($resp['data']);
        update_order_status($objectId, $charged ? 'Processing' : 'Chargeable', $metadataRef);
    }
} else if ($eventType === 'payment.paid') {
    if ($objectId) update_order_status($objectId, 'Paid', $metadataRef);
} else if ($eventType === 'payment.failed') {
    if ($objectId) update_order_status($objectId, 'Failed', $metadataRef);
}

http_response_code(200);
echo json_encode(['received' => true]);
