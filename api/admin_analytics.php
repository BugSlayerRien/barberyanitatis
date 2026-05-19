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
    $activeServices = (int)$pdo->query('SELECT COUNT(*) FROM services WHERE is_active = TRUE')->fetchColumn();

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

    $funnelMetrics = [
        'scanCount' => 0,
        'selectionCount' => 0,
        'bookingCount' => 0,
        'scanToSelectionRate' => 0,
        'selectionToBookingRate' => 0,
        'repeatStyleAcceptanceRate' => 0,
    ];

    $tableExistsStmt = $pdo->prepare(
        "SELECT COUNT(*)
         FROM information_schema.tables
         WHERE table_schema = current_schema() AND table_name = 'ai_recommendation_events'"
    );
    $tableExistsStmt->execute();
    $hasAiEvents = (int)$tableExistsStmt->fetchColumn() > 0;

    if ($hasAiEvents) {
        $scanCount = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'scan_completed'
               AND scan_session_id IS NOT NULL
               AND scan_session_id <> ''"
        )->fetchColumn();

        $selectionCount = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'style_selected'
               AND scan_session_id IS NOT NULL
               AND scan_session_id <> ''"
        )->fetchColumn();

        $bookingCount = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'booking_created'
               AND scan_session_id IS NOT NULL
               AND scan_session_id <> ''"
        )->fetchColumn();

        $repeatUsers = (int)$pdo->query(
            "WITH grouped AS (
                SELECT user_id, variant_id, COUNT(*) AS hits
                FROM ai_recommendation_events
                WHERE event_type = 'booking_created'
                  AND user_id IS NOT NULL
                  AND variant_id IS NOT NULL
                GROUP BY user_id, variant_id
            )
            SELECT COUNT(DISTINCT user_id)
            FROM grouped
            WHERE hits >= 2"
        )->fetchColumn();

        $bookedUsers = (int)$pdo->query(
            "SELECT COUNT(DISTINCT user_id)
             FROM ai_recommendation_events
             WHERE event_type = 'booking_created'
               AND user_id IS NOT NULL"
        )->fetchColumn();

        $funnelMetrics = [
            'scanCount' => $scanCount,
            'selectionCount' => $selectionCount,
            'bookingCount' => $bookingCount,
            'scanToSelectionRate' => $scanCount > 0 ? round(($selectionCount / $scanCount) * 100, 2) : 0,
            'selectionToBookingRate' => $selectionCount > 0 ? round(($bookingCount / $selectionCount) * 100, 2) : 0,
            'repeatStyleAcceptanceRate' => $bookedUsers > 0 ? round(($repeatUsers / $bookedUsers) * 100, 2) : 0,
        ];
    }

    $metrics = [
        'totalUsers' => $totalUsers,
        'totalBarbers' => $totalBarbers,
        'activeServices' => $activeServices,
        'monthlyRevenue' => $monthlyRevenue,
        'appointmentStatusCounts' => $statusCounts,
        'topServices' => $topServices,
        'aiFunnel' => $funnelMetrics,
    ];

    $mobileChatbotKey = 'AQ.Ab8RN6KlvnR-121WQ5uxMLL8cMZN7yWFg8-319S1KXo169ZEBQ';
    $apiKey = getenv('GEMINI_API_KEY') ?: $mobileChatbotKey;
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
