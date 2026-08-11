<?php
declare(strict_types=1);

/**
 * Replicate Flux Kontext try-on for 3-angle face scan captures.
 * Ported from backend-replicate/api.py — server-side only (REPLICATE_API_TOKEN in .env).
 */

function replicate_curl_set($ch, array $options): void
{
    curl_setopt_array($ch, $options + api_curl_ssl_options());
}

function replicate_api_token(): string
{
    return trim((string)(getenv('REPLICATE_API_TOKEN') ?: ($_ENV['REPLICATE_API_TOKEN'] ?? '')));
}

function replicate_is_configured(): bool
{
    return replicate_api_token() !== '';
}

function replicate_flux_model(): string
{
    $model = trim((string)(getenv('REPLICATE_FLUX_MODEL') ?: ($_ENV['REPLICATE_FLUX_MODEL'] ?? '')));
    return $model !== '' ? $model : 'black-forest-labs/flux-kontext-pro';
}

/** @return array<string, string> */
function replicate_style_prompts(): array
{
    return [
        'buzz_cut' => 'buzz cut hairstyle, very short uniform hair, clean fade',
        'french_crop' => 'french crop hairstyle, short textured top, faded sides',
        'low_fade' => 'low fade hairstyle, gradual fade on sides, natural top',
        'blowout_taper' => 'blowout taper hairstyle, voluminous top, tapered sides',
        'two_block' => 'two block hairstyle, long top short sides korean style',
        'barbers_cut' => 'classic barbers cut, neat professional hairstyle',
        'modern_mullet' => 'modern mullet hairstyle, short sides long back',
        'edgar_cut' => 'edgar cut hairstyle, straight fringe sharp line',
        'caesar_cut' => 'caesar cut hairstyle, short horizontal fringe',
        'textured_crop' => 'textured crop wavy hairstyle, messy natural waves',
        'messy_quiff' => 'messy quiff wavy hairstyle, voluminous front',
        'modern_curtains' => 'modern curtains hairstyle, middle part wavy',
        'wavy_mod_cut' => 'wavy mod cut hairstyle, bowl shape with waves',
        'wavy_fringe' => 'wavy fringe hairstyle, wavy hair with fringe',
        'wavy_burst_fade' => 'wavy burst fade hairstyle, waves on top fade sides',
        'wavy_side_sweep' => 'wavy side sweep hairstyle, swept to one side',
        'wavy_messy_top' => 'wavy messy top hairstyle, natural messy waves',
        'curly_taper' => 'curly taper hairstyle, curly top tapered sides',
        'curly_modern_mullet' => 'curly modern mullet, curly long back short sides',
        'curly_burst_fade' => 'curly burst fade, curly afro burst fade sides',
        'curly_mid_fade' => 'curly mid fade hairstyle, curls on top mid fade',
        'curly_drop_fade' => 'curly drop fade hairstyle, curly top drop fade',
        'curly_short_crop' => 'curly short crop hairstyle, short tight curls',
        'curly_crew_cut' => 'curly crew cut hairstyle, short curly uniform',
        'curly_edgar' => 'curly edgar hairstyle, curly hair straight fringe',
    ];
}

/** @return array<int, string> */
function replicate_hair_length_labels(): array
{
    return [0 => 'very short', 1 => 'short', 2 => 'medium', 3 => 'long'];
}

/** @return array<int, string> */
function replicate_length_style_hints(): array
{
    return [
        0 => 'Keep the result very short (buzz/crop length). Do not add visible length.',
        1 => 'Keep hair short; do not extend past the ears or add long layers.',
        2 => 'Keep medium length; restyle only, do not add shoulder-length hair.',
        3 => 'You may reshape or shorten slightly, but do not remove all length if the style needs volume.',
    ];
}

/** @return array<string, int> */
function replicate_style_min_length(): array
{
    return [
        'buzz_cut' => 0, 'french_crop' => 0, 'caesar_cut' => 0, 'low_fade' => 0,
        'edgar_cut' => 0, 'barbers_cut' => 0, 'curly_crew_cut' => 0, 'curly_short_crop' => 0,
        'curly_edgar' => 0, 'blowout_taper' => 1, 'textured_crop' => 1, 'messy_quiff' => 1,
        'wavy_fringe' => 1, 'wavy_burst_fade' => 1, 'wavy_side_sweep' => 1, 'wavy_messy_top' => 1,
        'curly_taper' => 1, 'curly_burst_fade' => 1, 'curly_mid_fade' => 1, 'curly_drop_fade' => 1,
        'two_block' => 2, 'modern_curtains' => 2, 'wavy_mod_cut' => 2, 'modern_mullet' => 2,
        'curly_modern_mullet' => 3,
    ];
}

