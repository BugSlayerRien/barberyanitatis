<?php
require_once dirname(__DIR__) . '/api/http.php';
load_project_env();

$ch = curl_init('https://api.replicate.com');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_NOBODY => true,
    CURLOPT_TIMEOUT => 15,
] + api_curl_ssl_options());
curl_exec($ch);
$err = curl_error($ch);
$code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
echo $err !== '' ? "FAIL: $err\n" : "OK HTTP $code\n";
