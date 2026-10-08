<?php
header('Content-Type: application/json');
require_once __DIR__ . '/http_bootstrap.php';

paymongo_bootstrap();

require_once __DIR__ . '/paymongo_client.php';
require_once __DIR__ . '/paymongo_settlement.php';

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