function replicate_normalize_style_key(string $raw): string
{
    $key = strtolower(trim($raw));
    $key = preg_replace('/[^a-z0-9]+/', '_', $key) ?? $key;
    $key = trim($key, '_');
    return $key;
}

function replicate_resolve_style_key(string $styleName, ?string $styleCode = null): string
{
    $prompts = replicate_style_prompts();
    if ($styleCode !== null && $styleCode !== '') {
        $codeKey = replicate_normalize_style_key($styleCode);
        if (isset($prompts[$codeKey])) {
            return $codeKey;
        }
    }

    $nameKey = replicate_normalize_style_key($styleName);
    if (isset($prompts[$nameKey])) {
        return $nameKey;
    }

    $nameLower = strtolower($styleName);
    foreach (array_keys($prompts) as $key) {
        $label = str_replace('_', ' ', $key);
        if ($nameLower !== '' && str_contains($nameLower, $label)) {
            return $key;
        }
    }

    return 'barbers_cut';
}

/**
 * Shared hair-only, identity-locked edit prompt used by every image-generation provider
 * (Gemini and the Replicate fallback) so results stay consistent regardless of which
 * provider actually renders the image.
 */
function replicate_build_hair_only_prompt(
    string $styleDescription,
    int $hairLengthLevel = 1,
    string $hairColorLabel = ''
): string {
    $hints = replicate_length_style_hints();
    $labels = replicate_hair_length_labels();
    $lengthHint = $hints[$hairLengthLevel] ?? $hints[1];
    $currentLabel = $labels[$hairLengthLevel] ?? 'short';
    $colorClause = '';
    if (trim($hairColorLabel) !== '') {
        $colorClause = ' Preserve the person\'s natural ' . trim($hairColorLabel)
            . ' hair color exactly. Do not lighten, darken, redden, or recolor the hair.';
    }

    return 'Photo-realistic HAIR-ONLY edit of the attached photo. Change ONLY the hair on this '
        . 'exact person — crown, top, sides, temples, sideburns, and back hairline — to this '
        . "exact haircut: \"{$styleDescription}\". Current length: {$currentLabel}. {$lengthHint} "
        . 'Completely remove the old hairstyle everywhere, not just the tips or one side; the new '
        . 'cut silhouette must look clearly different from the original. Do not paste extra hair '
        . 'onto forehead skin, cheeks, or neck. '
        . 'STRICT IDENTITY LOCK — do not change: face shape, facial features, facial expression, '
        . 'skin tone and texture, blemishes or marks, eyebrows, eyes, eyeglasses if present, ears, '
        . 'neck, body proportions, age, or gender. This must remain the exact same person, not a '
        . 'different or idealized person. '
        . 'Keep the same shirt/clothing and the same room background unchanged. '
        . 'Preserve the original head pose, camera angle, framing, perspective, and lighting '
        . 'direction/intensity exactly as captured in the source photo. '
        . 'Output one single photo-realistic image — not an illustration, sketch, or cartoon.'
        . $colorClause;
}

/** @return array<string, string> */
function replicate_view_angle_hints(): array
{
    return [
        'front' => 'Front view: keep the subject looking straight at the camera.',
        'left' => 'This run uses your LEFT-profile photo only.',
        'right' => 'This run uses your RIGHT-profile photo only (different head turn than the left photo).',
    ];
}

function replicate_absolute_path_from_relative(string $relativePath): string
{
    return api_project_root() . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim($relativePath, '/'));
}

/**
 * @return array{ok: bool, dataUri: string, error: string}
 */
