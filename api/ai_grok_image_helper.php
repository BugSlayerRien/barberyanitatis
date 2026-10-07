<?php
declare(strict_types=1);

/**
 * Grok Imagine (xAI) image editing for 3-angle face-scan try-on.
 * Uses POST https://api.x.ai/v1/images/edits with model grok-imagine-image by default.
 *
 * Reuses the shared style tables, hair-only prompt builder, and image resize/data-URI
 * helper from replicate_helper.php so all providers stay behaviorally consistent.
 */

require_once __DIR__ . '/replicate_helper.php';

function grok_image_api_key(): string
{
    return trim((string)(
        getenv('GROK_IMAGE_API_KEY')
        ?: ($_ENV['GROK_IMAGE_API_KEY'] ?? $_SERVER['GROK_IMAGE_API_KEY'] ?? '')
        ?: getenv('XAI_API_KEY')
        ?: ($_ENV['XAI_API_KEY'] ?? $_SERVER['XAI_API_KEY'] ?? '')
    ));
}

function grok_image_model(): string
{
    $model = trim((string)(getenv('GROK_IMAGE_MODEL') ?: ($_ENV['GROK_IMAGE_MODEL'] ?? '')));
    return $model !== '' ? $model : 'grok-imagine-image';
}

function grok_image_is_configured(): bool
{
    $key = grok_image_api_key();
    return $key !== '' && $key !== 'REPLACE_WITH_XAI_KEY';
}

/**
 * Single image-edit call via Grok Imagine: source photo + text prompt → raw image bytes.
 *
 * @return array{ok: bool, bytes: string, error: string}
 */
function grok_generate_image_edit(string $absoluteImagePath, string $prompt): array
{
    $apiKey = grok_image_api_key();
    if ($apiKey === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Grok/xAI image API key is not configured'];
    }

    $data = replicate_image_to_data_uri($absoluteImagePath);
    if (!$data['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => $data['error']];
    }

    $payload = json_encode([
        'model' => grok_image_model(),
        'prompt' => $prompt,
        'image' => [
            'url' => $data['dataUri'],
            'type' => 'image_url',
        ],
    ]);
    if ($payload === false) {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to encode Grok payload'];
    }

    $ch = curl_init('https://api.x.ai/v1/images/edits');
    $opts = [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $apiKey,
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 180,
    ];
    if (function_exists('api_curl_ssl_options')) {
        $opts += api_curl_ssl_options();
    }
    curl_setopt_array($ch, $opts);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw)) {
        return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'No response from Grok'];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
        $detail = is_array($decoded)
            ? (string)($decoded['error']['message'] ?? $decoded['error'] ?? substr($raw, 0, 400))
            : substr($raw, 0, 400);
        return ['ok' => false, 'bytes' => '', 'error' => "Grok error ({$httpCode}): {$detail}"];
    }

    $outputUrl = '';
    if (!empty($decoded['data'][0]['url']) && is_string($decoded['data'][0]['url'])) {
        $outputUrl = $decoded['data'][0]['url'];
    } elseif (!empty($decoded['url']) && is_string($decoded['url'])) {
        $outputUrl = $decoded['url'];
    } elseif (!empty($decoded['data'][0]['b64_json']) && is_string($decoded['data'][0]['b64_json'])) {
        $bytes = base64_decode($decoded['data'][0]['b64_json'], true);
        if (is_string($bytes) && $bytes !== '') {
            return ['ok' => true, 'bytes' => $bytes, 'error' => ''];
        }
    }

    if ($outputUrl === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Grok returned no image URL'];
    }

    $imgCh = curl_init($outputUrl);
    $imgOpts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 120,
        CURLOPT_FOLLOWLOCATION => true,
    ];
    if (function_exists('api_curl_ssl_options')) {
        $imgOpts += api_curl_ssl_options();
    }
    curl_setopt_array($imgCh, $imgOpts);
    $imgBytes = curl_exec($imgCh);
    curl_close($imgCh);

    if (!is_string($imgBytes) || $imgBytes === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to download Grok-generated image'];
    }

    return ['ok' => true, 'bytes' => $imgBytes, 'error' => ''];
}

