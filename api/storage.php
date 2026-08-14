<?php

declare(strict_types=1);

/**
 * Object storage adapter for uploaded images.
 *
 * STORAGE_DRIVER=local (default) — write under api_project_root() (XAMPP / Docker disk).
 * STORAGE_DRIVER=supabase — upload to a public bucket; DB still stores the relative path.
 *
 * Service role key is server-only (Render / .env). Never expose it to Flutter.
 */

require_once __DIR__ . '/http.php';

function storage_env(string $key, string $default = ''): string
{
    load_project_env();

    if (array_key_exists($key, $_ENV) && is_scalar($_ENV[$key])) {
        $fromEnv = trim((string)$_ENV[$key]);
        if ($fromEnv !== '') {
            return $fromEnv;
        }
    }
    if (array_key_exists($key, $_SERVER) && is_scalar($_SERVER[$key])) {
        $fromServer = trim((string)$_SERVER[$key]);
        if ($fromServer !== '') {
            return $fromServer;
        }
    }

    $fromGetenv = getenv($key);
    if ($fromGetenv !== false && trim((string)$fromGetenv) !== '') {
        return trim((string)$fromGetenv);
    }

    return $default;
}

function storage_driver(): string
{
    $raw = strtolower(storage_env('STORAGE_DRIVER', 'local'));

    return $raw === 'supabase' ? 'supabase' : 'local';
}

function storage_public_bucket(): string
{
    $bucket = storage_env('SUPABASE_STORAGE_PUBLIC_BUCKET', 'tatis-public');

    return $bucket !== '' ? $bucket : 'tatis-public';
}

/**
 * Normalize a relative object key (DB value). Rejects traversal and absolute paths.
 */
function storage_normalize_relative_path(string $relativePath): string
{
    $path = str_replace('\\', '/', trim($relativePath));
    $path = ltrim($path, '/');
    if ($path === '' || str_contains($path, '..')) {
        throw new InvalidArgumentException('Invalid storage path');
    }
    if (!preg_match('#^[a-zA-Z0-9][a-zA-Z0-9._/-]*$#', $path)) {
        throw new InvalidArgumentException('Invalid storage path');
    }

    return $path;
}

/**
 * Write bytes and return the relative path stored in the database.
 */
function storage_put_bytes(string $relativePath, string $bytes, string $mime = 'application/octet-stream'): string
{
    if ($bytes === '') {
        throw new RuntimeException('Cannot store empty file');
    }

    $relativePath = storage_normalize_relative_path($relativePath);
    if (storage_driver() === 'supabase') {
        storage_put_supabase($relativePath, $bytes, $mime);
    } else {
        storage_put_local($relativePath, $bytes);
    }

    return $relativePath;
}

function storage_put_local(string $relativePath, string $bytes): void
{
    $fullPath = api_project_root() . DIRECTORY_SEPARATOR
        . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
    $dir = dirname($fullPath);
    if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
        throw new RuntimeException('Could not create upload directory');
    }
    if (file_put_contents($fullPath, $bytes) === false) {
        throw new RuntimeException('Could not save uploaded file');
    }
}

function storage_put_supabase(string $relativePath, string $bytes, string $mime): void
{
    $base = rtrim(storage_env('SUPABASE_URL'), '/');
    $key = storage_env('SUPABASE_SERVICE_ROLE_KEY');
    $bucket = storage_public_bucket();
    if ($base === '' || $key === '') {
        throw new RuntimeException('Supabase storage is not configured (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)');
    }

    $encodedKey = implode('/', array_map('rawurlencode', explode('/', $relativePath)));
    $url = $base . '/storage/v1/object/' . rawurlencode($bucket) . '/' . $encodedKey;

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => 'POST',
        CURLOPT_POSTFIELDS => $bytes,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 45,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $key,
            'apikey: ' . $key,
            'Content-Type: ' . $mime,
            'x-upsert: true',
        ],
    ] + api_curl_ssl_options());
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw) || $code < 200 || $code >= 300) {
        throw new RuntimeException(
            'Supabase storage upload failed (HTTP ' . $code . ')'
            . ($err !== '' ? ': ' . $err : '')
        );
    }
}