function replicate_image_to_data_uri(string $absolutePath, int $maxSide = 1280): array
{
    if (!is_readable($absolutePath)) {
        return ['ok' => false, 'dataUri' => '', 'error' => 'Image file not readable'];
    }

    $bytes = file_get_contents($absolutePath);
    if ($bytes === false || $bytes === '') {
        return ['ok' => false, 'dataUri' => '', 'error' => 'Image file is empty'];
    }

    $mime = 'image/jpeg';
    if (function_exists('imagecreatefromstring') && function_exists('imagescale')) {
        $source = @imagecreatefromstring($bytes);
        if ($source !== false) {
            $width = imagesx($source);
            $height = imagesy($source);
            if ($width > 0 && $height > 0 && max($width, $height) > $maxSide) {
                $scale = $maxSide / max($width, $height);
                $newW = max(1, (int)round($width * $scale));
                $newH = max(1, (int)round($height * $scale));
                $scaled = imagescale($source, $newW, $newH);
                if ($scaled !== false) {
                    ob_start();
                    imagejpeg($scaled, null, 90);
                    $jpeg = ob_get_clean();
                    imagedestroy($scaled);
                    if (is_string($jpeg) && $jpeg !== '') {
                        $bytes = $jpeg;
                    }
                }
            }
            imagedestroy($source);
        }
    }

    return [
        'ok' => true,
        'dataUri' => 'data:' . $mime . ';base64,' . base64_encode($bytes),
        'error' => '',
    ];
}

/**
 * @return array{ok: bool, bytes: string, error: string}
 */
function replicate_poll_prediction(string $predictionId, int $maxAttempts = 120, int $sleepSeconds = 2): array
{
    $token = replicate_api_token();
    $url = 'https://api.replicate.com/v1/predictions/' . rawurlencode($predictionId);

    for ($i = 0; $i < $maxAttempts; $i++) {
        if ($i > 0) {
            sleep($sleepSeconds);
        }

        $ch = curl_init($url);
        replicate_curl_set($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $token,
                'Content-Type: application/json',
            ],
            CURLOPT_TIMEOUT => 60,
        ]);
        $raw = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if (!is_string($raw)) {
            return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'Poll failed'];
        }

        $decoded = json_decode($raw, true);
        if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
            return ['ok' => false, 'bytes' => '', 'error' => 'Replicate poll HTTP error'];
        }

        $status = strtolower((string)($decoded['status'] ?? ''));
        if ($status === 'succeeded') {
            $output = $decoded['output'] ?? null;
            $outputUrl = is_array($output) ? ($output[0] ?? '') : $output;
            if (!is_string($outputUrl) || $outputUrl === '') {
                return ['ok' => false, 'bytes' => '', 'error' => 'Replicate succeeded but returned no image URL'];
            }

            $imgCh = curl_init($outputUrl);
            replicate_curl_set($imgCh, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 120,
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            $imgBytes = curl_exec($imgCh);
            curl_close($imgCh);
            if (!is_string($imgBytes) || $imgBytes === '') {
                return ['ok' => false, 'bytes' => '', 'error' => 'Failed to download generated image'];
            }

            return ['ok' => true, 'bytes' => $imgBytes, 'error' => ''];
        }

        if ($status === 'failed' || $status === 'canceled') {
            $err = (string)($decoded['error'] ?? $status);
            return ['ok' => false, 'bytes' => '', 'error' => 'Replicate job ' . $status . ': ' . $err];
        }
    }

    return ['ok' => false, 'bytes' => '', 'error' => 'Replicate timed out waiting for the result'];
}

/**
 * @return array{ok: bool, bytes: string, error: string}
 */
