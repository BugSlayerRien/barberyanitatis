<?php
// Shared Gemini text generation helper for AI scan features.

declare(strict_types=1);

function ai_gemini_api_key(): string
{
    return trim((string)(
        getenv('AI_API_KEY')
        ?: ($_ENV['AI_API_KEY'] ?? $_SERVER['AI_API_KEY'] ?? '')
        ?: getenv('GEMINI_API_KEY')
        ?: ($_ENV['GEMINI_API_KEY'] ?? $_SERVER['GEMINI_API_KEY'] ?? '')
    ));
}

function ai_gemini_model(): string
{
    return trim((string)(
        getenv('GEMINI_MODEL')
        ?: ($_ENV['GEMINI_MODEL'] ?? $_SERVER['GEMINI_MODEL'] ?? 'gemini-2.5-flash-lite')
    ));
}

function ai_gemini_enabled(): bool
{
    $key = ai_gemini_api_key();
    return $key !== '' && $key !== 'REPLACE_WITH_GEMINI_KEY';
}

function ai_gemini_generate_text(string $prompt, float $temperature = 0.4, int $maxTokens = 2048): ?string
{
    if (!ai_gemini_enabled()) {
        return null;
    }

    $model = ai_gemini_model();
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        . rawurlencode($model)
        . ':generateContent?key=' . urlencode(ai_gemini_api_key());

    $payload = json_encode([
        'contents' => [
            ['parts' => [['text' => $prompt]]],
        ],
        'generationConfig' => [
            'temperature' => $temperature,
            'maxOutputTokens' => $maxTokens,
            'responseMimeType' => 'application/json',
        ],
    ]);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 45,
    ]);
    $result = curl_exec($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($result === false || $status < 200 || $status >= 300) {
        return null;
    }

    $data = json_decode($result, true);
    if (!is_array($data)) {
        return null;
    }

    $parts = $data['candidates'][0]['content']['parts'] ?? [];
    $text = '';
    foreach ($parts as $part) {
        if (isset($part['text'])) {
            $text .= (string)$part['text'];
        }
    }

    return trim($text) !== '' ? trim($text) : null;
}

/** Plain-text replies (chatbot) — no JSON response mode. */
function ai_gemini_generate_plain_text(
    string $prompt,
    float $temperature = 0.65,
    int $maxTokens = 1024,
    ?string &$error = null
): ?string {
    $error = null;
    if (!ai_gemini_enabled()) {
        $error = 'Gemini API key is not configured';
        return null;
    }

    $model = ai_gemini_model();
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/'
        . rawurlencode($model)
        . ':generateContent?key=' . urlencode(ai_gemini_api_key());

    $payload = json_encode([
        'contents' => [
            ['parts' => [['text' => $prompt]]],
        ],
        'generationConfig' => [
            'temperature' => $temperature,
            'maxOutputTokens' => $maxTokens,
        ],
    ]);

    $ch = curl_init($url);
    $opts = [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 45,
    ];
    if (function_exists('api_curl_ssl_options')) {
        $opts += api_curl_ssl_options();
    }
    curl_setopt_array($ch, $opts);
    $result = curl_exec($ch);
    $curlErr = curl_error($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($result === false) {
        $error = $curlErr !== '' ? $curlErr : 'Gemini request failed';
        error_log('Gemini plain_text: ' . $error);
        return null;
    }

    if ($status < 200 || $status >= 300) {
        $error = 'Gemini HTTP ' . $status;
        error_log('Gemini plain_text HTTP ' . $status . ': ' . substr((string)$result, 0, 400));
        return null;
    }

    $data = json_decode($result, true);
    if (!is_array($data)) {
        $error = 'Gemini returned invalid JSON';
        error_log('Gemini plain_text: invalid JSON response');
        return null;
    }

    $parts = $data['candidates'][0]['content']['parts'] ?? [];
    $text = '';
    foreach ($parts as $part) {
        if (isset($part['text'])) {
            $text .= (string)$part['text'];
        }
    }

    $trimmed = trim($text);
    if ($trimmed === '') {
        $error = 'Gemini returned an empty reply';
        error_log('Gemini plain_text: empty candidates text');
        return null;
    }

    return $trimmed;
}

function ai_gemini_parse_json(?string $raw): ?array
{
    if ($raw === null || trim($raw) === '') {
        return null;
    }

    $decoded = json_decode($raw, true);
    if (is_array($decoded)) {
        return $decoded;
    }

    if (preg_match('/\{[\s\S]*\}/', $raw, $matches) === 1) {
        $decoded = json_decode($matches[0], true);
        if (is_array($decoded)) {
            return $decoded;
        }
    }

    return null;
}
