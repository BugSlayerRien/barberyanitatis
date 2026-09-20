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

/**
 * Same intent row as store_payment_intent_record(), but for an AI-generation
 * credit top-up rather than a booking: appointment_id is NULL, purpose is
 * 'ai_credits', and user_id/credits identify what to grant once PayMongo
 * confirms payment (see ai_tryon_provider.php's ensure_ai_credit_columns()
 * and ai_tryon_purchased_credits()).
 *
 * A separate function rather than widening store_payment_intent_record()'s
 * signature, so the booking path above is untouched.
 */
function store_ai_credit_intent_record(int $userId, int $credits, string $resourceId, string $method, int $amount): ?string {
    try {
        require_once dirname(__DIR__) . '/db.php';
        require_once dirname(__DIR__) . '/ai_tryon_provider.php';
        load_repository_env();

        with_pdo_retry(function (PDO $pdo) use ($userId, $credits, $resourceId, $method, $amount): void {
            schema_ensure_once('ai_credit_columns', static function () use ($pdo): void {
                ensure_ai_credit_columns($pdo);
            });
            $expiresAt = new DateTimeImmutable('+ 24 hours');
            $stmt = $pdo->prepare(
                "INSERT INTO appointment_payment_intents
                 (appointment_id, purpose, user_id, credits, amount, method, provider, status, intent_token, provider_ref, expires_at)
                 VALUES (NULL, 'ai_credits', :user_id, :credits, :amount, :method, 'paymongo', 'PendingGateway', :token, :ref, :expires_at)
                 ON CONFLICT DO NOTHING"
            );
            $stmt->execute([
                ':user_id' => $userId,
                ':credits' => $credits,
                ':amount' => $amount / 100,
                ':method' => $method,
                ':token' => $resourceId,
                ':ref' => $resourceId,
                ':expires_at' => $expiresAt->format('c'),
            ]);
        });

        return null; // success
    } catch (Exception $e) {
        $msg = "DB error: {$e->getMessage()}";
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Failed to store ai_credits intent: {$msg}\n", FILE_APPEND);
        return $msg;
    }
}

/**
 * PayMongo's error detail for a non-2xx response, or null when the call
 * succeeded. Without this the endpoint passed the gateway's status straight
 * through with no `error` key in the body, so the app fell back to a bare
 * "Request failed (HTTP 400)" with nothing to act on.
 */
function paymongo_error_detail(array $resp): ?string {
    $code = (int)($resp['http_code'] ?? 0);
    if ($code >= 200 && $code < 300) {
        return null;
    }
    $errors = $resp['body']['errors'] ?? null;
    if (is_array($errors) && $errors !== []) {
        $details = [];
        foreach ($errors as $error) {
            $detail = trim((string)($error['detail'] ?? ''));
            if ($detail !== '') {
                $details[] = $detail;
            }
        }
        if ($details !== []) {
            return implode(' ', $details);
        }
    }

    return "Payment gateway rejected the request (HTTP {$code}).";
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

// AI-generation credit top-up: an alternative to appointment_id. Everything
// else about the PayMongo call (source/payment-intent creation, redirect,
// status polling) is identical to a booking payment — only what gets stored
// afterwards differs.
$purpose = isset($input['purpose']) ? strtolower(trim((string)$input['purpose'])) : 'booking';
$creditUserId = isset($input['user_id']) ? intval($input['user_id']) : 0;
$credits = isset($input['credits']) ? intval($input['credits']) : 0;
$isAiCreditPurchase = $purpose === 'ai_credits';

if ($isAiCreditPurchase && ($creditUserId <= 0 || $credits <= 0)) {
    http_response_code(400);
    echo json_encode(['error' => 'ai_credits purchases require a positive user_id and credits']);
    exit;
}

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
if ($isAiCreditPurchase) {
    $metadata['purpose'] = 'ai_credits';
    $metadata['user_id'] = $creditUserId;
    $metadata['credits'] = $credits;
} elseif ($appointmentId > 0) {
    $metadata['appointment_id'] = $appointmentId;
}

// PayMongo rejects the whole request with a 400 if any metadata value is not a
// string, so coerce here -- once, for every branch -- rather than relying on
// each field remembering its own cast at assignment.
$metadata = array_map(static fn($value): string => (string)$value, $metadata);

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

    // Flat metadata only (PayMongo doesn't accept nested metadata objects).
    if (!empty($metadata)) {
        $sourcePayload['data']['attributes']['metadata'] = $metadata;
    }
    if ($description !== null) {
        $sourcePayload['data']['attributes']['description'] = $description;
    }

    $resp = paymongo_request('POST', '/sources', $sourcePayload);
    $body = $resp['body'];
    $checkoutUrl = $body['data']['attributes']['redirect']['checkout_url'] ?? null;
    $sourceId = $body['data']['id'] ?? null;

    // Store initial payment intent record for tracking
    if ($sourceId && ($resp['http_code'] ?? 0) >= 200 && ($resp['http_code'] ?? 0) < 300) {
        $dbError = $isAiCreditPurchase
            ? store_ai_credit_intent_record($creditUserId, $credits, $sourceId, $method, $amount)
            : ($appointmentId > 0 ? store_payment_intent_record($appointmentId, $sourceId, $method, $amount, 'source') : null);
        if ($dbError) {
            // Log but don't fail the entire payment - user can still proceed
            @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Warning: {$dbError} for source {$sourceId}\n", FILE_APPEND);
        }
    }

    $gatewayError = paymongo_error_detail($resp);

    http_response_code($resp['http_code'] ?: 500);
    echo json_encode([
        'provider' => 'paymongo',
        'flow' => 'redirect_source',
        'resource_type' => 'source',
        'resource_id' => $sourceId,
        'checkout_url' => $checkoutUrl,
        'data' => $body['data'] ?? null,
        'raw' => $body,
        ...($gatewayError !== null ? ['error' => $gatewayError] : []),
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

// Flat metadata only
if (!empty($metadata)) {
    $payload['data']['attributes']['metadata'] = $metadata;
}

$resp = paymongo_request('POST', '/payment_intents', $payload);
$body = $resp['body'];
$intentId = $body['data']['id'] ?? null;

// Store initial payment intent record for tracking
if ($intentId && ($resp['http_code'] ?? 0) >= 200 && ($resp['http_code'] ?? 0) < 300) {
    $dbError = $isAiCreditPurchase
        ? store_ai_credit_intent_record($creditUserId, $credits, $intentId, $method, $amount)
        : ($appointmentId > 0 ? store_payment_intent_record($appointmentId, $intentId, $method, $amount, 'payment_intent') : null);
    if ($dbError) {
        // Log but don't fail the entire payment - user can still proceed
        @file_put_contents(__DIR__ . '/paymongo_events.log', date('c') . " Warning: {$dbError} for intent {$intentId}\n", FILE_APPEND);
    }
}

$gatewayError = paymongo_error_detail($resp);

http_response_code($resp['http_code'] ?: 500);
echo json_encode([
    'provider' => 'paymongo',
    'flow' => 'payment_intent',
    'resource_type' => 'payment_intent',
    'resource_id' => $intentId,
    'data' => $body['data'] ?? null,
    'raw' => $body,
    ...($gatewayError !== null ? ['error' => $gatewayError] : []),
]);
