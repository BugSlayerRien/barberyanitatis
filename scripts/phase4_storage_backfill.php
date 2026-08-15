<?php
/**
 * Phase 4 — one-time backfill of existing image files into Supabase Storage.
 *
 * Does NOT change STORAGE_DRIVER. Does NOT update database path strings.
 * Object keys stay identical to today's relative paths (uploads/..., assets/images/overlays/...).
 *
 * Dry-run (default):
 *   php scripts/migrate_uploads_to_supabase.php
 *
 * Upload:
 *   php scripts/migrate_uploads_to_supabase.php --apply
 *
 * Optional: --limit=20
 *
 * Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env (already used for Auth).
 * Create buckets tatis-public and tatis-scans in the Supabase dashboard first.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "Run this script from the command line only.\n");
    exit(1);
}

require_once dirname(__DIR__) . '/api/db.php';
require_once dirname(__DIR__) . '/api/storage.php';

$opts = getopt('', ['apply', 'dry-run', 'limit::', 'help']);
if (isset($opts['help'])) {
    echo file_get_contents(__FILE__, false, null, 0, 900);
    exit(0);
}

$apply = isset($opts['apply']);
$limit = isset($opts['limit']) ? max(0, (int)$opts['limit']) : 0;

function backfill_table_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare(
        "SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = :t LIMIT 1"
    );
    $stmt->execute([':t' => $table]);

    return (bool)$stmt->fetchColumn();
}

function backfill_column_exists(PDO $pdo, string $table, string $column): bool
{
    $stmt = $pdo->prepare(
        "SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = :t AND column_name = :c LIMIT 1"
    );
    $stmt->execute([':t' => $table, ':c' => $column]);

    return (bool)$stmt->fetchColumn();
}

function backfill_normalize_key(string $raw): string
{
    $path = str_replace('\\', '/', trim($raw));
    if ($path === '' || strcasecmp($path, 'null') === 0) {
        return '';
    }
    if (str_starts_with($path, 'http://') || str_starts_with($path, 'https://') || str_starts_with($path, 'data:')) {
        return '';
    }
    $path = ltrim($path, '/');
    try {
        return storage_normalize_relative_path($path);
    } catch (InvalidArgumentException $e) {
        return '';
    }
}

function backfill_local_file(string $relativePath): ?string
{
    $root = api_project_root();
    $candidates = [];
    if (str_starts_with($relativePath, 'assets/images/overlays/')) {
        $candidates[] = $root . DIRECTORY_SEPARATOR . 'mobile-app' . DIRECTORY_SEPARATOR
            . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
    }
    $candidates[] = storage_local_full_path($relativePath);
    if (str_starts_with($relativePath, 'assets/')) {
        $candidates[] = $root . DIRECTORY_SEPARATOR . 'database' . DIRECTORY_SEPARATOR
            . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);
    }

    foreach ($candidates as $full) {
        if (is_file($full) && filesize($full) > 0) {
            return $full;
        }
    }

    return null;
}

/**
 * @return list<string>
 */
function backfill_collect_sql_paths(PDO $pdo): array
{
    $paths = [];
    $queries = [
        ['users', 'profile_image'],
        ['barbers', 'profile_image'],
        ['face_scan_captures', 'file_path'],
        ['face_scan_previews', 'front_url'],
        ['face_scan_previews', 'left_url'],
        ['face_scan_previews', 'right_url'],
        ['appointment_details', 'customer_front_url'],
        ['appointment_details', 'customer_left_url'],
        ['appointment_details', 'customer_right_url'],
        ['hairstyle_variants', 'front_view_url'],
        ['hairstyle_variants', 'side_view_url'],
        ['hairstyle_variants', 'back_view_url'],
    ];

    foreach ($queries as [$table, $column]) {
        if (!backfill_table_exists($pdo, $table) || !backfill_column_exists($pdo, $table, $column)) {
            continue;
        }
        $stmt = $pdo->query("SELECT DISTINCT {$column} AS p FROM {$table} WHERE {$column} IS NOT NULL");
        if (!$stmt) {
            continue;
        }
        foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $raw) {
            $key = backfill_normalize_key((string)$raw);
            if ($key !== '') {
                $paths[$key] = true;
            }
        }
    }

    return array_keys($paths);
}

/**
 * @return list<string>
 */
function backfill_collect_disk_uploads(string $root): array
{
    $paths = [];
    $prefixes = ['uploads/profiles', 'uploads/barbers', 'uploads/face_scans'];
    foreach ($prefixes as $prefix) {
        $dir = $root . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $prefix);
        if (!is_dir($dir)) {
            continue;
        }
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS)
        );
        /** @var SplFileInfo $file */
        foreach ($iterator as $file) {
            if (!$file->isFile() || $file->getSize() <= 0) {
                continue;
            }
            $name = $file->getFilename();
            if ($name === '.gitkeep' || str_starts_with($name, '.')) {
                continue;
            }
            $full = $file->getPathname();
            $rel = str_replace('\\', '/', substr($full, strlen($root) + 1));
            $key = backfill_normalize_key($rel);
            if ($key !== '') {
                $paths[$key] = true;
            }
        }
    }

    return array_keys($paths);
}

