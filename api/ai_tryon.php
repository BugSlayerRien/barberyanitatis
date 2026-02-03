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

function decode_data_url(string $dataUrl): array
{
    if (strpos($dataUrl, 'data:') !== 0) {
        return ['', ''];
    }
    if (!preg_match('/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/', $dataUrl, $matches)) {
        return ['', ''];
    }
    return [$matches[2], $matches[1]];
}

function store_generated_image(string $base64, string $mime): array
{
    $uploadDir = __DIR__ . '/../uploads/generated';
    if (!is_dir($uploadDir)) {
        mkdir($uploadDir, 0775, true);
    }
    $ext = $mime === 'image/png' ? 'png' : 'jpg';
    $filename = 'tryon_' . date('Ymd_His') . '_' . bin2hex(random_bytes(4)) . '.' . $ext;
    $targetPath = $uploadDir . '/' . $filename;
    $decoded = base64_decode($base64, true);
    if ($decoded === false || $decoded === '') {
        return ['', ''];
    }
    if (file_put_contents($targetPath, $decoded) === false) {
        return ['', ''];
    }
    return ['/uploads/generated/' . $filename, $filename];
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

        $provider = strtolower(trim((string)(getenv('FREE_TRYON_PROVIDER') ?: ($_ENV['FREE_TRYON_PROVIDER'] ?? $_SERVER['FREE_TRYON_PROVIDER'] ?? 'facechain'))));
        $negative = $negativePrompt !== '' ? $negativePrompt : 'cartoon, anime, blurry, low quality';

        [$imageDataUrl, $imageErr] = to_data_url($imageUrl);
        if ($imageDataUrl === '') {
            json_response(['error' => 'Failed to read image for try-on', 'details' => $imageErr], 422);
        }

        $httpCode = 0;
        $raw = '';
        if ($provider === 'instantid') {
            $endpoint = trim((string)(getenv('INSTANTID_ENDPOINT') ?: ($_ENV['INSTANTID_ENDPOINT'] ?? $_SERVER['INSTANTID_ENDPOINT'] ?? '')));
            if ($endpoint === '') {
                json_response([
                    'error' => 'InstantID endpoint not configured',
                    'hint' => 'Set INSTANTID_ENDPOINT to your InstantID service URL.',
                ], 500);
            }

            $payload = [
                'image' => $imageDataUrl,
                'prompt' => $prompt,
                'negative_prompt' => $negative,
            ];

            [$code, $raw, $err] = replicate_post('', $endpoint, $payload);
            if ($raw === false || $code < 200 || $code >= 300) {
                json_response([
                    'error' => 'InstantID request failed',
                    'details' => $err !== '' ? $err : $raw,
                    'hint' => 'Ensure your InstantID service is running and reachable.',
                ], 502);
            }

            $response = json_decode((string)$raw, true);
            $imageBase64 = $response['imageBase64'] ?? '';
            $imageUrl = $response['imageUrl'] ?? '';
            $dataUrl = $response['dataUrl'] ?? '';
            if ($imageBase64 === '' && $imageUrl === '' && $dataUrl === '') {
                json_response(['error' => 'InstantID did not return an image', 'details' => $raw], 502);
            }
            if ($imageBase64 === '' && $dataUrl !== '') {
                [$decoded, $mime] = decode_data_url((string)$dataUrl);
                if ($decoded !== '') {
                    $imageBase64 = $decoded;
                }
            }
            if ($imageBase64 !== '') {
                [$publicUrl] = store_generated_image($imageBase64, 'image/png');
                json_response([
                    'message' => 'Image generated',
                    'imageBase64' => $imageBase64,
                    'imageUrl' => $publicUrl,
                    'provider' => 'instantid',
                ]);
            }
            json_response([
                'message' => 'Image generated',
                'imageUrl' => $imageUrl,
                'provider' => 'instantid',
            ]);
        }

        if ($provider === 'fooocus') {
            $endpoint = trim((string)(getenv('FREE_TRYON_FOOOCUS_ENDPOINT') ?: ($_ENV['FREE_TRYON_FOOOCUS_ENDPOINT'] ?? $_SERVER['FREE_TRYON_FOOOCUS_ENDPOINT'] ?? 'https://fc.aitianhu.space/api/v1/generation/generate-image')));
            $payload = [
                'prompt' => $prompt,
                'negative_prompt' => $negative,
                'image_prompts' => [
                    [
                        'image' => $imageDataUrl,
                        'weight' => 1.0,
                        'type' => 'face',
                    ],
                ],
                'performance' => 'Speed',
                'aspect_ratio' => '1:1',
                'sharpness' => 2,
                'seed' => random_int(1, 999999999),
            ];
            $ch = curl_init($endpoint);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_POST => true,
                CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
                CURLOPT_POSTFIELDS => json_encode($payload),
                CURLOPT_TIMEOUT => 90,
            ]);
            $raw = curl_exec($ch);
            $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlError = curl_error($ch);
            curl_close($ch);
            if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
                // Fall back to facechain if Fooocus is unavailable
                $provider = 'facechain';
            } else {
                $response = json_decode((string)$raw, true);
                $imageBase64 = $response['images'][0] ?? '';
                if ($imageBase64 === '') {
                    $provider = 'facechain';
                } else {
                    [$publicUrl] = store_generated_image($imageBase64, 'image/png');
                    json_response([
                        'message' => 'Image generated',
                        'imageBase64' => $imageBase64,
                        'imageUrl' => $publicUrl,
                        'provider' => 'fooocus-free',
                    ]);
                }
            }
        }

        $endpoint = trim((string)(getenv('FREE_TRYON_FACECHAIN_ENDPOINT') ?: ($_ENV['FREE_TRYON_FACECHAIN_ENDPOINT'] ?? $_SERVER['FREE_TRYON_FACECHAIN_ENDPOINT'] ?? 'https://facechain-plus.hf.space/api/predict')));
        $payload = [
            'data' => [
                $imageDataUrl,
                $prompt . ', detailed face, sharp features',
                $negative,
                20,
                7,
            ],
        ];
        $headers = ['Content-Type: application/json'];
        $hfToken = trim((string)(getenv('HF_TOKEN') ?: ($_ENV['HF_TOKEN'] ?? $_SERVER['HF_TOKEN'] ?? '')));
        if ($hfToken !== '') {
            $headers[] = 'Authorization: Bearer ' . $hfToken;
        }
        $ch = curl_init($endpoint);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_POSTFIELDS => json_encode($payload),
            CURLOPT_TIMEOUT => 90,
        ]);
        $raw = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);
        if ($raw === false || $httpCode < 200 || $httpCode >= 300) {
            json_response([
                'error' => 'FaceChain request failed',
                'details' => $curlError !== '' ? $curlError : $raw,
                'hint' => 'Check FREE_TRYON_PROVIDER/FREE_TRYON_FACECHAIN_ENDPOINT and HF_TOKEN if required.',
            ], 502);
        }
        $response = json_decode((string)$raw, true);
        $dataUrl = $response['data'][0] ?? '';
        if (!is_string($dataUrl) || $dataUrl === '') {
            json_response(['error' => 'FaceChain did not return an image', 'details' => $raw], 502);
        }
        [$imageBase64, $mime] = decode_data_url($dataUrl);
        if ($imageBase64 === '') {
            json_response(['error' => 'FaceChain returned invalid image data'], 502);
        }
        [$publicUrl] = store_generated_image($imageBase64, $mime !== '' ? $mime : 'image/png');
        json_response([
            'message' => 'Image generated',
            'imageBase64' => $imageBase64,
            'imageUrl' => $publicUrl,
            'provider' => 'facechain-free',
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
