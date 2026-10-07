<?php
declare(strict_types=1);

/**
 * HTTP client for the Python AI try-on sidecar (ai-service/api.py).
 * Set AI_SERVICE_URL in .env (e.g. http://127.0.0.1:8000).
 */

require_once __DIR__ . '/storage.php';

function ai_service_base_url(): string
{
    $url = trim((string)(getenv('AI_SERVICE_URL') ?: ($_ENV['AI_SERVICE_URL'] ?? '')));
    return rtrim($url, '/');
}

function ai_service_health_ok(string $base): bool
{
    $ch = curl_init($base . '/health');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 12,
        CURLOPT_CONNECTTIMEOUT => 6,
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

function ai_service_is_available(): bool
{
    $base = ai_service_base_url();
    if ($base === '') {
        return false;
    }

    $attempts = 3;
    for ($i = 0; $i < $attempts; $i++) {
        if (ai_service_health_ok($base)) {
            return true;
        }
        if ($i < $attempts - 1) {
            usleep(400000 * ($i + 1));
        }
    }

    return false;
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
 * Ask the sidecar to verify a generated view's head turn and mirror it if the
 * generator flipped it. Returns corrected JPEG bytes, or null when nothing
 * needed changing / the check could not run.
 *
 * Mirroring lives in the sidecar because it already has OpenCV; the PHP image
 * ships without the GD extension, so imageflip() is not available there.
 */
function ai_service_enforce_view_orientation(string $absolutePath, string $expected): ?string
{
    $base = ai_service_base_url();
    if ($base === '' || !is_readable($absolutePath)) {
        return null;
    }
    if (!in_array($expected, ['left', 'right'], true)) {
        return null;
    }

    $file = ai_service_curl_file($absolutePath, basename($absolutePath));
    if ($file === null) {
        return null;
    }

    $result = ai_service_multipart_post(
        $base . '/enforce-view-orientation',
        ['image' => $file, 'expected' => $expected],
        45
    );
    if (!($result['ok'] ?? false)) {
        return null;
    }

    $data = $result['data'] ?? [];
    if (($data['corrected'] ?? false) !== true) {
        return null;
    }
    $encoded = (string)($data['image'] ?? '');
    if ($encoded === '') {
        return null;
    }
    $bytes = base64_decode($encoded, true);
    return ($bytes !== false && $bytes !== '') ? $bytes : null;
}

/**
 * Head-turn direction for one image, via the sidecar's landmark geometry.
 *
 * Returns 'left', 'right', 'front', or null when it could not be determined
 * (sidecar down, no face found). Callers must treat null as "unknown" and skip
 * the check rather than assuming a direction.
 */
function ai_service_face_orientation(string $absolutePath): ?string
{
    $probe = ai_service_face_yaw($absolutePath);
    return $probe === null ? null : $probe['direction'];
}

/**
 * Head-turn direction AND the signed yaw behind it.
 *
 * Same single request as ai_service_face_orientation() — /face-orientation has
 * always returned `yaw` alongside `direction`, we simply threw the number away.
 * The number is what makes left-vs-right duplicate detection possible: two
 * generated profiles turned the same way share a yaw sign, even when their
 * bytes differ enough to defeat a hash comparison.
 *
 * Returns ['direction' => 'left'|'right'|'front', 'yaw' => float], or null when
 * it could not be determined (sidecar down, no face found). Callers must treat
 * null as "unknown" and skip the check rather than assuming a direction.
 *
 * @return array{direction: string, yaw: float}|null
 */
function ai_service_face_yaw(string $absolutePath): ?array
{
    $base = ai_service_base_url();
    if ($base === '' || !is_readable($absolutePath)) {
        return null;
    }

    $file = ai_service_curl_file($absolutePath, basename($absolutePath));
    if ($file === null) {
        return null;
    }

    $result = ai_service_multipart_post($base . '/face-orientation', ['image' => $file], 30);
    if (!($result['ok'] ?? false)) {
        return null;
    }
    $data = $result['data'] ?? [];
    if (($data['ok'] ?? false) !== true) {
        return null;
    }
    $direction = (string)($data['direction'] ?? '');
    if (!in_array($direction, ['left', 'right', 'front'], true)) {
        return null;
    }

    return [
        'direction' => $direction,
        'yaw' => (float)($data['yaw'] ?? 0.0),
    ];
}

/**
 * @param array{front: string, left: string, right: string} $absolutePaths
 * @return array{ok: bool, images: array<string, string>, styleKey: string, previewDiagnostics: array<string, array<string, mixed>>, error: string}
 */
function ai_service_generate_style(
    array $absolutePaths,
    string $styleName,
    ?string $styleCode,
    int $hairLengthLevel = 1,
    string $hairColorLabel = ''
): array {
    $base = ai_service_base_url();
    if ($base === '') {
        return ['ok' => false, 'images' => [], 'styleKey' => '', 'previewDiagnostics' => [], 'error' => 'AI_SERVICE_URL is not configured'];
    }

    $resolvedCode = $styleCode !== null && $styleCode !== '' ? $styleCode : $styleName;
    $fields = [
        'face_image' => ai_service_curl_file($absolutePaths['front'] ?? '', 'front.jpg'),
        'left_image' => ai_service_curl_file($absolutePaths['left'] ?? '', 'left.jpg'),
        'right_image' => ai_service_curl_file($absolutePaths['right'] ?? '', 'right.jpg'),
        'style' => $resolvedCode,
        'style_name' => $styleName,
        'style_code' => $styleCode ?? '',
        'hair_length_level' => (string)max(0, min(3, $hairLengthLevel)),
        'hair_color' => $hairColorLabel,
    ];

    if ($fields['face_image'] === null || $fields['left_image'] === null || $fields['right_image'] === null) {
        return ['ok' => false, 'images' => [], 'styleKey' => '', 'previewDiagnostics' => [], 'error' => 'Missing capture files for generation'];
    }

    $response = ai_service_multipart_post($base . '/generate', $fields, 600);
    if (!$response['ok']) {
        return [
            'ok' => false,
            'images' => [],
            'styleKey' => '',
            'previewDiagnostics' => [],
            'error' => $response['error'],
        ];
    }

    $data = $response['data'];
    $resultImages = $data['result_images'] ?? [];
    if (!is_array($resultImages)) {
        return ['ok' => false, 'images' => [], 'styleKey' => '', 'previewDiagnostics' => [], 'error' => 'Sidecar returned no result_images'];
    }

    $rawDiagnostics = $data['preview_diagnostics'] ?? $data['previewDiagnostics'] ?? [];
    $previewDiagnostics = is_array($rawDiagnostics) ? $rawDiagnostics : [];

    $images = [];
    foreach (['front', 'left', 'right'] as $angle) {
        $b64 = $resultImages[$angle] ?? '';
        if (!is_string($b64) || $b64 === '') {
            return ['ok' => false, 'images' => [], 'styleKey' => '', 'previewDiagnostics' => [], 'error' => "Missing {$angle} in sidecar response"];
        }
        $bytes = base64_decode($b64, true);
        if ($bytes === false || $bytes === '') {
            return ['ok' => false, 'images' => [], 'styleKey' => '', 'previewDiagnostics' => [], 'error' => "Invalid base64 for {$angle}"];
        }
        $images[$angle] = $bytes;
    }

    return [
        'ok' => true,
        'images' => $images,
        'styleKey' => (string)($data['style'] ?? ''),
        'previewDiagnostics' => $previewDiagnostics,
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
    $out = [];
    foreach (['front', 'left', 'right'] as $angle) {
        $rel = $relativePaths[$angle] ?? null;
        if ($rel === null || $rel === '') {
            continue;
        }
        try {
            $out[$angle] = storage_ensure_readable_file((string)$rel);
        } catch (Throwable $e) {
            $out[$angle] = api_project_root() . DIRECTORY_SEPARATOR
                . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim((string)$rel, '/'));
        }
    }

    return $out;
}
