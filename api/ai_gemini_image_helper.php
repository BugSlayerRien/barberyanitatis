<?php
declare(strict_types=1);

/**
 * Gemini image generation/editing (nano-banana family, e.g. gemini-2.5-flash-image) for
 * 3-angle face-scan try-on. Kept separate from api/ai_gemini_helper.php on purpose — that
 * file is for text-only chat/ranking models, this one is strictly for image models
 * (see design review G4).
 *
 * Reuses the shared style tables, hair-only prompt builder, and image resize/data-URI
 * helper from replicate_helper.php so both providers stay behaviorally consistent.
 */

require_once __DIR__ . '/replicate_helper.php';

function gemini_image_api_key(): string
{
    return trim((string)(
        getenv('GEMINI_IMAGE_API_KEY')
        ?: ($_ENV['GEMINI_IMAGE_API_KEY'] ?? $_SERVER['GEMINI_IMAGE_API_KEY'] ?? '')
        ?: getenv('AI_API_KEY')
        ?: ($_ENV['AI_API_KEY'] ?? $_SERVER['AI_API_KEY'] ?? '')
        ?: getenv('GEMINI_API_KEY')
        ?: ($_ENV['GEMINI_API_KEY'] ?? $_SERVER['GEMINI_API_KEY'] ?? '')
    ));
}

function gemini_image_model(): string
{
    $model = trim((string)(getenv('GEMINI_IMAGE_MODEL') ?: ($_ENV['GEMINI_IMAGE_MODEL'] ?? '')));
    return $model !== '' ? $model : 'gemini-2.5-flash-image';
}

function gemini_image_is_configured(): bool
{
    $key = gemini_image_api_key();
    return $key !== '' && $key !== 'REPLACE_WITH_GEMINI_KEY';
}

/**
 * Single image-edit call: sends one source photo + one text prompt, returns the raw
 * bytes of the edited image.
 *
 * @return array{ok: bool, bytes: string, error: string}
 */
function gemini_generate_image_edit(string $absoluteImagePath, string $prompt): array
{
    $apiKey = gemini_image_api_key();
    if ($apiKey === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Gemini image API key is not configured'];
    }

    $data = replicate_image_to_data_uri($absoluteImagePath);
    if (!$data['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => $data['error']];
    }

    $matches = [];
    if (!preg_match('/^data:([^;]+);base64,(.+)$/', $data['dataUri'], $matches)) {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to encode source image'];
    }
    $mimeType = $matches[1];
    $base64Data = $matches[2];

    $model = gemini_image_model();
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        . rawurlencode($model) . ':generateContent?key=' . urlencode($apiKey);

    $payload = json_encode([
        'contents' => [
            [
                'parts' => [
                    ['text' => $prompt],
                    [
                        'inline_data' => [
                            'mime_type' => $mimeType,
                            'data' => $base64Data,
                        ],
                    ],
                ],
            ],
        ],
        'generationConfig' => [
            'temperature' => 0.2,
            'responseModalities' => ['IMAGE'],
        ],
    ]);
    if ($payload === false) {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to encode Gemini payload'];
    }

    $ch = curl_init($url);
    $opts = [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 120,
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
        return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'No response from Gemini'];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
        $detail = is_array($decoded)
            ? (string)($decoded['error']['message'] ?? substr($raw, 0, 400))
            : substr($raw, 0, 400);
        return ['ok' => false, 'bytes' => '', 'error' => "Gemini error ({$httpCode}): {$detail}"];
    }

    $parts = $decoded['candidates'][0]['content']['parts'] ?? [];
    if (is_array($parts)) {
        foreach ($parts as $part) {
            $inline = $part['inlineData'] ?? $part['inline_data'] ?? null;
            if (is_array($inline) && !empty($inline['data'])) {
                $bytes = base64_decode((string)$inline['data'], true);
                if (is_string($bytes) && $bytes !== '') {
                    return ['ok' => true, 'bytes' => $bytes, 'error' => ''];
                }
            }
        }
    }

    $finishReason = (string)($decoded['candidates'][0]['finishReason'] ?? '');
    $blockReason = (string)($decoded['promptFeedback']['blockReason'] ?? '');
    $reasonNote = $blockReason !== ''
        ? " (blocked: {$blockReason})"
        : ($finishReason !== '' ? " (finish: {$finishReason})" : '');

    return ['ok' => false, 'bytes' => '', 'error' => 'Gemini returned no image data' . $reasonNote];
}

