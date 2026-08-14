<?php

declare(strict_types=1);

/**
 * Object storage adapter for uploaded images.
 *
 * STORAGE_DRIVER=local (default) — write under api_project_root() (XAMPP / Docker disk).
 * STORAGE_DRIVER=supabase — upload to buckets; DB still stores the relative path.
 *   tatis-public: profiles, barbers, overlay PNGs
 *   tatis-scans:  face captures + AI previews (private; service-role reads)
 *
 * Reads try disk first, then Supabase when URL + service role are set (Phase 2).
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

function storage_scans_bucket(): string
{
    $bucket = storage_env('SUPABASE_STORAGE_SCANS_BUCKET', 'tatis-scans');

    return $bucket !== '' ? $bucket : 'tatis-scans';
}

function storage_bucket_for_path(string $relativePath): string
{
    if (str_starts_with($relativePath, 'uploads/face_scans/')) {
        return storage_scans_bucket();
    }

    return storage_public_bucket();
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
    $bucket = storage_bucket_for_path($relativePath);
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

function storage_remote_configured(): bool
{
    return rtrim(storage_env('SUPABASE_URL'), '/') !== ''
        && storage_env('SUPABASE_SERVICE_ROLE_KEY') !== '';
}

function storage_local_full_path(string $relativePath): string
{
    $relativePath = storage_normalize_relative_path($relativePath);

    return api_project_root() . DIRECTORY_SEPARATOR
        . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
}

function storage_supabase_object_url(string $relativePath): string
{
    $base = rtrim(storage_env('SUPABASE_URL'), '/');
    $bucket = storage_bucket_for_path($relativePath);
    $encodedKey = implode('/', array_map('rawurlencode', explode('/', $relativePath)));

    return $base . '/storage/v1/object/' . rawurlencode($bucket) . '/' . $encodedKey;
}

/**
 * Public URL for a key in the public bucket. DB still stores the relative path.
 */
function storage_public_url(string $relativePath): string
{
    $relativePath = storage_normalize_relative_path($relativePath);
    $base = rtrim(storage_env('SUPABASE_URL'), '/');
    if ($base === '') {
        return '';
    }
    if (storage_bucket_for_path($relativePath) !== storage_public_bucket()) {
        return '';
    }
    $bucket = storage_public_bucket();
    $encodedKey = implode('/', array_map('rawurlencode', explode('/', $relativePath)));

    return $base . '/storage/v1/object/public/' . rawurlencode($bucket) . '/' . $encodedKey;
}

function storage_supabase_request(string $relativePath, bool $headOnly): array
{
    $key = storage_env('SUPABASE_SERVICE_ROLE_KEY');
    $url = storage_supabase_object_url($relativePath);
    $ch = curl_init($url);
    $opts = [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 45,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $key,
            'apikey: ' . $key,
        ],
    ] + api_curl_ssl_options();
    if ($headOnly) {
        $opts[CURLOPT_NOBODY] = true;
        $opts[CURLOPT_CUSTOMREQUEST] = 'HEAD';
    }
    curl_setopt_array($ch, $opts);
    $raw = curl_exec($ch);
    $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    return [
        'ok' => is_string($raw) || $headOnly,
        'code' => $code,
        'body' => is_string($raw) ? $raw : '',
        'error' => $err,
    ];
}

function storage_exists_local(string $relativePath): bool
{
    $full = storage_local_full_path($relativePath);

    return is_file($full) && filesize($full) > 0;
}

function storage_exists_supabase(string $relativePath): bool
{
    $head = storage_supabase_request($relativePath, true);
    if ($head['code'] >= 200 && $head['code'] < 300) {
        return true;
    }
    // Some Storage gateways do not implement HEAD; fall back to a GET.
    if (in_array($head['code'], [0, 404, 405, 501], true) || $head['code'] >= 500) {
        $get = storage_supabase_request($relativePath, false);

        return $get['code'] >= 200 && $get['code'] < 300 && $get['body'] !== '';
    }

    return false;
}

function storage_get_supabase(string $relativePath): ?string
{
    $get = storage_supabase_request($relativePath, false);
    if ($get['code'] < 200 || $get['code'] >= 300 || $get['body'] === '') {
        return null;
    }

    return $get['body'];
}

/**
 * True if the object exists on disk or (when configured) in the public bucket.
 */
function storage_exists(string $relativePath): bool
{
    $relativePath = trim(str_replace('\\', '/', $relativePath));
    $relativePath = ltrim($relativePath, '/');
    if ($relativePath === '') {
        return false;
    }

    try {
        $relativePath = storage_normalize_relative_path($relativePath);
    } catch (InvalidArgumentException $e) {
        return false;
    }

    if (storage_exists_local($relativePath)) {
        return true;
    }

    return storage_remote_configured() && storage_exists_supabase($relativePath);
}

/**
 * Read object bytes: disk first, then Supabase when credentials are set.
 */
function storage_get_bytes(string $relativePath): ?string
{
    $relativePath = trim(str_replace('\\', '/', $relativePath));
    $relativePath = ltrim($relativePath, '/');
    if ($relativePath === '') {
        return null;
    }

    try {
        $relativePath = storage_normalize_relative_path($relativePath);
    } catch (InvalidArgumentException $e) {
        return null;
    }

    if (storage_exists_local($relativePath)) {
        $bytes = file_get_contents(storage_local_full_path($relativePath));

        return $bytes === false || $bytes === '' ? null : $bytes;
    }

    if (!storage_remote_configured()) {
        return null;
    }

    return storage_get_supabase($relativePath);
}

/**
 * Absolute path for tools that must open a local file (sidecar / Replicate).
 * Downloads to a temp file when the object is only in Supabase.
 */
function storage_ensure_readable_file(string $relativePath): string
{
    $relativePath = storage_normalize_relative_path($relativePath);
    $full = storage_local_full_path($relativePath);
    if (is_file($full) && filesize($full) > 0) {
        return $full;
    }

    $bytes = storage_remote_configured() ? storage_get_supabase($relativePath) : null;
    if ($bytes === null || $bytes === '') {
        return $full;
    }

    $tmp = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR
        . 'tatis_storage_' . hash('sha256', $relativePath) . '_' . basename($relativePath);
    if (file_put_contents($tmp, $bytes) === false) {
        return $full;
    }

    return $tmp;
}

function storage_mime_from_path(string $relativePath): string
{
    $ext = strtolower(pathinfo($relativePath, PATHINFO_EXTENSION));
    $map = [
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
    ];

    return $map[$ext] ?? 'application/octet-stream';
}
