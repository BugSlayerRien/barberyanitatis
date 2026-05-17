<?php
// Run admin_audit.php in CLI by simulating a GET request and capturing output
$_SERVER['REQUEST_METHOD'] = 'GET';
// Minimal CGI-like environment
$_SERVER['HTTP_ACCEPT'] = 'application/json';
ob_start();
include __DIR__ . '/../api/admin_audit.php';
$output = ob_get_clean();
// Print cleaned output
echo $output;
