<?php
declare(strict_types=1);

/**
 * HTTP client for the Python AI try-on sidecar (ai-service/api.py).
 * Set AI_SERVICE_URL in .env (e.g. http://127.0.0.1:8000).
 */

function ai_service_base_url(): string
{
    $url = trim((string)(getenv('AI_SERVICE_URL') ?: ($_ENV['AI_SERVICE_URL'] ?? '')));
    return rtrim($url, '/');
}

function ai_service_is_available(): bool
{
    $base = ai_service_base_url();
    if ($base === '') {
        return false;
    }

    $ch = curl_init($base . '/health');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 8,
        CURLOPT_CONNECTTIMEOUT => 4,
    ] + api_curl_ssl_options());
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if (!is_string($raw) || $code < 200 || $code >= 300) {
        return false;
    }

    $data = json_decode($raw, true);
    return is_array($data) && ($data['ok'] ?? false) === true;
}

/**
 * @param array{front: string, left: string, right: string} $absolutePaths
 * @return array{ok: bool, data: array<string, mixed>, error: string}
 */
function ai_service_analyze_face(array $absolutePaths): array
{
    $base = ai_service_base_url();
    if ($base === '') {
        return ['ok' => false, 'data' => [], 'error' => 'AI_SERVICE_URL is not configured'];
    }

    $fields = [
        'face_image' => ai_service_curl_file($absolutePaths['front'] ?? '', 'front.jpg'),
        'left_image' => ai_service_curl_file($absolutePaths['left'] ?? '', 'left.jpg'),
        'right_image' => ai_service_curl_file($absolutePaths['right'] ?? '', 'right.jpg'),
    ];

    if ($fields['face_image'] === null || $fields['left_image'] === null || $fields['right_image'] === null) {
        return ['ok' => false, 'data' => [], 'error' => 'Missing capture files for analysis'];
    }

    return ai_service_multipart_post($base . '/analyze-face', $fields, 60);
}

/**
 * @param array{front: string, left: string, right: string} $absolutePaths
 * @return array{ok: bool, images: array<string, string>, feasibleToday: bool, lengthNote: ?string, styleKey: string, error: string}
 */
function ai_service_generate_style(
    array $absolutePaths,
    string $styleName,
    ?string $styleCode,
    int $hairLengthLevel = 1
): array {
    $base = ai_service_base_url();
    if ($base === '') {
        return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'styleKey' => '', 'error' => 'AI_SERVICE_URL is not configured'];
    }

    $style = $styleCode !== null && $styleCode !== '' ? $styleCode : $styleName;
    $fields = [
        'face_image' => ai_service_curl_file($absolutePaths['front'] ?? '', 'front.jpg'),
        'left_image' => ai_service_curl_file($absolutePaths['left'] ?? '', 'left.jpg'),
        'right_image' => ai_service_curl_file($absolutePaths['right'] ?? '', 'right.jpg'),
        'style' => $style,
        'hair_length_level' => (string)max(0, min(3, $hairLengthLevel)),
    ];

    if ($fields['face_image'] === null || $fields['left_image'] === null || $fields['right_image'] === null) {
        return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'styleKey' => '', 'error' => 'Missing capture files for generation'];
    }

    $response = ai_service_multipart_post($base . '/generate', $fields, 600);
    if (!$response['ok']) {
        return [
            'ok' => false,
            'images' => [],
            'feasibleToday' => true,
            'lengthNote' => null,
            'styleKey' => '',
            'error' => $response['error'],
        ];
    }

    $data = $response['data'];
    $resultImages = $data['result_images'] ?? [];
    if (!is_array($resultImages)) {
        return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'styleKey' => '', 'error' => 'Sidecar returned no result_images'];
    }

    $images = [];
    foreach (['front', 'left', 'right'] as $angle) {
        $b64 = $resultImages[$angle] ?? '';
        if (!is_string($b64) || $b64 === '') {
            return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'styleKey' => '', 'error' => "Missing {$angle} in sidecar response"];
        }
        $bytes = base64_decode($b64, true);
        if ($bytes === false || $bytes === '') {
            return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'styleKey' => '', 'error' => "Invalid base64 for {$angle}"];
        }
        $images[$angle] = $bytes;
    }

    return [
        'ok' => true,
        'images' => $images,
        'feasibleToday' => (bool)($data['feasible_today'] ?? $data['feasibleToday'] ?? true),
        'lengthNote' => isset($data['length_note']) ? (string)$data['length_note'] : (isset($data['lengthNote']) ? (string)$data['lengthNote'] : null),
        'styleKey' => (string)($data['style'] ?? ''),
        'error' => '',
    ];
}

/**
 * @return array{ok: bool, data: array<string, mixed>, error: string}
 */
function ai_service_multipart_post(string $url, array $fields, int $timeoutSeconds): array
{
    $postFields = [];
    foreach ($fields as $key => $value) {
        if ($value === null) {
            continue;
        }
        $postFields[$key] = $value;
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $postFields,
        CURLOPT_TIMEOUT => $timeoutSeconds,
        CURLOPT_CONNECTTIMEOUT => 15,
    ] + api_curl_ssl_options());

    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw)) {
        return ['ok' => false, 'data' => [], 'error' => $curlError !== '' ? $curlError : 'No response from AI service'];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300) {
        $message = is_array($decoded)
            ? (string)($decoded['error'] ?? $decoded['detail'] ?? 'AI service request failed')
            : substr($raw, 0, 400);
        return ['ok' => false, 'data' => [], 'error' => $message];
    }

    if (!is_array($decoded)) {
        return ['ok' => false, 'data' => [], 'error' => 'Invalid JSON from AI service'];
    }

    return ['ok' => true, 'data' => $decoded, 'error' => ''];
}

/**
 * @return CURLStringFile|null
 */
function ai_service_curl_file(string $absolutePath, string $uploadName)
{
    if ($absolutePath === '' || !is_readable($absolutePath)) {
        return null;
    }

    $mime = 'image/jpeg';
    return new CURLStringFile((string)file_get_contents($absolutePath), $uploadName, $mime);
}

/**
 * @param array{front: ?string, left: ?string, right: ?string} $relativePaths
 * @return array{front: string, left: string, right: string}
 */
function ai_service_absolute_capture_paths(array $relativePaths): array
{
    $root = dirname(__DIR__);
    $out = [];
    foreach (['front', 'left', 'right'] as $angle) {
        $rel = $relativePaths[$angle] ?? null;
        if ($rel === null || $rel === '') {
            continue;
        }
        $out[$angle] = $root . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim((string)$rel, '/'));
    }

    return $out;
}