/**
 * @return list<string>
 */
function backfill_collect_overlay_files(string $root): array
{
    $paths = [];
    $dir = $root . DIRECTORY_SEPARATOR . 'mobile-app' . DIRECTORY_SEPARATOR
        . 'assets' . DIRECTORY_SEPARATOR . 'images' . DIRECTORY_SEPARATOR . 'overlays';
    if (!is_dir($dir)) {
        return [];
    }
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS)
    );
    /** @var SplFileInfo $file */
    foreach ($iterator as $file) {
        if (!$file->isFile() || $file->getSize() <= 0) {
            continue;
        }
        if (strtolower($file->getExtension()) !== 'png') {
            continue;
        }
        $full = $file->getPathname();
        $marker = 'assets' . DIRECTORY_SEPARATOR . 'images' . DIRECTORY_SEPARATOR . 'overlays';
        $pos = strpos($full, $marker);
        if ($pos === false) {
            continue;
        }
        $rel = str_replace('\\', '/', substr($full, $pos));
        $key = backfill_normalize_key($rel);
        if ($key !== '') {
            $paths[$key] = true;
        }
    }

    return array_keys($paths);
}

$pdo = get_db_connection();
$root = api_project_root();
$keys = [];
foreach (array_merge(
    backfill_collect_sql_paths($pdo),
    backfill_collect_disk_uploads($root),
    backfill_collect_overlay_files($root)
) as $key) {
    $keys[$key] = true;
}
$keys = array_keys($keys);
sort($keys);

if ($limit > 0) {
    $keys = array_slice($keys, 0, $limit);
}

$publicBucket = storage_public_bucket();
$scansBucket = storage_scans_bucket();
$driver = storage_driver();

$ready = ['upload' => [], 'missing' => [], 'invalid' => []];
foreach ($keys as $key) {
    $local = backfill_local_file($key);
    if ($local === null) {
        $ready['missing'][] = $key;
        continue;
    }
    $ready['upload'][] = [
        'key' => $key,
        'file' => $local,
        'bucket' => storage_bucket_for_path($key),
        'bytes' => filesize($local),
        'mime' => storage_mime_from_path($key),
    ];
}

$byBucket = [];
foreach ($ready['upload'] as $item) {
    $byBucket[$item['bucket']] = ($byBucket[$item['bucket']] ?? 0) + 1;
}

echo "STORAGE_DRIVER={$driver} (must stay local during Phase 4)\n";
echo 'Project root: ' . $root . "\n";
echo "Public bucket: {$publicBucket}\n";
echo "Scans bucket:  {$scansBucket}\n";
echo 'Mode: ' . ($apply ? 'APPLY (upload)' : 'DRY-RUN (no uploads)') . "\n";
echo 'Candidates: ' . count($keys)
    . ' | on disk: ' . count($ready['upload'])
    . ' | missing: ' . count($ready['missing']) . "\n";
foreach ($byBucket as $bucket => $count) {
    echo "  would go to {$bucket}: {$count}\n";
}

$sample = array_slice($ready['upload'], 0, 8);
if ($sample !== []) {
    echo "Sample keys:\n";
    foreach ($sample as $item) {
        echo "  [{$item['bucket']}] {$item['key']} ({$item['bytes']} bytes)\n";
    }
}
if ($ready['missing'] !== []) {
    echo 'Missing on disk (skipped, first 8): ' . implode(', ', array_slice($ready['missing'], 0, 8)) . "\n";
}

if (!$apply) {
    echo "\nNo files were uploaded. Create the two buckets, then re-run with --apply.\n";
    exit(0);
}

if ($driver === 'supabase') {
    fwrite(STDERR, "Refusing --apply while STORAGE_DRIVER=supabase. Phase 4 is backfill only; keep STORAGE_DRIVER=local.\n");
    exit(1);
}

if (!storage_remote_configured()) {
    fwrite(STDERR, "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env. Buckets are not created by this script.\n");
    exit(1);
}

$ok = 0;
$fail = 0;
foreach ($ready['upload'] as $item) {
    $bytes = file_get_contents($item['file']);
    if ($bytes === false || $bytes === '') {
        echo "FAIL empty {$item['key']}\n";
        $fail++;
        continue;
    }
    try {
        storage_put_supabase($item['key'], $bytes, $item['mime']);
        $ok++;
        echo "OK {$item['bucket']} {$item['key']}\n";
    } catch (Throwable $e) {
        $fail++;
        echo 'FAIL ' . $item['key'] . ' — ' . $e->getMessage() . "\n";
    }
}

$verified = 0;
$toVerify = array_slice($ready['upload'], 0, min(5, count($ready['upload'])));
foreach ($toVerify as $item) {
    if (storage_exists_supabase($item['key'])) {
        $verified++;
    } else {
        echo "VERIFY MISS {$item['key']}\n";
    }
}

echo "\nUploaded: {$ok}  Failed: {$fail}  Spot-check exists: {$verified}/" . count($toVerify) . "\n";
echo "Database paths were not changed.\n";
exit($fail > 0 ? 2 : 0);
