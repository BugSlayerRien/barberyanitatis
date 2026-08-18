<?php
header('Content-Type: application/json');
require_once __DIR__ . '/http_bootstrap.php';

paymongo_bootstrap();

require_once __DIR__ . '/paymongo_client.php';

function store_payment_intent_record(int $appointmentId, string $resourceId, string $method, int $amount, string $resourceType = 'source'): ?string {
    try {
        require_once dirname(__DIR__) . '/db.php';
        load_repository_env();

        with_pdo_retry(function (PDO $pdo) use ($appointmentId, $resourceId, $method, $amount): void {
        $expiresAt = new DateTimeImmutable('+ 24 hours');
        $stmt = $pdo->prepare(
            "INSERT INTO appointment_payment_intents 
             (appointment_id, amount, method, provider, status, intent_token, provider_ref, expires_at)
             VALUES (:appointment_id, :amount, :method, 'paymongo', 'PendingGateway', :token, :ref, :expires_at)
             ON CONFLICT DO NOTHING"
        );
        $stmt->execute([
            ':appointment_id' => $appointmentId,
            ':amount' => $amount / 100, // convert cents to currency units
            ':method' => $method,
            ':token' => $resourceId,
            ':ref' => $resourceId,
            ':expires_at' => $expiresAt->format('c'),
        ]);
        });

        return null; // success
    } catch (Exception $e) {
        $msg = "DB error: {$e->getMessage()}";
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Failed to store payment intent: {$msg}\n", FILE_APPEND);
        return $msg;
    }
}

$rawInput = file_get_contents('php://input');
$input = json_decode($rawInput, true) ?: [];

$amount = isset($input['amount']) ? intval($input['amount']) : 0; // amount in cents/lowest currency unit
$currency = isset($input['currency']) ? strtoupper($input['currency']) : 'PHP';
$method = isset($input['method']) ? strtolower($input['method']) : 'card';
$description = isset($input['description']) ? $input['description'] : null;
$appointmentId = isset($input['appointment_id']) ? intval($input['appointment_id']) : 0;
$successUrl = isset($input['success_url']) ? strval($input['success_url']) : (getenv('PAYMONGO_SUCCESS_URL') ?: null);
$failedUrl = isset($input['failed_url']) ? strval($input['failed_url']) : (getenv('PAYMONGO_FAILED_URL') ?: null);

if ($amount <= 0) {
    http_response_code(400);
    echo json_encode([
        'error' => 'Invalid amount',
        'debug' => [
            'received_amount' => $input['amount'] ?? 'NOT_SET',
            'parsed_amount' => $amount,
            'raw_input_length' => strlen($rawInput),
        ]
    ]);
    exit;
}

// Normalize requested method
if ($method === 'grabpay') {
    $method = 'grab_pay';
}

$metadata = [];
if ($appointmentId > 0) {
    $metadata['appointment_id'] = $appointmentId;
}

// Wallet methods use hosted redirect source flow.
if ($method === 'gcash' || $method === 'grab_pay') {
    if (!$successUrl || !$failedUrl) {
        http_response_code(400);
        echo json_encode([
            'error' => 'Missing redirect URLs for wallet payment.',
            'required' => ['success_url', 'failed_url'],
        ]);
        exit;
    }

    $sourcePayload = [
        'data' => [
            'attributes' => [
                'amount' => $amount,
                'currency' => $currency,
                'type' => $method,
                'redirect' => [
                    'success' => $successUrl,
                    'failed' => $failedUrl,
                ],
            ],
        ],
    ];

    // Add flat metadata if appointment_id exists (PayMongo doesn't accept nested metadata objects)
    if ($appointmentId > 0) {
        $sourcePayload['data']['attributes']['metadata'] = [
            'appointment_id' => (string)$appointmentId,
        ];
    }
    if ($description !== null) {
        $sourcePayload['data']['attributes']['description'] = $description;
    }

    $resp = paymongo_request('POST', '/sources', $sourcePayload);
    $body = $resp['body'];
    $checkoutUrl = $body['data']['attributes']['redirect']['checkout_url'] ?? null;
    $sourceId = $body['data']['id'] ?? null;

    // Store initial payment intent record for tracking
    if ($sourceId && $appointmentId > 0 && ($resp['http_code'] ?? 0) >= 200 && ($resp['http_code'] ?? 0) < 300) {
        $dbError = store_payment_intent_record($appointmentId, $sourceId, $method, $amount, 'source');
        if ($dbError) {
            // Log but don't fail the entire payment - user can still proceed
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Warning: {$dbError} for source {$sourceId}\n", FILE_APPEND);
        }
    }

    http_response_code($resp['http_code'] ?: 500);
    echo json_encode([
        'provider' => 'paymongo',
        'flow' => 'redirect_source',
        'resource_type' => 'source',
        'resource_id' => $sourceId,
        'checkout_url' => $checkoutUrl,
        'data' => $body['data'] ?? null,
        'raw' => $body,
    ]);
    exit;
}

// Default to payment intent flow (cards and compatible methods)
$allowed = ['card'];
if ($method !== 'card') {
    $allowed = [$method];
}

$payload = [
    'data' => [
        'attributes' => [
            'amount' => $amount,
            'currency' => $currency,
            'payment_method_allowed' => $allowed,
        ],
    ],
];

if ($description !== null) {
    $payload['data']['attributes']['description'] = $description;
}

// Add flat metadata if appointment_id exists
if ($appointmentId > 0) {
    $payload['data']['attributes']['metadata'] = [
        'appointment_id' => (string)$appointmentId,
    ];
}

$resp = paymongo_request('POST', '/payment_intents', $payload);
$body = $resp['body'];
$intentId = $body['data']['id'] ?? null;

// Store initial payment intent record for tracking
if ($intentId && $appointmentId > 0 && ($resp['http_code'] ?? 0) >= 200 && ($resp['http_code'] ?? 0) < 300) {
    $dbError = store_payment_intent_record($appointmentId, $intentId, $method, $amount, 'payment_intent');
    if ($dbError) {
        // Log but don't fail the entire payment - user can still proceed
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Warning: {$dbError} for intent {$intentId}\n", FILE_APPEND);
    }
}

http_response_code($resp['http_code'] ?: 500);
echo json_encode([
    'provider' => 'paymongo',
    'flow' => 'payment_intent',
    'resource_type' => 'payment_intent',
    'resource_id' => $intentId,
    'data' => $body['data'] ?? null,
    'raw' => $body,
]);