function replicate_generate_view_image(string $absolutePath, string $basePrompt, string $viewKey, string $extra = ''): array
{
    $token = replicate_api_token();
    if ($token === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'REPLICATE_API_TOKEN is not configured'];
    }

    $data = replicate_image_to_data_uri($absolutePath);
    if (!$data['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => $data['error']];
    }

    $hints = replicate_view_angle_hints();
    $viewPrompt = $basePrompt . ' ' . ($hints[$viewKey] ?? '') . $extra;

    $model = replicate_flux_model();
    $endpoint = 'https://api.replicate.com/v1/models/' . $model . '/predictions';

    $payload = json_encode([
        'input' => [
            'prompt' => $viewPrompt,
            'input_image' => $data['dataUri'],
            'aspect_ratio' => 'match_input_image',
            'prompt_upsampling' => false,
            'output_format' => 'png',
            'safety_tolerance' => 2,
        ],
    ]);
    if ($payload === false) {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to encode Replicate payload'];
    }

    $ch = curl_init($endpoint);
    replicate_curl_set($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $token,
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 120,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw)) {
        return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'No Replicate response'];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
        $detail = is_array($decoded)
            ? (string)($decoded['detail'] ?? $decoded['error'] ?? substr($raw, 0, 400))
            : substr($raw, 0, 400);
        return ['ok' => false, 'bytes' => '', 'error' => "Replicate error ({$httpCode}): {$detail}"];
    }

    $status = strtolower((string)($decoded['status'] ?? ''));
    if ($status === 'succeeded') {
        $output = $decoded['output'] ?? null;
        $outputUrl = is_array($output) ? ($output[0] ?? '') : $output;
        if (is_string($outputUrl) && $outputUrl !== '') {
            $imgCh = curl_init($outputUrl);
            replicate_curl_set($imgCh, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 120,
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            $imgBytes = curl_exec($imgCh);
            curl_close($imgCh);
            if (is_string($imgBytes) && $imgBytes !== '') {
                return ['ok' => true, 'bytes' => $imgBytes, 'error' => ''];
            }
        }
    }

    $predictionId = (string)($decoded['id'] ?? '');
    if ($predictionId === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Replicate did not return a prediction id'];
    }

    $polled = replicate_poll_prediction($predictionId);
    if (!$polled['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => ($viewKey . ' view: ' . $polled['error'])];
    }

    return ['ok' => true, 'bytes' => $polled['bytes'], 'error' => ''];
}

/**
 * Generate front/left/right try-on images from stored captures.
 *
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array{ok: bool, images: array<string, string>, feasibleToday: bool, lengthNote: ?string, error: string}
 */
function replicate_generate_three_view_previews(
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

    $resultImages = [];
    foreach (['front', 'left', 'right'] as $viewKey) {
        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$viewKey]);
        $generated = replicate_generate_view_image($absolute, $basePrompt, $viewKey);
        if (!$generated['ok']) {
            return [
                'ok' => false,
                'images' => [],
                'feasibleToday' => $feasibleToday,
                'lengthNote' => $lengthNote,
                'error' => $generated['error'],
            ];
        }
        $resultImages[$viewKey] = $generated['bytes'];
    }

    if (isset($resultImages['left'], $resultImages['right'])
        && hash('sha256', $resultImages['left']) === hash('sha256', $resultImages['right'])) {
        $absoluteRight = replicate_absolute_path_from_relative((string)$capturePaths['right']);
        $retryExtra = ' CRITICAL: The right-profile output must NOT match the left-profile output. '
            . 'This input is RIGHT profile only: nose must stay toward the LEFT side of the frame.';
        $retry = replicate_generate_view_image($absoluteRight, $basePrompt, 'right', $retryExtra);
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

/**
 * Legacy single-image helper (InstantID version path) — kept for compatibility.
 *
 * @return array{ok: bool, imageUrl: string, error: string}
 */
function replicate_tryon_from_face_image(string $imageDataUrl, string $styleName, string $promptExtra = ''): array
{
    $styleKey = replicate_resolve_style_key($styleName);
    $prompts = replicate_style_prompts();
    $styleDesc = $prompts[$styleKey] ?? $styleName;
    $prompt = replicate_build_hair_only_prompt($styleDesc, 1) . ' ' . $promptExtra;

    $version = trim((string)(getenv('REPLICATE_TRYON_VERSION') ?: ''));
    if ($version === '') {
        $version = 'c4c54e3c8c97cd50c2d2fec9bea5b12250426ee87b563a86d917279794976753';
    }

    $token = replicate_api_token();
    if ($token === '') {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'REPLICATE_API_TOKEN is not configured'];
    }

    $payload = json_encode([
        'version' => $version,
        'input' => [
            'image' => $imageDataUrl,
            'prompt' => $prompt,
            'negative_prompt' => 'cartoon, anime, blurry, distorted face, extra limbs',
            'ip_adapter_scale' => 0.8,
            'controlnet_conditioning_scale' => 0.8,
        ],
    ]);

    $ch = curl_init('https://api.replicate.com/v1/predictions');
    replicate_curl_set($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $token,
            'Content-Type: application/json',
            'Prefer: wait',
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 180,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if (!is_string($raw) || $httpCode < 200 || $httpCode >= 300) {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'Replicate request failed'];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'Invalid Replicate response'];
    }

    $output = $decoded['output'] ?? null;
    if (is_string($output) && $output !== '') {
        return ['ok' => true, 'imageUrl' => $output, 'error' => ''];
    }
    if (is_array($output) && isset($output[0]) && is_string($output[0])) {
        return ['ok' => true, 'imageUrl' => $output[0], 'error' => ''];
    }

    return ['ok' => false, 'imageUrl' => '', 'error' => 'Replicate returned no image URL'];
}