/**
 * Generate front/left/right try-on images via Grok Imagine from stored captures.
 *
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array{ok: bool, images: array<string, string>, error: string}
 */
function grok_generate_three_view_previews(
    array $capturePaths,
    string $styleName,
    ?string $styleCode = null,
    int $hairLengthLevel = 1,
    string $hairColorLabel = ''
): array {
    foreach (['front', 'left', 'right'] as $angle) {
        if (empty($capturePaths[$angle])) {
            return ['ok' => false, 'images' => [], 'error' => "Missing capture: {$angle}"];
        }
    }

    $brief = replicate_style_brief($styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
    if (!$brief['ok']) {
        return ['ok' => false, 'images' => [], 'error' => $brief['error']];
    }
    $basePrompt = $brief['basePrompt'];

    $hints = replicate_view_angle_hints();
    $resultImages = [];
    foreach (['front', 'left', 'right'] as $viewKey) {
        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$viewKey]);
        $viewPrompt = $basePrompt . ' ' . ($hints[$viewKey] ?? '');
        $generated = grok_generate_image_edit($absolute, $viewPrompt);
        if (!$generated['ok']) {
            return [
                'ok' => false,
                'images' => [],
                'error' => $viewKey . ' view: ' . $generated['error'],
            ];
        }
        $resultImages[$viewKey] = $generated['bytes'];
    }

    grok_retry_duplicate_views($resultImages, $capturePaths, $basePrompt, $hints);
    // Byte-identical duplicates are rare; the real failure is a view that comes
    // back turned the wrong way. Verify each profile against its own input and
    // mirror it when the generator flipped the head.
    $orientationReport = tryon_enforce_view_orientation($resultImages, $capturePaths);

    return [
        'ok' => true,
        'images' => $resultImages,
        'orientation' => $orientationReport,
        'error' => '',
    ];
}

/**
 * Grok equivalent of replicate_retry_duplicate_views() — same exact-byte-match
 * safety net, widened to check both profile angles against front as well as
 * against each other, not just left-vs-right. See that function's doc comment for
 * why this only catches literal duplicate bytes, not general pose correctness.
 *
 * @param array<string, string> $resultImages front/left/right bytes, mutated in place
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @param array<string, string> $hints from replicate_view_angle_hints()
 */
function grok_retry_duplicate_views(array &$resultImages, array $capturePaths, string $basePrompt, array $hints): void
{
    $pairs = [
        'left' => ['front', 'right'],
        'right' => ['front', 'left'],
    ];

    foreach ($pairs as $angle => $others) {
        if (!isset($resultImages[$angle])) {
            continue;
        }
        $duplicateOf = null;
        foreach ($others as $other) {
            if (isset($resultImages[$other])
                && hash('sha256', $resultImages[$angle]) === hash('sha256', $resultImages[$other])) {
                $duplicateOf = $other;
                break;
            }
        }
        if ($duplicateOf === null) {
            continue;
        }

        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$angle]);
        $side = $angle === 'left' ? 'LEFT' : 'RIGHT';
        $oppositeSide = $angle === 'left' ? 'right (nose toward the right)' : 'left (nose toward the left)';
        $retryPrompt = $basePrompt . ' ' . ($hints[$angle] ?? '')
            . " CRITICAL: This output was a duplicate of the {$duplicateOf} view — that is WRONG. "
            . "This input is {$side} profile only: the head must be turned, nose pointing away from "
            . "the {$oppositeSide} side of the frame, clearly different from a straight-on or "
            . 'opposite-side photo.';
        $retry = grok_generate_image_edit($absolute, $retryPrompt);
        if ($retry['ok']) {
            $resultImages[$angle] = $retry['bytes'];
        }
    }
}
