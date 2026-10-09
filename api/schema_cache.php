<?php

declare(strict_types=1);

/**
 * Skip expensive idempotent schema/maintenance work on most requests.
 * Uses a small marker file under a writable cache dir with a TTL (default 1 hour).
 */
function schema_cache_dir(): string
{
    static $resolved = null;
    if ($resolved !== null) {
        return $resolved;
    }

    // Prefer api/storage (writable in Docker docroot). Fall back to system temp.
    $candidates = [
        __DIR__ . DIRECTORY_SEPARATOR . 'storage',
        rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'tatis_schema_cache',
    ];

    foreach ($candidates as $dir) {
        if (!is_dir($dir)) {
            @mkdir($dir, 0755, true);
        }
        if (is_dir($dir) && is_writable($dir)) {
            $resolved = $dir;

            return $resolved;
        }
    }

    // Last resort: memory-only markers still work via schema_cache_should_run statics.
    $resolved = $candidates[0];

    return $resolved;
}

function schema_cache_marker_path(string $key): string
{
    $safe = preg_replace('/[^a-z0-9_-]/i', '_', $key) ?? 'default';

    return schema_cache_dir() . DIRECTORY_SEPARATOR . 'schema_' . $safe . '.ok';
}

function schema_cache_is_fresh(string $key, int $ttlSeconds = 3600): bool
{
    $path = schema_cache_marker_path($key);
    if (!is_file($path)) {
        return false;
    }

    return (time() - (int)filemtime($path)) < $ttlSeconds;
}

function schema_cache_mark_fresh(string $key): void
{
    $path = schema_cache_marker_path($key);
    $dir = dirname($path);
    if (!is_dir($dir) || !is_writable($dir)) {
        return;
    }
    @touch($path);
}

function schema_cache_should_run(string $key, int $ttlSeconds = 3600): bool
{
    static $memory = [];
    if (isset($memory[$key])) {
        return false;
    }
    if (schema_cache_is_fresh($key, $ttlSeconds)) {
        $memory[$key] = true;

        return false;
    }

    return true;
}

function schema_cache_done(string $key): void
{
    static $memory = [];
    $memory[$key] = true;
    schema_cache_mark_fresh($key);
}

/**
 * Small JSON value cache, same directory and TTL idea as the markers above.
 *
 * Added for the haircut catalog: deciding whether a style is usable means
 * checking that three overlay images exist, and under STORAGE_DRIVER=supabase
 * each check is an HTTP round trip. Recomputing that per request would put
 * dozens of calls on the customer's hot path.
 */
function schema_cache_get_json(string $key, int $ttlSeconds): ?array
{
    $path = schema_cache_marker_path($key) . '.json';
    if (!is_file($path)) {
        return null;
    }
    $age = time() - (int)@filemtime($path);
    if ($age > $ttlSeconds) {
        return null;
    }
    $raw = @file_get_contents($path);
    if ($raw === false || $raw === '') {
        return null;
    }
    $decoded = json_decode($raw, true);

    return is_array($decoded) ? $decoded : null;
}

function schema_cache_put_json(string $key, array $value): void
{
    $path = schema_cache_marker_path($key) . '.json';
    @file_put_contents($path, json_encode($value), LOCK_EX);
}

/**
 * Drop a cached entry so the next read recomputes it.
 *
 * The haircut catalog is cached for five minutes, which is right for the
 * customer's hot path and wrong immediately after an admin publishes a style:
 * the style was saved, the portal said so, and the app kept showing the old
 * catalog for up to five minutes. Every write that can change which styles
 * qualify calls this, so publishing takes effect on the next request.
 */
function schema_cache_invalidate(string $key): void
{
    $marker = schema_cache_marker_path($key);
    foreach ([$marker, $marker . '.json'] as $path) {
        if (is_file($path)) {
            @unlink($path);
        }
    }
}
