<?php
// Image proxy for Flutter web (adds CORS headers and serves local assets/uploads)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

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

$root = dirname(__DIR__);
$relative = ltrim($path, '/');
$fullPath = $root . '/' . $relative;

if (!is_file($fullPath) && (strpos($relative, 'assets/') === 0)) {
    $altPath = $root . '/database/' . $relative;
    if (is_file($altPath)) {
        $fullPath = $altPath;
    }
}

if (!is_file($fullPath)) {
    json_response(['error' => 'File not found'], 404);
}

$mime = function_exists('mime_content_type') ? mime_content_type($fullPath) : 'application/octet-stream';
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Origin, Content-Type, Accept');
header('X-Content-Type-Options: nosniff');
header('Content-Type: ' . ($mime ?: 'application/octet-stream'));
readfile($fullPath);
exit;