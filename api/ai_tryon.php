<?php
// AI Try-on API (library-based; returns selected haircut image)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';
$prompt = trim((string)($input['prompt'] ?? ''));
$imageUrl = trim((string)($input['imageUrl'] ?? ''));
$negativePrompt = trim((string)($input['negativePrompt'] ?? ''));
$variantID = (int)($input['variantID'] ?? 0);

$isGenerate = $action === 'generateImage' || ($prompt !== '' && $variantID <= 0);
$isInstantId = $action === 'instantId';

if (!$isGenerate && !$isInstantId && $variantID <= 0) {
    json_response(['error' => 'Invalid variantID'], 422);
}

function to_data_url(string $pathOrUrl): array
{
    if ($pathOrUrl === '') {
        return ['', ''];
    }

    if (strpos($pathOrUrl, 'data:') === 0) {
        return [$pathOrUrl, ''];
    }

    $data = null;
    $mime = '';

    if (strpos($pathOrUrl, 'http://') === 0 || strpos($pathOrUrl, 'https://') === 0) {
        $ch = curl_init($pathOrUrl);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_TIMEOUT => 30,
        ]);
        $data = curl_exec($ch);
        $contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
        curl_close($ch);
        if (is_string($contentType)) {
            $mime = trim(explode(';', $contentType)[0]);
        }
    } else {
        $root = dirname(__DIR__);
        $relative = ltrim($pathOrUrl, '/');
        $fullPath = $root . '/' . $relative;
        if (is_file($fullPath)) {
            $data = file_get_contents($fullPath);
            $mime = function_exists('mime_content_type') ? mime_content_type($fullPath) : '';
        }
    }

    if (!is_string($data) || $data === '') {
        return ['', 'Failed to load image'];
    }

    if ($mime === '') {
        $mime = 'image/jpeg';
    }

    $base64 = base64_encode($data);
    return ['data:' . $mime . ';base64,' . $base64, ''];
}

function replicate_post(string $token, string $endpoint, array $payload): array
{
    $ch = curl_init($endpoint);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Token ' . $token,
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_TIMEOUT => 60,
    ]);
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    return [$code, $raw, $err];
}

function replicate_get(string $token, string $endpoint): array
{
    $ch = curl_init($endpoint);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Token ' . $token,
        ],
        CURLOPT_TIMEOUT => 60,
    ]);
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    return [$code, $raw, $err];
}

