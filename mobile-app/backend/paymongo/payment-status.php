<?php
header('Content-Type: application/json');
require_once __DIR__ . '/http_bootstrap.php';

paymongo_bootstrap();

require_once __DIR__ . '/paymongo_client.php';

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

    $whereByExternal = [];
    foreach (['intent_id', 'paymongo_intent_id', 'external_reference', 'order_reference', 'source_id', 'paymongo_source_id', 'provider_ref', 'intent_token'] as $candidate) {
        if (isset($colSet[$candidate])) {
            $whereByExternal[] = "CAST($candidate AS TEXT) = :external";
        }
    }

    if (!empty($whereByExternal)) {
        $sql = "UPDATE {$tableName} SET {$statusCol} = :status{$updatedAtSql} WHERE " . implode(' OR ', $whereByExternal);
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
            $sql2 = "UPDATE {$tableName} SET {$statusCol} = :status{$updatedAtSql} WHERE " . implode(' OR ', $whereByMeta);
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

function paymongo_update_order_status(string $externalId, string $status, ?string $metadataRef = null): void {
    $dbHost = getenv('DB_HOST') ?: '127.0.0.1';
    $dbPort = getenv('DB_PORT') ?: '5432';
    $dbName = getenv('DB_NAME') ?: '';
    $dbUser = getenv('DB_USER') ?: '';
    $dbPass = getenv('DB_PASS') ?: '';
    $sslMode = getenv('DB_SSLMODE');

    if (!$dbName || !$dbUser) {
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " DB config missing. {$externalId} => {$status}\n", FILE_APPEND);
        return;
    }

    $dsn = "pgsql:host={$dbHost};port={$dbPort};dbname={$dbName}";
    if ($sslMode) {
        $dsn .= ";sslmode={$sslMode}";
    }

    try {
        $pdo = new PDO($dsn, $dbUser, $dbPass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

        $affected = paymongo_update_table_status($pdo, 'appointment_payment_intents', $externalId, $status, $metadataRef);
        if ($affected <= 0) {
            $affected = paymongo_update_table_status($pdo, 'orders', $externalId, $status, $metadataRef);
        }

        if ($affected > 0) {
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Updated order(s) for {$externalId} => {$status} (rows: {$affected})\n", FILE_APPEND);
        }
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

$intentId = $_GET['intent_id'] ?? ($_GET['id'] ?? null);
if (!$intentId) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing intent_id']);
    exit;
}

$resourceType = strtolower($_GET['resource_type'] ?? '');
if ($resourceType === '') {
    $resourceType = strpos($intentId, 'src_') === 0 ? 'source' : 'payment_intent';
}

if ($resourceType === 'source') {
    $resp = paymongo_request('GET', '/sources/' . urlencode($intentId));
    $body = $resp['body'];

    $sourceData = $body['data'] ?? null;
    $sourceStatus = is_array($sourceData) ? (($sourceData['attributes']['status'] ?? '') . '') : '';
    $metadataRef = is_array($sourceData) ? paymongo_extract_metadata_ref($sourceData) : null;

    if (is_array($sourceData) && in_array(strtolower($sourceStatus), ['failed', 'expired', 'canceled'], true)) {
        paymongo_update_order_status((string) $intentId, 'Failed', $metadataRef);
    }

    if (is_array($sourceData) && strtolower($sourceStatus) === 'chargeable') {
        $cachedPaymentId = paymongo_cached_payment_id((string) $intentId);
        if ($cachedPaymentId) {
            $paymentResp = paymongo_request('GET', '/payments/' . urlencode($cachedPaymentId));
            $paymentBody = $paymentResp['body'];
            $paymentData = $paymentBody['data'] ?? null;
            $paymentStatus = is_array($paymentData) ? (($paymentData['attributes']['status'] ?? '') . '') : '';
            if (is_array($paymentData) && in_array(strtolower($paymentStatus), ['paid', 'succeeded'], true)) {
                paymongo_update_order_status((string) $intentId, 'Paid', $metadataRef);
            }
            http_response_code($paymentResp['http_code'] ?: 500);
            echo json_encode([
                'resource_type' => 'payment',
                'data' => $paymentBody['data'] ?? null,
                'raw' => $paymentBody,
                'source' => $sourceData,
            ]);
            exit;
        }

        $chargeResult = paymongo_create_payment_from_source($sourceData);
        if (is_array($chargeResult) && isset($chargeResult['data'])) {
            $paymentStatus = (($chargeResult['data']['attributes']['status'] ?? '') . '');
            if (in_array(strtolower($paymentStatus), ['paid', 'succeeded'], true)) {
                paymongo_update_order_status((string) $intentId, 'Paid', $metadataRef);
            } else {
                paymongo_update_order_status((string) $intentId, 'Processing', $metadataRef);
            }
            http_response_code(200);
            echo json_encode([
                'resource_type' => 'payment',
                'data' => $chargeResult['data'],
                'raw' => $chargeResult['raw'],
                'source' => $sourceData,
            ]);
            exit;
        }
    }

    http_response_code($resp['http_code'] ?: 500);
    echo json_encode([
        'resource_type' => 'source',
        'data' => $body['data'] ?? null,
        'raw' => $body,
    ]);
    exit;
}

$resp = paymongo_request('GET', '/payment_intents/' . urlencode($intentId));
$body = $resp['body'];
$paymentData = $body['data'] ?? null;
$paymentStatus = is_array($paymentData) ? (($paymentData['attributes']['status'] ?? '') . '') : '';

if (is_array($paymentData)) {
    $metadataRef = paymongo_extract_metadata_ref($paymentData);
    if (in_array(strtolower($paymentStatus), ['paid', 'succeeded'], true)) {
        paymongo_update_order_status((string) $intentId, 'Paid', $metadataRef);
    } elseif (in_array(strtolower($paymentStatus), ['failed', 'expired', 'canceled'], true)) {
        paymongo_update_order_status((string) $intentId, 'Failed', $metadataRef);
    }
}

http_response_code($resp['http_code'] ?: 500);
echo json_encode([
    'resource_type' => 'payment_intent',
    'data' => $body['data'] ?? null,
    'raw' => $body,
]);
