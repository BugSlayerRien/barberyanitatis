<?php
header('Content-Type: application/json');
require_once __DIR__ . '/backend/paymongo/paymongo_client.php';

$raw = file_get_contents('php://input');
$data = json_decode($raw, true) ?: $_POST ?: [];
$action = $data['action'] ?? ($_GET['action'] ?? null);

if (!$action) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing action']);
    exit;
}

if ($action === 'createIntent') {
    // Expect amount in decimal or cents
    $amount = $data['amount'] ?? 0;
    // If amount looks like decimal (e.g., 123.45), convert to cents
    if (is_string($amount) && strpos($amount, '.') !== false) {
        $cents = intval(round(floatval($amount) * 100));
    } else if (is_float($amount)) {
        $cents = intval(round($amount * 100));
    } else {
        $cents = intval($amount);
    }

    $payload = [
        'data' => [
            'attributes' => [
                'amount' => $cents,
                'currency' => strtoupper($data['currency'] ?? 'PHP'),
                'payment_method_allowed' => [$data['method'] ?? 'card'],
                'description' => $data['description'] ?? null,
            ],
        ],
    ];

    $resp = paymongo_request('POST', '/payment_intents', $payload);
    http_response_code($resp['http_code'] ?: 500);
    echo json_encode($resp['body']);
    exit;
}

if ($action === 'getIntentStatus') {
    $intentID = $data['intentID'] ?? $data['intentId'] ?? null;
    if (!$intentID) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing intentID']);
        exit;
    }

    $resp = paymongo_request('GET', '/payment_intents/' . urlencode($intentID));
    http_response_code($resp['http_code'] ?: 500);
    echo json_encode($resp['body']);
    exit;
}

if ($action === 'mockProviderWebhook') {
    // For local testing: simulate a webhook by invoking webhook.php handler
    $intentID = $data['intentID'] ?? null;
    $outcome = $data['outcome'] ?? 'paid';
    if (!$intentID) {
        http_response_code(400);
        echo json_encode(['error' => 'Missing intentID']);
        exit;
    }

    // Create a minimal payload to pass to webhook handler
    $event = [
        'type' => $outcome === 'paid' ? 'payment_intent.paid' : 'payment_intent.failed',
        'data' => [
            'id' => $intentID,
            'attributes' => [
                'status' => $outcome === 'paid' ? 'paid' : 'failed',
                'payment_intent' => $intentID,
            ],
        ],
    ];

    // Call webhook handler directly
    $webhookPath = __DIR__ . '/backend/paymongo/webhook.php';
    if (file_exists($webhookPath)) {
        // Emulate posting JSON by writing to php://input is not trivial here; instead, call update_order_status directly if available
        require_once __DIR__ . '/backend/paymongo/webhook.php';
        echo json_encode(['ok' => true]);
        exit;
    }

    echo json_encode(['error' => 'Webhook handler missing']);
    exit;
}

http_response_code(400);
echo json_encode(['error' => 'Unknown action']);
