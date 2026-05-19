<?php
// Quick test for scanner API
require_once __DIR__ . '/db.php';

$payload = [
    'action' => 'rankByFeatures',
    'faceShape' => 'Oval',
    'hairTexture' => 'Straight',
];

// Call ai_scan.php via HTTP
$ch = curl_init('http://localhost/barberyanitatis/tatis_barbershop/api/ai_scan.php');
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
$resp = curl_exec($ch);
$code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

echo "=== Scanner API Test ===\n";
echo "Status: $code\n";
$data = json_decode($resp, true);
echo "Recommendations count: " . count($data['recommendations'] ?? []) . "\n\n";

if (count($data['recommendations'] ?? []) > 0) {
    echo "First 3 recommendations:\n";
    foreach (array_slice($data['recommendations'], 0, 3) as $idx => $item) {
        echo ($idx + 1) . ". " . ($item['style_name'] ?? 'N/A') .
             " | Face: " . ($item['face_shape'] ?? 'N/A') .
             " | Texture: " . ($item['hair_texture'] ?? 'N/A') .
             " | Score: " . number_format($item['match_score'] ?? 0, 2) . "\n";
    }
} else {
    echo "No recommendations returned.\n";
    echo "Full response: " . substr($resp, 0, 500) . "\n";
}
