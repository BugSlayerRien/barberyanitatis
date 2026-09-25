<?php
// Admin dashboard API (real data)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/shop_schedule.php';

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);
    auto_complete_due_appointments($pdo);

    $totalUsers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
    $activeServices = (int)$pdo->query('SELECT COUNT(*) FROM services WHERE is_active = TRUE')->fetchColumn();
    $pendingAppointments = (int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE status = 'Scheduled'")->fetchColumn();

        $monthlyRevenueStmt = $pdo->prepare(
                "SELECT COALESCE(SUM(total_amount), 0)::numeric
                 FROM payments
                 WHERE payment_status = 'Paid'
                     AND created_at >= date_trunc('month', CURRENT_DATE)
                     AND created_at < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month'"
        );
    $monthlyRevenueStmt->execute();
    $monthlyRevenue = (float)$monthlyRevenueStmt->fetchColumn();

    $recentAppointmentsStmt = $pdo->prepare(
        "SELECT a.appointment_id, u.full_name, a.created_at
         FROM appointments a
         JOIN users u ON a.user_id = u.user_id
         ORDER BY a.created_at DESC
         LIMIT 5"
    );
    $recentAppointmentsStmt->execute();
    $recentAppointments = $recentAppointmentsStmt->fetchAll();

    $activities = array_map(function ($row) {
        return [
            'icon' => '📅',
            'title' => 'New appointment created',
            'description' => ($row['full_name'] ?? $row['fullName'] ?? 'Customer') . ' booked an appointment',
            'time' => $row['created_at'] ?? $row['createdAt'] ?? null,
        ];
    }, $recentAppointments);

    // --- Shop rating -------------------------------------------------------
    // Averaged from real customer feedback (barber_feedback), NOT from
    // barbers.rating: that column is seeded to 5.00 for every barber, so using
    // it would report a flattering ~4.96 that no customer actually gave.
    // Distribution is returned so the dashboard can draw the 1-5 breakdown
    // instead of printing a single number.
    $shopRating = [
        'average' => null,
        'count' => 0,
        'distribution' => [1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0],
        'source' => 'none',
    ];
    try {
        $ratingRow = $pdo->query(
            "SELECT ROUND(AVG(rating)::numeric, 2) AS avg_rating, COUNT(*)::int AS n
             FROM barber_feedback
             WHERE rating BETWEEN 1 AND 5"
        )->fetch(PDO::FETCH_ASSOC);

        if ($ratingRow && (int)$ratingRow['n'] > 0) {
            $shopRating['average'] = (float)$ratingRow['avg_rating'];
            $shopRating['count'] = (int)$ratingRow['n'];
            $shopRating['source'] = 'customer_feedback';

            $distRows = $pdo->query(
                "SELECT rating, COUNT(*)::int AS c
                 FROM barber_feedback
                 WHERE rating BETWEEN 1 AND 5
                 GROUP BY rating"
            )->fetchAll(PDO::FETCH_ASSOC);
            foreach ($distRows as $row) {
                $shopRating['distribution'][(int)$row['rating']] = (int)$row['c'];
            }
        }
    } catch (Throwable $e) {
        // barber_feedback may not exist on a fresh database; leave the card empty
        // rather than failing the whole dashboard.
    }

    // Per-barber averages for the ranking chart, again from real feedback only.
    $barberRatings = [];
    try {
        $barberRatings = $pdo->query(
            "SELECT b.full_name,
                    ROUND(AVG(f.rating)::numeric, 2)::float AS avg_rating,
                    COUNT(*)::int AS rating_count
             FROM barber_feedback f
             JOIN barbers b ON b.barber_id = f.barber_id
             WHERE f.rating BETWEEN 1 AND 5
               AND b.is_active = TRUE
             GROUP BY b.barber_id, b.full_name
             ORDER BY avg_rating DESC, rating_count DESC
             LIMIT 8"
        )->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $barberRatings = [];
    }

    // 7-day appointment volume for the dashboard sparkline.
    $weekTrend = [];
    try {
        $weekTrend = $pdo->query(
            "SELECT to_char(d.day, 'YYYY-MM-DD') AS day,
                    COUNT(a.appointment_id)::int AS total
             FROM generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, INTERVAL '1 day') AS d(day)
             LEFT JOIN appointments a ON a.appointment_date = d.day::date
             GROUP BY d.day
             ORDER BY d.day"
        )->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $weekTrend = [];
    }

    $response = [
        'shopRating' => $shopRating,
        'barberRatings' => array_map(static fn(array $r): array => [
            'name' => (string)$r['full_name'],
            'rating' => (float)$r['avg_rating'],
            'count' => (int)$r['rating_count'],
        ], $barberRatings),
        'weekTrend' => array_map(static fn(array $r): array => [
            'day' => (string)$r['day'],
            'total' => (int)$r['total'],
        ], $weekTrend),
        'stats' => [
            ['title' => 'Total Users', 'value' => (string)$totalUsers, 'change' => '', 'changeType' => 'success'],
            ['title' => 'Active Services', 'value' => (string)$activeServices, 'change' => '', 'changeType' => 'success'],
            // Calendar month to date. Analytics reports a rolling window for its
            // selected period, so the two figures legitimately differ -- the title
            // says which this one is.
            ['title' => 'Revenue This Month', 'value' => '₱' . number_format($monthlyRevenue, 2), 'change' => '', 'changeType' => 'success'],
            ['title' => 'Pending Appointments', 'value' => (string)$pendingAppointments, 'change' => '', 'changeType' => 'warning'],
        ],
        'activities' => $activities,
    ];

    json_response($response);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
