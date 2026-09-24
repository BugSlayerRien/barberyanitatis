<?php
// Image proxy for Flutter web (adds CORS headers and serves local assets/uploads).
// Phase 2: if an uploads/ object is missing on disk, stream it from Storage.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/storage.php';

$path = isset($_GET['path']) ? trim((string)$_GET['path']) : '';
if ($path === '') {
    json_response(['error' => 'Missing path'], 422);
}

$path = str_replace('\0', '', $path);
$path = str_replace('\\', '/', $path);

$allowedPrefixes = ['assets/', '/assets/', 'uploads/', '/uploads/', 'database/assets/', '/database/assets/'];
$allowed = false;
foreach ($allowedPrefixes as $prefix) {
    if (strpos($path, $prefix) === 0) {
        $allowed = true;
        break;
    }
}
if (!$allowed) {
    json_response(['error' => 'Invalid path'], 400);
}

$root = api_project_root();
$relative = ltrim($path, '/');
$fullPath = $root . '/' . $relative;

// assets/ paths are stored relative to whichever tree owns them: seeded assets
// live under database/, and admin-uploaded overlays are written into
// mobile-app/ (see mobile_app_overlay_root()). Check both before giving up on
// disk and falling through to Storage.
if (!is_file($fullPath) && (strpos($relative, 'assets/') === 0)) {
    foreach (['database', 'mobile-app'] as $altRoot) {
        $altPath = $root . '/' . $altRoot . '/' . $relative;
        if (is_file($altPath)) {
            $fullPath = $altPath;
            break;
        }
    }
}

$sendCors = static function (): void {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, OPTIONS');
    header('Access-Control-Allow-Headers: Origin, Content-Type, Accept');
    header('X-Content-Type-Options: nosniff');
};

if (is_file($fullPath)) {
    $mime = function_exists('mime_content_type') ? mime_content_type($fullPath) : 'application/octet-stream';
    $sendCors();
    header('Content-Type: ' . ($mime ?: 'application/octet-stream'));
    readfile($fullPath);
    exit;
}

if (strpos($relative, 'uploads/') === 0 || strpos($relative, 'assets/images/overlays/') === 0) {
    $bytes = storage_get_bytes($relative);
    if ($bytes !== null && $bytes !== '') {
        $sendCors();
        header('Content-Type: ' . storage_mime_from_path($relative));
        echo $bytes;
        exit;
    }
}

json_response(['error' => 'File not found'], 404);
