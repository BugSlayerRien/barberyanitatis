<?php
// Simple PayMongo helper using Basic auth with secret key from env
function paymongo_request($method, $path, $payload = null) {
    $secret = getenv('PAYMONGO_SECRET');
    if (!$secret) {
        http_response_code(500);
        echo json_encode(['error' => 'Missing PAYMONGO_SECRET environment variable']);
        exit;
    }

    $base = getenv('PAYMONGO_API_URL') ?: 'https://api.paymongo.com/v1';
    $url = rtrim($base, '/') . '/' . ltrim($path, '/');

    $ch = curl_init($url);
    $headers = [
        'Accept: application/json',
        'Content-Type: application/json',
        'Authorization: Basic ' . base64_encode($secret . ':'),
    ];

    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, strtoupper($method));
    if ($payload !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    }

    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($resp === false) {
        return ['error' => $err, 'http_code' => 0];
    }

    $decoded = json_decode($resp, true);
    return ['body' => $decoded, 'http_code' => $code, 'raw' => $resp];
}
