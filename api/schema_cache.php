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
