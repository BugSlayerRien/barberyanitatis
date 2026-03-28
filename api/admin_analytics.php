<?php
// Admin analytics AI summary API

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('GET');

function gemini_summary(string $prompt, string $apiKey): ?string
{
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=' . urlencode($apiKey);
    $payload = json_encode([
        'contents' => [
            ['parts' => [['text' => $prompt]]],
        ],
        'generationConfig' => [
            'temperature' => 0.3,
            'maxOutputTokens' => 220,
        ],
    ]);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => $payload,
    ]);
    $result = curl_exec($ch);
    if ($result === false) {
        curl_close($ch);
        return null;
    }
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($status < 200 || $status >= 300) {
        return null;
    }
    $data = json_decode($result, true);
    return $data['candidates'][0]['content']['parts'][0]['text'] ?? null;
}

try {
    $pdo = get_db_connection();

    $totalUsers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
    $totalBarbers = (int)$pdo->query('SELECT COUNT(*) FROM barbers')->fetchColumn();
    $activeServices = (int)$pdo->query('SELECT COUNT(*) FROM services WHERE is_active = 1')->fetchColumn();

    $statusCounts = $pdo->query(
        "SELECT status, COUNT(*) AS count
         FROM appointments
         GROUP BY status"
    )->fetchAll();

    $monthlyRevenueStmt = $pdo->prepare(
        "SELECT COALESCE(SUM(total_amount), 0)
         FROM payments
         WHERE payment_status = 'Paid'
            AND created_at >= date_trunc('month', CURRENT_DATE)
            AND created_at < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'"
    );
    $monthlyRevenueStmt->execute();
    $monthlyRevenue = (float)$monthlyRevenueStmt->fetchColumn();

    $topServices = $pdo->query(
        "SELECT s.service_name, COUNT(*) AS count
         FROM appointment_details ad
         JOIN services s ON ad.service_id = s.service_id
         GROUP BY s.service_name
         ORDER BY count DESC
         LIMIT 5"
    )->fetchAll();

    $metrics = [
        'totalUsers' => $totalUsers,
        'totalBarbers' => $totalBarbers,
        'activeServices' => $activeServices,
        'monthlyRevenue' => $monthlyRevenue,
        'appointmentStatusCounts' => $statusCounts,
        'topServices' => $topServices,
    ];

    $apiKey = getenv('GEMINI_API_KEY') ?: '';
    $summary = null;
    if ($apiKey !== '') {
        $statusText = implode(', ', array_map(fn($row) => $row['status'] . ':' . $row['count'], $statusCounts));
        $servicesText = implode(', ', array_map(fn($row) => $row['service_name'] . ' (' . $row['count'] . ')', $topServices));
        $prompt = "You are a business analyst for a barbershop. Summarize performance in 3-5 short sentences. "
            . "Metrics: users=$totalUsers, barbers=$totalBarbers, active_services=$activeServices, "
            . "monthly_revenue=₱" . number_format($monthlyRevenue, 2) . ". "
            . "Appointment status counts: $statusText. Top services: $servicesText. "
            . "Give a concise overview and one actionable suggestion.";
        $summary = gemini_summary($prompt, $apiKey);
    }

    json_response([
        'metrics' => $metrics,
        'summary' => $summary ?? 'No AI summary available. Configure GEMINI_API_KEY to enable AI analytics.',
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
