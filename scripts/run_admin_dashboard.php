<?php
$_SERVER['REQUEST_METHOD'] = 'GET';
ob_start();
include __DIR__ . '/../api/admin_dashboard.php';
$out = ob_get_clean();
echo $out;