try {
    $pdo = get_db_connection();

    if ($isInstantId) {
        if ($prompt === '') {
            json_response(['error' => 'Prompt is required'], 422);
        }
        if ($imageUrl === '') {
            json_response(['error' => 'imageUrl is required'], 422);
        }

        $replicateToken = trim((string)(getenv('REPLICATE_API_TOKEN') ?: ($_ENV['REPLICATE_API_TOKEN'] ?? $_SERVER['REPLICATE_API_TOKEN'] ?? '')));
        if ($replicateToken === '') {
            json_response(['error' => 'REPLICATE_API_TOKEN not configured'], 500);
        }

        $version = '2e4785a4d80dadf580077b2244c8d7c05d8e3faac04a04c02d8e099dd2876789';
        $negative = $negativePrompt !== '' ? $negativePrompt : 'cartoon, anime, blurry, low quality';

        [$imageDataUrl, $imageErr] = to_data_url($imageUrl);
        if ($imageDataUrl === '') {
            json_response(['error' => 'Failed to read image for try-on', 'details' => $imageErr], 422);
        }

        $payload = [
            'version' => $version,
            'input' => [
                'image' => $imageDataUrl,
                'prompt' => $prompt,
                'negative_prompt' => $negative,
                'num_steps' => 30,
                'guidance_scale' => 7.5,
            ],
        ];

        [$code, $raw, $err] = replicate_post($replicateToken, 'https://api.replicate.com/v1/predictions', $payload);
        if ($raw === false || $code < 200 || $code >= 300) {
            json_response(['error' => 'Replicate request failed', 'details' => $err !== '' ? $err : $raw], 502);
        }

        $response = json_decode((string)$raw, true);
        $predictionId = $response['id'] ?? '';
        if ($predictionId === '') {
            json_response(['error' => 'Replicate did not return a prediction id'], 502);
        }

        $status = $response['status'] ?? 'starting';
        $outputUrl = '';
        $tries = 0;
        while ($tries < 30 && $status !== 'succeeded' && $status !== 'failed' && $status !== 'canceled') {
            sleep(2);
            [$gCode, $gRaw, $gErr] = replicate_get($replicateToken, 'https://api.replicate.com/v1/predictions/' . $predictionId);
            if ($gRaw === false || $gCode < 200 || $gCode >= 300) {
                json_response(['error' => 'Replicate polling failed', 'details' => $gErr !== '' ? $gErr : $gRaw], 502);
            }
            $poll = json_decode((string)$gRaw, true);
            $status = $poll['status'] ?? $status;
            if ($status === 'succeeded') {
                $output = $poll['output'] ?? [];
                if (is_array($output) && isset($output[0])) {
                    $outputUrl = (string)$output[0];
                }
                break;
            }
            if ($status === 'failed' || $status === 'canceled') {
                json_response(['error' => 'Replicate generation failed', 'details' => $poll['error'] ?? $status], 502);
            }
            $tries++;
        }

        if ($outputUrl === '') {
            json_response(['error' => 'Replicate did not return an output image'], 502);
        }

        [$outputDataUrl, $outputErr] = to_data_url($outputUrl);
        if ($outputDataUrl === '') {
            json_response(['error' => 'Failed to download generated image', 'details' => $outputErr], 502);
        }

        $base64Pos = strpos($outputDataUrl, 'base64,');
        $imageBase64 = $base64Pos !== false ? substr($outputDataUrl, $base64Pos + 7) : '';

        json_response([
            'message' => 'Image generated',
            'imageBase64' => $imageBase64,
            'imageUrl' => $outputUrl,
            'provider' => 'replicate-instantid',
        ]);
    }

    if ($isGenerate) {
        if ($prompt === '') {
            json_response(['error' => 'Prompt is required'], 422);
        }

        $apiKey = trim((string)(getenv('AI_API_KEY') ?: ($_ENV['AI_API_KEY'] ?? $_SERVER['AI_API_KEY'] ?? '')));
        if ($apiKey === '') {
            json_response(['error' => 'AI_API_KEY not configured'], 500);
        }

        $model = trim((string)(getenv('IMAGEN_MODEL') ?: ($_ENV['IMAGEN_MODEL'] ?? $_SERVER['IMAGEN_MODEL'] ?? 'imagen-3')));
        if ($model === '') {
            $model = 'imagen-3';
        }

        $payload = [
            'prompt' => ['text' => $prompt],
            'imageGenerationConfig' => [
                'numberOfImages' => 1,
                'aspectRatio' => '1:1',
            ],
        ];

        $url = 'https://generativelanguage.googleapis.com/v1beta/models/' . rawurlencode($model) . ':generateImages';
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => [
                'Content-Type: application/json',
                'x-goog-api-key: ' . $apiKey,
            ],
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_TIMEOUT => 60,
        ]);
        $raw = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
            json_response([
                'error' => 'Image generation failed',
                'details' => $curlError !== '' ? $curlError : $raw,
            ], 502);
        }

        $data = json_decode((string)$raw, true);
        $imageBase64 = $data['generatedImages'][0]['bytesBase64Encoded'] ?? '';
        if ($imageBase64 === '') {
            json_response(['error' => 'No image returned from model'], 502);
        }

        json_response([
            'message' => 'Image generated',
            'imageBase64' => $imageBase64,
            'model' => $model,
        ]);
    }

    $stmt = $pdo->prepare(
        'SELECT hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes,
                hs.style_name, hs.style_code
         FROM hairstyle_variants hv
         JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
         WHERE hv.variant_id = :variant_id AND hs.is_active = 1'
    );
    $stmt->execute([':variant_id' => $variantID]);
    $variant = $stmt->fetch();

    if (!$variant) {
        json_response([
            'message' => 'Variant not found.',
            'variant' => null,
        ], 404);
    }

    json_response([
        'message' => 'Variant found',
        'variant' => $variant,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
