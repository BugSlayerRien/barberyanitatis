<?php
// AI Status API — configuration health only (never returns secrets).

declare(strict_types=1);

require_once __DIR__ . '/db.php';

function env_str(string $key, string $default = ''): string
{
    $value = getenv($key);
    if ($value === false || $value === '') {
        $value = $_ENV[$key] ?? $_SERVER[$key] ?? $default;
    }

    return trim((string)$value);
}

function key_configured(string ...$keys): bool
{
    foreach ($keys as $key) {
        $value = env_str($key);
        if ($value !== '' && $value !== 'REPLACE_WITH_GEMINI_KEY' && !str_starts_with($value, 'REPLACE_')) {
            return true;
        }
    }

    return false;
}

$geminiModel = env_str('GEMINI_MODEL', 'gemini-2.5-flash-lite');
$geminiImageModel = env_str('GEMINI_IMAGE_MODEL', 'gemini-2.5-flash-image');
$grokImageModel = env_str('GROK_IMAGE_MODEL', 'grok-imagine-image');
$replicateModel = env_str('REPLICATE_MODEL', '');

$chatConfigured = key_configured('GEMINI_API_KEY', 'AI_API_KEY');

$tryonProvider = strtolower(env_str('AI_TRYON_PROVIDER'));
if (!in_array($tryonProvider, ['gemini', 'grok', 'replicate'], true)) {
    if (key_configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY')) {
        $tryonProvider = 'gemini';
    } elseif (key_configured('XAI_API_KEY')) {
        $tryonProvider = 'grok';
    } elseif (key_configured('REPLICATE_API_TOKEN')) {
        $tryonProvider = 'replicate';
    } else {
        $tryonProvider = 'none';
    }
}

$providerConfigured = match ($tryonProvider) {
    'gemini' => key_configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY'),
    'grok' => key_configured('XAI_API_KEY'),
    'replicate' => key_configured('REPLICATE_API_TOKEN'),
    default => false,
};

$imageModel = match ($tryonProvider) {
    'gemini' => $geminiImageModel,
    'grok' => $grokImageModel,
    'replicate' => $replicateModel !== '' ? $replicateModel : 'replicate (configured)',
    default => 'n/a',
};

$styleLimitRaw = env_str('AI_TRYON_STYLE_LIMIT', '3');
$styleLimit = ctype_digit($styleLimitRaw) ? (int)$styleLimitRaw : 3;
$unlimited = in_array(strtolower(env_str('AI_TRYON_UNLIMITED')), ['1', 'true', 'yes', 'on'], true);
$allowFallback = in_array(strtolower(env_str('AI_TRYON_ALLOW_FALLBACK')), ['1', 'true', 'yes', 'on'], true);

$aiServiceUrl = env_str('AI_SERVICE_URL');
$aiServiceOk = null;
$aiServiceHttp = 0;
if ($aiServiceUrl !== '') {
    $probeUrl = rtrim($aiServiceUrl, '/') . '/';
    $ch = curl_init($probeUrl);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 4,
        CURLOPT_FOLLOWLOCATION => true,
    ]);
    curl_exec($ch);
    $aiServiceHttp = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    $aiServiceOk = $aiServiceHttp > 0 && $aiServiceHttp < 500;
}

json_response([
    'ok' => $providerConfigured || $chatConfigured,
    // Backward-compatible "scan" block for the admin overview panel.
    'scan' => [
        'provider' => 'gemini',
        'model' => $geminiModel,
        'enabled' => $chatConfigured,
        'configured' => $chatConfigured,
    ],
    'tryon' => [
        'provider' => $tryonProvider,
        'model' => $imageModel,
        'configured' => $providerConfigured,
        'styleLimit' => $styleLimit,
        'unlimited' => $unlimited,
        'allowFallback' => $allowFallback,
        'availableProviders' => [
            'gemini' => key_configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY'),
            'grok' => key_configured('XAI_API_KEY'),
            'replicate' => key_configured('REPLICATE_API_TOKEN'),
        ],
        'source' => 'AI_TRYON_PROVIDER / server .env (read-only)',
        // Overview expects probe.httpCode — report sidecar reachability when configured.
        'probe' => [
            'ok' => $aiServiceOk === true || ($aiServiceUrl === '' && $providerConfigured),
            'httpCode' => $aiServiceUrl !== '' ? $aiServiceHttp : ($providerConfigured ? 200 : 0),
        ],
    ],
    'chat' => [
        'provider' => 'gemini',
        'model' => $geminiModel,
        'configured' => $chatConfigured,
    ],
    'aiService' => [
        'configured' => $aiServiceUrl !== '',
        'reachable' => $aiServiceOk,
        'httpCode' => $aiServiceHttp,
        'note' => 'Sidecar used for face analysis when running. URL is not exposed.',
    ],
]);
