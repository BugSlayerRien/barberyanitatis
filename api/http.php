<?php

declare(strict_types=1);

function api_curl_insecure_ssl(): bool
{
    $raw = trim((string)(getenv('API_INSECURE_SSL') ?: ($_ENV['API_INSECURE_SSL'] ?? '')));
    return in_array(strtolower($raw), ['1', 'true', 'yes'], true);
}

/**
 * Extra cURL options for HTTPS on Windows dev machines with broken CA stores.
 * Set API_INSECURE_SSL=true in .env (local only — never in production).
 *
 * @return array<int, mixed>
 */
function api_curl_ssl_options(): array
{
    if (!api_curl_insecure_ssl()) {
        return [];
    }

    return [
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => 0,
    ];
}

/**
 * Project root for uploads/storage.
 * Local monorepo: parent of api/. Docker flat docroot: the api directory itself.
 */
function api_project_root(): string
{
    static $root = null;
    if ($root !== null) {
        return $root;
    }

    $here = __DIR__;
    $parent = dirname($here);

    if (
        is_dir($parent . DIRECTORY_SEPARATOR . 'web-admin')
        || is_dir($parent . DIRECTORY_SEPARATOR . 'mobile-app')
        || is_dir($parent . DIRECTORY_SEPARATOR . 'uploads')
    ) {
        $root = $parent;

        return $root;
    }

    $root = $here;

    return $root;
}

function load_project_env(): void
{
    static $loaded = false;
    if ($loaded) {
        return;
    }
    $loaded = true;

    // Local: repo-root/.env. Docker entrypoint: /var/www/.env (parent of docroot).
    $candidates = [
        dirname(__DIR__) . DIRECTORY_SEPARATOR . '.env',
        api_project_root() . DIRECTORY_SEPARATOR . '.env',
        __DIR__ . DIRECTORY_SEPARATOR . '.env',
    ];
    $envFile = null;
    foreach ($candidates as $candidate) {
        if (is_readable($candidate)) {
            $envFile = $candidate;
            break;
        }
    }
    if ($envFile === null) {
        return;
    }

    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        return;
    }

    foreach ($lines as $line) {
        $trimmed = trim($line);
        if ($trimmed === '' || str_starts_with($trimmed, '#') || !str_contains($line, '=')) {
            continue;
        }

        [$key, $value] = explode('=', $line, 2);
        $key = trim($key);
        $value = trim($value);
        $value = trim($value, "'\"");

        if ($key !== '') {
            // Project .env must win over stale Apache/Windows process env
            // (e.g. an old GEMINI_MODEL left on the service after .env was updated).
            putenv($key . '=' . $value);
            $_ENV[$key] = $value;
            $_SERVER[$key] = $value;
        }
    }
}

function apply_api_cors_headers(): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, X-Portal-Token, X-Supabase-Access-Token, X-Authorization');
    header('Access-Control-Max-Age: 86400');
}

function require_method(string ...$methods): void
{
    load_project_env();
    apply_api_cors_headers();

    $method = strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET'));
    if ($method === 'OPTIONS') {
        http_response_code(204);
        exit;
    }

    $allowed = array_map(static fn(string $item): string => strtoupper($item), $methods);
    if (!in_array($method, $allowed, true)) {
        json_response(['error' => 'Method not allowed'], 405);
    }
}

function get_json_input(): array
{
    $raw = file_get_contents('php://input');
    if ($raw === false || trim($raw) === '') {
        return [];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        json_response(['error' => 'Invalid JSON body'], 400);
    }

    return $decoded;
}

function json_response(array $payload, int $status = 200): void
{
    if (!headers_sent()) {
        apply_api_cors_headers();
        header('Content-Type: application/json; charset=utf-8');
        http_response_code($status);
    }

    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
