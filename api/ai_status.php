<?php
// AI Status API (reports configuration health)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

$scanProvider = strtolower(trim((string)(getenv('AI_PROVIDER') ?: ($_ENV['AI_PROVIDER'] ?? $_SERVER['AI_PROVIDER'] ?? 'gemini'))));
$geminiModel = (string)(getenv('GEMINI_MODEL') ?: ($_ENV['GEMINI_MODEL'] ?? $_SERVER['GEMINI_MODEL'] ?? 'gemini-2.5-flash-lite'));
$imagenModel = (string)(getenv('IMAGEN_MODEL') ?: ($_ENV['IMAGEN_MODEL'] ?? $_SERVER['IMAGEN_MODEL'] ?? 'imagen-3'));
$scanKey = trim((string)(getenv('AI_API_KEY') ?: ($_ENV['AI_API_KEY'] ?? $_SERVER['AI_API_KEY'] ?? '')));
$scanEnabled = $scanProvider === 'gemini' && $scanKey !== '' && $scanKey !== 'REPLACE_WITH_GEMINI_KEY';

$tryonProvider = strtolower(trim((string)(getenv('FREE_TRYON_PROVIDER') ?: ($_ENV['FREE_TRYON_PROVIDER'] ?? $_SERVER['FREE_TRYON_PROVIDER'] ?? 'facechain'))));
$instantIdEndpoint = trim((string)(getenv('INSTANTID_ENDPOINT') ?: ($_ENV['INSTANTID_ENDPOINT'] ?? $_SERVER['INSTANTID_ENDPOINT'] ?? '')));
$fooocusEndpoint = trim((string)(getenv('FREE_TRYON_FOOOCUS_ENDPOINT') ?: ($_ENV['FREE_TRYON_FOOOCUS_ENDPOINT'] ?? $_SERVER['FREE_TRYON_FOOOCUS_ENDPOINT'] ?? 'https://fc.aitianhu.space/api/v1/generation/generate-image')));
$facechainEndpoint = trim((string)(getenv('FREE_TRYON_FACECHAIN_ENDPOINT') ?: ($_ENV['FREE_TRYON_FACECHAIN_ENDPOINT'] ?? $_SERVER['FREE_TRYON_FACECHAIN_ENDPOINT'] ?? 'https://facechain-plus.hf.space/api/predict')));
$hfImageModel = trim((string)(getenv('HF_IMAGE_MODEL') ?: ($_ENV['HF_IMAGE_MODEL'] ?? $_SERVER['HF_IMAGE_MODEL'] ?? 'stabilityai/stable-diffusion-xl-base-1.0')));
$hfInferenceEndpoint = $hfImageModel !== '' ? 'https://api-inference.huggingface.co/models/' . rawurlencode($hfImageModel) : '';
$hfToken = trim((string)(getenv('HF_TOKEN') ?: ($_ENV['HF_TOKEN'] ?? $_SERVER['HF_TOKEN'] ?? '')));

function probe_endpoint(string $url): array
{
    if ($url === '') {
        return ['ok' => false, 'httpCode' => 0];
    }
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_TIMEOUT => 10,
    ]);
    curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    return ['ok' => $code >= 200 && $code < 500, 'httpCode' => $code];
}

$tryonConfigured = $tryonProvider === 'instantid'
    ? $instantIdEndpoint !== ''
    : ($tryonProvider === 'fooocus'
        ? $fooocusEndpoint !== ''
        : ($tryonProvider === 'huggingface'
            ? $hfImageModel !== ''
            : $facechainEndpoint !== ''));

$tryonProbe = $tryonProvider === 'instantid'
    ? probe_endpoint($instantIdEndpoint)
    : ($tryonProvider === 'fooocus'
        ? probe_endpoint($fooocusEndpoint)
        : ($tryonProvider === 'huggingface'
            ? probe_endpoint($hfInferenceEndpoint)
            : probe_endpoint($facechainEndpoint)));

json_response([
    'ok' => $scanEnabled || $tryonConfigured,
    'scan' => [
        'provider' => $scanProvider,
        'model' => $geminiModel,
        'enabled' => $scanEnabled,
        'configured' => $scanKey !== '' && $scanKey !== 'REPLACE_WITH_GEMINI_KEY',
    ],
    'tryon' => [
        'provider' => $tryonProvider,
        'model' => $imagenModel,
        'configured' => $tryonConfigured,
        'instantIdEndpoint' => $instantIdEndpoint,
        'fooocusEndpoint' => $fooocusEndpoint,
        'facechainEndpoint' => $facechainEndpoint,
        'hfImageModel' => $hfImageModel,
        'hfInferenceEndpoint' => $hfInferenceEndpoint,
        'hfTokenSet' => $hfToken !== '',
        'probe' => $tryonProbe,
    ],
]);