/**
 * Generate front/left/right try-on images via Gemini from stored captures. Mirrors
 * replicate_generate_three_view_previews()'s contract so face_scan.php / the provider
 * router can treat both providers identically.
 *
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array{ok: bool, images: array<string, string>, feasibleToday: bool, lengthNote: ?string, error: string}
 */
function gemini_generate_three_view_previews(
    array $capturePaths,
    string $styleName,
    ?string $styleCode = null,
    int $hairLengthLevel = 1,
    string $hairColorLabel = ''
): array {
    foreach (['front', 'left', 'right'] as $angle) {
        if (empty($capturePaths[$angle])) {
            return ['ok' => false, 'images' => [], 'feasibleToday' => true, 'lengthNote' => null, 'error' => "Missing capture: {$angle}"];
        }
    }

    $styleKey = replicate_resolve_style_key($styleName, $styleCode);
    $prompts = replicate_style_prompts();
    $styleDesc = $prompts[$styleKey] ?? ($styleName . ' hairstyle');
    $minLengths = replicate_style_min_length();
    $feasibleToday = ($minLengths[$styleKey] ?? 1) <= $hairLengthLevel;
    $lengthNote = null;
    if (!$feasibleToday) {
        $lengthNote = 'This style usually needs more length than detected today. '
            . 'Preview shows the target look — ask your barber what is achievable today.';
    }

    $profileNote = ' Use the same haircut design on all three photos, but each output must keep '
        . "that photo's original head turn and camera angle — do not make every frame face the camera.";

    if ($feasibleToday) {
        $basePrompt = replicate_build_hair_only_prompt($styleDesc, $hairLengthLevel, $hairColorLabel) . $profileNote;
    } else {
        $basePrompt = 'HAIR-ONLY ASPIRATIONAL EDIT. Preview longer hair with style: '
            . "{$styleDesc}. FORBIDDEN: changing face, skin, eyes, clothing, or background. "
            . "Identity and background must match the input.{$profileNote}";
    }

    $hints = replicate_view_angle_hints();
    $resultImages = [];
    foreach (['front', 'left', 'right'] as $viewKey) {
        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$viewKey]);
        $viewPrompt = $basePrompt . ' ' . ($hints[$viewKey] ?? '');
        $generated = gemini_generate_image_edit($absolute, $viewPrompt);
        if (!$generated['ok']) {
            return [
                'ok' => false,
                'images' => [],
                'feasibleToday' => $feasibleToday,
                'lengthNote' => $lengthNote,
                'error' => $viewKey . ' view: ' . $generated['error'],
            ];
        }
        $resultImages[$viewKey] = $generated['bytes'];
    }

    if (isset($resultImages['left'], $resultImages['right'])
        && hash('sha256', $resultImages['left']) === hash('sha256', $resultImages['right'])) {
        $absoluteRight = replicate_absolute_path_from_relative((string)$capturePaths['right']);
        $retryPrompt = $basePrompt . ' ' . ($hints['right'] ?? '')
            . ' CRITICAL: The right-profile output must NOT match the left-profile output. '
            . 'This input is RIGHT profile only: nose must stay toward the LEFT side of the frame.';
        $retry = gemini_generate_image_edit($absoluteRight, $retryPrompt);
        if ($retry['ok']) {
            $resultImages['right'] = $retry['bytes'];
        }
    }

    return [
        'ok' => true,
        'images' => $resultImages,
        'feasibleToday' => $feasibleToday,
        'lengthNote' => $lengthNote,
        'error' => '',
    ];
}
