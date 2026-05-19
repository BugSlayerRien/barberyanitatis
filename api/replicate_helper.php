<?php
declare(strict_types=1);

/**
 * Minimal Replicate API helper for try-on image generation.
 * Set REPLICATE_API_TOKEN in .env (server-side only).
 */

function replicate_api_token(): string
{
    return trim((string)(getenv('REPLICATE_API_TOKEN') ?: ($_ENV['REPLICATE_API_TOKEN'] ?? '')));
}

function replicate_is_configured(): bool
{
    return replicate_api_token() !== '';
}

/**
 * @param array<string, mixed> $input
 * @return array{ok: bool, output: mixed, error: string, raw: string}
 */
function replicate_create_prediction(string $version, array $input, int $timeoutSeconds = 120): array
{
    $token = replicate_api_token();
    if ($token === '') {
        return ['ok' => false, 'output' => null, 'error' => 'REPLICATE_API_TOKEN is not configured', 'raw' => ''];
    }

    $payload = json_encode([
        'version' => $version,
        'input' => $input,
    ]);
    if ($payload === false) {
        return ['ok' => false, 'output' => null, 'error' => 'Failed to encode Replicate payload', 'raw' => ''];
    }

    $ch = curl_init('https://api.replicate.com/v1/predictions');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $token,
            'Content-Type: application/json',
            'Prefer: wait',
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => $timeoutSeconds,
    ]);

    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw)) {
        return ['ok' => false, 'output' => null, 'error' => $curlError !== '' ? $curlError : 'No Replicate response', 'raw' => ''];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300) {
        $message = is_array($decoded)
            ? (string)($decoded['detail'] ?? $decoded['error'] ?? 'Replicate request failed')
            : 'Replicate request failed';
        return ['ok' => false, 'output' => null, 'error' => $message, 'raw' => $raw];
    }

    if (!is_array($decoded)) {
        return ['ok' => false, 'output' => null, 'error' => 'Invalid Replicate response', 'raw' => $raw];
    }

    $status = strtolower((string)($decoded['status'] ?? ''));
    if ($status === 'failed' || $status === 'canceled') {
        return [
            'ok' => false,
            'output' => null,
            'error' => (string)($decoded['error'] ?? 'Replicate prediction failed'),
            'raw' => $raw,
        ];
    }

    return [
        'ok' => true,
        'output' => $decoded['output'] ?? null,
        'error' => '',
        'raw' => $raw,
    ];
}

/**
 * @return array{ok: bool, imageUrl: string, error: string}
 */
function replicate_tryon_from_face_image(string $imageDataUrl, string $styleName, string $promptExtra = ''): array
{
    $version = trim((string)(getenv('REPLICATE_TRYON_VERSION') ?: ''));
    if ($version === '') {
        // InstantID community model version id — override in .env for your chosen model.
        $version = 'c4c54e3c8c97cd50c2d2fec9bea5b12250426ee87b563a86d917279794976753';
    }

    $prompt = trim("professional barbershop haircut preview, {$styleName}, realistic, natural lighting. {$promptExtra}");
    $result = replicate_create_prediction($version, [
        'image' => $imageDataUrl,
        'prompt' => $prompt,
        'negative_prompt' => 'cartoon, anime, blurry, distorted face, extra limbs',
        'ip_adapter_scale' => 0.8,
        'controlnet_conditioning_scale' => 0.8,
    ]);

    if (!$result['ok']) {
        return ['ok' => false, 'imageUrl' => '', 'error' => $result['error']];
    }

    $output = $result['output'];
    if (is_string($output) && $output !== '') {
        return ['ok' => true, 'imageUrl' => $output, 'error' => ''];
    }
    if (is_array($output) && isset($output[0]) && is_string($output[0])) {
        return ['ok' => true, 'imageUrl' => $output[0], 'error' => ''];
    }

    return ['ok' => false, 'imageUrl' => '', 'error' => 'Replicate returned no image URL'];
}
