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

function storage_unquote(string $value): string
{
    $value = trim($value);
    $value = stripslashes($value);
    $value = trim($value);
    $value = trim($value, "\"'");
    $value = preg_replace('/^[\x{201C}\x{201D}\x{2018}\x{2019}]+/u', '', $value) ?? $value;
    $value = preg_replace('/[\x{201C}\x{201D}\x{2018}\x{2019}]+$/u', '', $value) ?? $value;

    return trim($value);
}

function storage_env(string $key, string $default = ''): string
{
    load_project_env();

    if (array_key_exists($key, $_ENV) && is_scalar($_ENV[$key])) {
        $fromEnv = storage_unquote((string)$_ENV[$key]);
        if ($fromEnv !== '') {
            return $fromEnv;
        }
    }
    if (array_key_exists($key, $_SERVER) && is_scalar($_SERVER[$key])) {
        $fromServer = storage_unquote((string)$_SERVER[$key]);
        if ($fromServer !== '') {
            return $fromServer;
        }
    }

    $fromGetenv = getenv($key);
    if ($fromGetenv !== false && storage_unquote((string)$fromGetenv) !== '') {
        return storage_unquote((string)$fromGetenv);
    }

    return storage_unquote($default);
}

/**
 * Origin for Storage REST (https://<ref>.supabase.co).
 * Render/dotenv often leave wrapping quotes, which libcurl rejects as:
 * "URL rejected: Port number was not a decimal number between 0 and 65535".
 * Also recovers a project URL if DB_URL was pasted into SUPABASE_URL.
 */
function storage_normalize_supabase_url(string $raw): string
{
    $raw = storage_unquote($raw);
    if ($raw === '') {
        return '';
    }

    $raw = preg_replace('#^(https://)+#i', 'https://', $raw) ?? $raw;
    $raw = preg_replace('#^(http://)+#i', 'http://', $raw) ?? $raw;
    if (str_starts_with(strtolower($raw), 'jdbc:')) {
        $raw = substr($raw, 5);
    }

    $parts = parse_url($raw);
    if ($parts === false) {
        throw new RuntimeException('SUPABASE_URL is malformed');
    }

    $scheme = strtolower((string)($parts['scheme'] ?? ''));
    $host = strtolower((string)($parts['host'] ?? ''));
    $user = (string)($parts['user'] ?? '');

    // https://https://ref.supabase.co → host "https", path "//ref.supabase.co"
    if ($host === 'http' || $host === 'https') {
        $nested = preg_replace('#^/+#', '', str_replace('\\', '/', (string)($parts['path'] ?? '')));
        if ($nested !== '') {
            return storage_normalize_supabase_url('https://' . $nested);
        }
    }

    if (
        in_array($scheme, ['postgres', 'postgresql'], true)
        || str_contains($host, 'pooler.supabase.com')
        || str_contains($host, 'pooler.supabase.co')
    ) {
        $ref = storage_project_ref_from_db_parts($user, $host);
        if ($ref === '') {
            throw new RuntimeException(
                'SUPABASE_URL is a database connection string. Set it to https://<project-ref>.supabase.co, not DB_URL.'
            );
        }

        return 'https://' . $ref . '.supabase.co';
    }

    if (($scheme === 'http' || $scheme === 'https') && $host !== '') {
        if (preg_match('/^db\.([a-z0-9]+)\.supabase\.co$/', $host, $matches) === 1) {
            return 'https://' . $matches[1] . '.supabase.co';
        }
        $origin = ($scheme === 'http' ? 'http' : 'https') . '://' . $host;
        $port = $parts['port'] ?? null;
        if (is_int($port) && $port > 0 && $port <= 65535 && !in_array($port, [80, 443, 5432, 6543], true)) {
            $origin .= ':' . $port;
        }

        return $origin;
    }

    throw new RuntimeException(
        'SUPABASE_URL must be the project URL https://<project-ref>.supabase.co (no extra quotes).'
    );
}

function storage_project_ref_from_db_parts(string $user, string $host): string
{
    if (preg_match('/^postgres\.([a-z0-9]+)$/i', $user, $matches) === 1) {
        return strtolower($matches[1]);
    }
    if (preg_match('/^db\.([a-z0-9]+)\.supabase\.co$/i', $host, $matches) === 1) {
        return strtolower($matches[1]);
    }

    return '';
}

function storage_supabase_base_url(): string
{
    return storage_normalize_supabase_url(storage_env('SUPABASE_URL'));
}

function storage_service_role_key(): string
{
    $key = storage_env('SUPABASE_SERVICE_ROLE_KEY');
    if ($key !== '') {
        return $key;
    }

    return storage_env('SUPABASE_SERVICE_ROLE');
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
    $base = storage_supabase_base_url();
    $key = storage_service_role_key();
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
    try {
        return storage_supabase_base_url() !== ''
            && storage_service_role_key() !== '';
    } catch (RuntimeException $e) {
        return false;
    }
}

function storage_local_full_path(string $relativePath): string
{
    $relativePath = storage_normalize_relative_path($relativePath);

    return api_project_root() . DIRECTORY_SEPARATOR
        . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
}

function storage_supabase_object_url(string $relativePath): string
{
    $base = storage_supabase_base_url();
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
    try {
        $base = storage_supabase_base_url();
    } catch (RuntimeException $e) {
        return '';
    }
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
    $key = storage_service_role_key();
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

/**
 * Delete an object from wherever it lives. Used by the data-retention sweep
 * (data_retention.php); returns true when the object is gone afterwards,
 * including when it was already absent.
 */
function storage_delete(string $relativePath): bool
{
    $relativePath = ltrim(trim(str_replace(chr(92), '/', $relativePath)), '/');
    if ($relativePath === '') {
        return false;
    }

    try {
        $relativePath = storage_normalize_relative_path($relativePath);
    } catch (InvalidArgumentException $e) {
        // Refuses anything that escapes the storage root.
        return false;
    }

    $ok = true;

    $local = storage_local_full_path($relativePath);
    if (is_file($local)) {
        $ok = @unlink($local);
    }

    if (storage_remote_configured()) {
        $key = storage_service_role_key();
        $ch = curl_init(storage_supabase_object_url($relativePath));
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 45,
            CURLOPT_CUSTOMREQUEST => 'DELETE',
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $key,
                'apikey: ' . $key,
            ],
        ] + api_curl_ssl_options());
        curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        // 404 is fine: the point is that it is not there any more.
        if (!(($code >= 200 && $code < 300) || $code === 404)) {
            $ok = false;
        }
    }

    return $ok;
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
