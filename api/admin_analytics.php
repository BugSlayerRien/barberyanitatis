<?php
// Admin analytics dashboard API — period-scoped metrics from live operational tables.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';

$method = strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET'));
if (!in_array($method, ['GET', 'POST'], true)) {
    json_response(['error' => 'Method not allowed'], 405);
}

function analytics_gemini_summary(string $prompt, string $apiKey): ?string
{
    $url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=' . urlencode($apiKey);
    $payload = json_encode([
        'contents' => [
            ['parts' => [['text' => $prompt]]],
        ],
        'generationConfig' => [
            'temperature' => 0.2,
            'maxOutputTokens' => 320,
        ],
    ]);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 20,
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

function analytics_table_exists(PDO $pdo, string $table): bool
{
    static $cache = [];
    if (array_key_exists($table, $cache)) {
        return $cache[$table];
    }
    try {
        $stmt = $pdo->prepare(
            "SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = current_schema() AND table_name = :table"
        );
        $stmt->execute([':table' => $table]);
        $cache[$table] = (int)$stmt->fetchColumn() > 0;
    } catch (Throwable $e) {
        $cache[$table] = false;
    }

    return $cache[$table];
}

/**
 * @return array<string, mixed>
 */
function analytics_period_config(string $period): array
{
    $period = strtolower(trim($period));
    if ($period === 'today' || $period === 'week') {
        $period = '7d';
    } elseif ($period === 'month') {
        $period = '30d';
    }
    if (!in_array($period, ['7d', '30d', '3m', '1y'], true)) {
        $period = '30d';
    }

    $labels = [
        '7d' => 'Last 7 days',
        '30d' => 'Last 30 days',
        '3m' => 'Last 3 months',
        '1y' => 'Last 1 year',
    ];
    $daysMap = ['7d' => 6, '30d' => 29, '3m' => 89, '1y' => 364];
    $daysBack = $daysMap[$period];

    $startExpr = "(CURRENT_DATE - INTERVAL '{$daysBack} days')";
    $endExclusiveExpr = "(CURRENT_DATE + INTERVAL '1 day')";

    if ($period === '7d' || $period === '30d') {
        $bucketAppt = "to_char(appointment_date, 'YYYY-MM-DD')";
        $bucketPay = "to_char(created_at::date, 'YYYY-MM-DD')";
    } elseif ($period === '3m') {
        $bucketAppt = "to_char(date_trunc('week', appointment_date), 'IYYY-\"W\"IW')";
        $bucketPay = "to_char(date_trunc('week', created_at), 'IYYY-\"W\"IW')";
    } else {
        $bucketAppt = "to_char(date_trunc('month', appointment_date), 'YYYY-MM')";
        $bucketPay = "to_char(date_trunc('month', created_at), 'YYYY-MM')";
    }

    return [
        'key' => $period,
        'label' => $labels[$period],
        'daysBack' => $daysBack,
        'paymentSql' => "created_at >= {$startExpr} AND created_at < {$endExclusiveExpr}",
        'appointmentSql' => "appointment_date >= {$startExpr}::date AND appointment_date < {$endExclusiveExpr}::date",
        'eventSql' => "created_at >= {$startExpr} AND created_at < {$endExclusiveExpr}",
        'walkinSql' => "created_at >= {$startExpr} AND created_at < {$endExclusiveExpr}",
        'userCreatedSql' => "created_at >= {$startExpr} AND created_at < {$endExclusiveExpr}",
        'feedbackSql' => "created_at >= {$startExpr} AND created_at < {$endExclusiveExpr}",
        'bucketSqlAppointments' => $bucketAppt,
        'bucketSqlPayments' => $bucketPay,
    ];
}

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);

    $periodInput = $_GET['period'] ?? null;
    if ($method === 'POST') {
        $body = get_json_input();
        $periodInput = $periodInput ?? ($body['period'] ?? null);
    }

    $cfg = analytics_period_config((string)($periodInput ?? '30d'));
    $today = new DateTimeImmutable('today');
    $startDate = $today->modify('-' . (int)$cfg['daysBack'] . ' days')->format('Y-m-d');
    $endDate = $today->format('Y-m-d');
    $daysBack = (int)$cfg['daysBack'];

    $apptWhere = $cfg['appointmentSql'];
    // Qualified copies for queries that join tables sharing these column names.
    // hairstyles and hairstyle_variants both have created_at, so an unqualified
    // filter there is ambiguous and Postgres rejects the whole query.
    $apptWhereA = str_replace('appointment_date', 'a.appointment_date', $cfg['appointmentSql']);
    $eventWhereE = str_replace('created_at', 'e.created_at', $cfg['eventSql']);
    // A booking counts toward "most booked" only if it was not cancelled or a
    // no-show. Same rule as mostBookedBarber below and as the customer app's
    // trending haircut (api/booking.php getCustomerHomeInsights), so the admin
    // dashboard and the app agree on which haircut is most booked.
    $activeBookingStatuses = "('Completed', 'Scheduled', 'CheckedIn', 'InProgress')";
    $payWhere = $cfg['paymentSql'];
    $eventWhere = $cfg['eventSql'];
    $walkinWhere = $cfg['walkinSql'];
    $userWhere = $cfg['userCreatedSql'];
    $feedbackWhere = $cfg['feedbackSql'];

    $totalAppointments = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointments WHERE {$apptWhere}"
    )->fetchColumn();

    $completedAppointments = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointments WHERE {$apptWhere} AND status = 'Completed'"
    )->fetchColumn();

    $cancelledCount = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointments WHERE {$apptWhere} AND status = 'Cancelled'"
    )->fetchColumn();

    $noShowCount = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointments WHERE {$apptWhere} AND status = 'NoShow'"
    )->fetchColumn();

    $periodRevenue = (float)$pdo->query(
        "SELECT COALESCE(SUM(total_amount), 0)
         FROM payments
         WHERE payment_status = 'Paid'
           AND {$payWhere}"
    )->fetchColumn();

    $totalCustomers = (int)$pdo->query('SELECT COUNT(*) FROM users')->fetchColumn();
    $newCustomers = (int)$pdo->query(
        "SELECT COUNT(*) FROM users WHERE {$userWhere}"
    )->fetchColumn();

    $returningCustomers = (int)$pdo->query(
        "SELECT COUNT(DISTINCT a.user_id)
         FROM appointments a
         WHERE a.appointment_date >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
           AND a.appointment_date <= CURRENT_DATE
           AND a.user_id IS NOT NULL
           AND EXISTS (
             SELECT 1 FROM appointments prior
             WHERE prior.user_id = a.user_id
               AND prior.appointment_date < (CURRENT_DATE - INTERVAL '{$daysBack} days')
           )"
    )->fetchColumn();

    $avgRating = null;
    $ratingCount = 0;
    if (analytics_table_exists($pdo, 'barber_feedback')) {
        try {
            $ratingRow = $pdo->query(
                "SELECT ROUND(AVG(rating)::numeric, 2) AS avg_rating, COUNT(*)::int AS rating_count
                 FROM barber_feedback
                 WHERE {$feedbackWhere}"
            )->fetch(PDO::FETCH_ASSOC);
            if ($ratingRow && (int)($ratingRow['rating_count'] ?? 0) > 0) {
                $avgRating = (float)$ratingRow['avg_rating'];
                $ratingCount = (int)$ratingRow['rating_count'];
            }
        } catch (Throwable $e) {
            $avgRating = null;
        }
    }

    if ($avgRating === null) {
        $barberAvg = $pdo->query(
            "SELECT ROUND(AVG(rating)::numeric, 2)
             FROM barbers
             WHERE is_active = TRUE AND rating IS NOT NULL AND rating > 0"
        )->fetchColumn();
        if ($barberAvg !== false && $barberAvg !== null) {
            $avgRating = (float)$barberAvg;
        }
    }

    $cancellationRate = $totalAppointments > 0
        ? round(($cancelledCount / $totalAppointments) * 100, 1)
        : 0.0;
    $noShowRate = $totalAppointments > 0
        ? round(($noShowCount / $totalAppointments) * 100, 1)
        : 0.0;

    $statusCounts = $pdo->query(
        "SELECT status, COUNT(*)::int AS count
         FROM appointments
         WHERE {$apptWhere}
         GROUP BY status
         ORDER BY count DESC"
    )->fetchAll(PDO::FETCH_ASSOC);

    $appointmentTrend = $pdo->query(
        "SELECT {$cfg['bucketSqlAppointments']} AS bucket, COUNT(*)::int AS count
         FROM appointments
         WHERE {$apptWhere}
         GROUP BY 1
         ORDER BY 1"
    )->fetchAll(PDO::FETCH_ASSOC);

    $revenueTrend = $pdo->query(
        "SELECT {$cfg['bucketSqlPayments']} AS bucket, COALESCE(SUM(total_amount), 0)::float AS amount
         FROM payments
         WHERE payment_status = 'Paid'
           AND {$payWhere}
         GROUP BY 1
         ORDER BY 1"
    )->fetchAll(PDO::FETCH_ASSOC);

    $statusTrendByBucket = $pdo->query(
        "SELECT {$cfg['bucketSqlAppointments']} AS bucket, status, COUNT(*)::int AS count
         FROM appointments
         WHERE {$apptWhere}
         GROUP BY 1, status
         ORDER BY 1"
    )->fetchAll(PDO::FETCH_ASSOC);

    $barberPerformance = $pdo->query(
        "SELECT b.barber_id, b.full_name, b.barber_channel,
                COUNT(*) FILTER (WHERE a.status = 'Completed')::int AS completed,
                COUNT(*) FILTER (WHERE a.status = 'Cancelled')::int AS cancelled,
                COUNT(*) FILTER (WHERE a.status = 'NoShow')::int AS no_show,
                COUNT(a.appointment_id)::int AS total_appointments,
                -- Walk-in barbers take no appointments, so their 'completed'
                -- count has to come from the queue or they read as idle.
                COALESCE(w.walkin_completed, 0)::int AS walkin_completed,
                COALESCE(b.rating, 0)::float AS barber_rating
         FROM barbers b
         LEFT JOIN appointments a
           ON a.barber_id = b.barber_id
          AND {$apptWhere}
         LEFT JOIN (
             SELECT barber_id, COUNT(*) AS walkin_completed
             FROM walkin_queue
             WHERE status = 'Completed'
               AND created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
               AND created_at < (CURRENT_DATE + INTERVAL '1 day')
             GROUP BY barber_id
         ) w ON w.barber_id = b.barber_id
         WHERE b.is_active = TRUE
         GROUP BY b.barber_id, b.full_name, b.barber_channel, b.rating, w.walkin_completed
         ORDER BY completed DESC, b.full_name ASC"
    )->fetchAll(PDO::FETCH_ASSOC);

    // Revenue must come from BOTH sides of the payments table.
    //
    // payments carries appointment_id OR queue_id. Joining only appointments
    // dropped every walk-in payment, so regular (walk_in channel) barbers always
    // reported P0.00 even with completed services -- verified against live data:
    // three walk-in barbers had P1,300 of paid walk-ins in the period, all of it
    // invisible here.
    $barberRevenueMap = [];
    $barberRevRows = $pdo->query(
        "SELECT barber_id, COALESCE(SUM(total_amount), 0)::float AS revenue
         FROM (
             SELECT a.barber_id, p.total_amount
             FROM payments p
             JOIN appointments a ON a.appointment_id = p.appointment_id
             WHERE p.payment_status = 'Paid'
               AND p.created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
               AND p.created_at < (CURRENT_DATE + INTERVAL '1 day')
             UNION ALL
             SELECT w.barber_id, p.total_amount
             FROM payments p
             JOIN walkin_queue w ON w.queue_id = p.queue_id
             WHERE p.payment_status = 'Paid'
               AND p.created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
               AND p.created_at < (CURRENT_DATE + INTERVAL '1 day')
         ) AS all_payments
         WHERE barber_id IS NOT NULL
         GROUP BY barber_id"
    )->fetchAll(PDO::FETCH_ASSOC);
    foreach ($barberRevRows as $row) {
        $barberRevenueMap[(int)$row['barber_id']] = (float)$row['revenue'];
    }

    $barberFeedbackMap = [];
    if (analytics_table_exists($pdo, 'barber_feedback')) {
        try {
            $fbRows = $pdo->query(
                "SELECT barber_id,
                        ROUND(AVG(rating)::numeric, 2)::float AS avg_rating,
                        COUNT(*)::int AS rating_count
                 FROM barber_feedback
                 WHERE {$feedbackWhere}
                 GROUP BY barber_id"
            )->fetchAll(PDO::FETCH_ASSOC);
            foreach ($fbRows as $row) {
                $barberFeedbackMap[(int)$row['barber_id']] = [
                    'avgRating' => (float)$row['avg_rating'],
                    'ratingCount' => (int)$row['rating_count'],
                ];
            }
        } catch (Throwable $e) {
            // ignore
        }
    }

    $barberRows = [];
    foreach ($barberPerformance as $row) {
        $id = (int)$row['barber_id'];
        $fb = $barberFeedbackMap[$id] ?? null;
        $barberRows[] = [
            'barberId' => $id,
            'barberName' => (string)$row['full_name'],
            // Walk-in barbers are measured by queue completions, not appointments.
            'completed' => ((string)($row['barber_channel'] ?? '') === 'walk_in')
                ? (int)$row['walkin_completed']
                : (int)$row['completed'],
            'cancelled' => (int)$row['cancelled'],
            'noShow' => (int)$row['no_show'],
            'totalAppointments' => (int)$row['total_appointments'],
            'revenue' => (float)($barberRevenueMap[$id] ?? 0),
            // 'walk_in' (regular) or 'appointment' (exclusive). Ratings and
            // cancel/no-show only exist for the appointment channel, so the UI
            // renders the two as separate tables with different columns.
            'channel' => (string)($row['barber_channel'] ?? 'appointment'),
            'avgRating' => $fb['avgRating'] ?? ((float)$row['barber_rating'] > 0 ? (float)$row['barber_rating'] : null),
            'ratingCount' => $fb['ratingCount'] ?? 0,
            'ratingSource' => $fb ? 'period_feedback' : 'barber_profile',
        ];
    }

    $peakHours = $pdo->query(
        "SELECT EXTRACT(HOUR FROM start_time)::int AS hour, COUNT(*)::int AS count
         FROM appointments
         WHERE {$apptWhere}
           AND start_time IS NOT NULL
         GROUP BY 1
         ORDER BY 1"
    )->fetchAll(PDO::FETCH_ASSOC);

    $busiestDays = $pdo->query(
        "SELECT EXTRACT(DOW FROM appointment_date)::int AS dow, COUNT(*)::int AS count
         FROM appointments
         WHERE {$apptWhere}
         GROUP BY 1
         ORDER BY 1"
    )->fetchAll(PDO::FETCH_ASSOC);

    $walkinCount = 0;
    if (analytics_table_exists($pdo, 'walkin_queue')) {
        try {
            $walkinCount = (int)$pdo->query(
                "SELECT COUNT(*) FROM walkin_queue WHERE {$walkinWhere}"
            )->fetchColumn();
        } catch (Throwable $e) {
            $walkinCount = 0;
        }
    }

    $mostFavoritedHairstyles = [];
    if (analytics_table_exists($pdo, 'user_favorites')) {
        try {
            $mostFavoritedHairstyles = $pdo->query(
                "SELECT hs.style_name, hv.variant_id, COUNT(*)::int AS favorite_count
                 FROM user_favorites uf
                 JOIN hairstyle_variants hv ON hv.variant_id = uf.variant_id
                 JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
                 WHERE uf.variant_id IS NOT NULL
                   AND uf.created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
                   AND uf.created_at < (CURRENT_DATE + INTERVAL '1 day')
                 GROUP BY hs.style_name, hv.variant_id
                 ORDER BY favorite_count DESC
                 LIMIT 8"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $mostFavoritedHairstyles = [];
        }
    }

    $mostBookedBarber = null;
    $topBarberRow = $pdo->query(
        "SELECT b.barber_id, b.full_name, COUNT(*)::int AS booking_count
         FROM appointments a
         JOIN barbers b ON b.barber_id = a.barber_id
         WHERE {$apptWhere}
           AND a.status IN ('Completed', 'Scheduled', 'CheckedIn', 'InProgress')
         GROUP BY b.barber_id, b.full_name
         ORDER BY booking_count DESC
         LIMIT 1"
    )->fetch(PDO::FETCH_ASSOC);
    if ($topBarberRow) {
        $mostBookedBarber = [
            'barberId' => (int)$topBarberRow['barber_id'],
            'barberName' => (string)$topBarberRow['full_name'],
            'bookingCount' => (int)$topBarberRow['booking_count'],
            'note' => 'Most booked barber in the selected period (barber favorites are not stored).',
        ];
    }

    // Preview-credit sales.
    //
    // These live in appointment_payments with a NULL appointment_id, so every
    // revenue query in this file misses them -- they are not service revenue.
    // Reported separately rather than folded in, so neither number lies.
    $creditSales = ['count' => 0, 'credits' => 0, 'revenue' => 0.0, 'recent' => []];
    try {
        $row = $pdo->query(
            "SELECT COUNT(*)::int AS sale_count,
                    COALESCE(SUM(credits), 0)::int AS credits,
                    COALESCE(SUM(amount), 0)::float AS revenue
             FROM appointment_payments
             WHERE purpose = 'ai_credits' AND status = 'Captured' AND {$payWhere}"
        )->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            $creditSales['count'] = (int)$row['sale_count'];
            $creditSales['credits'] = (int)$row['credits'];
            $creditSales['revenue'] = (float)$row['revenue'];
        }

        $creditSales['recent'] = $pdo->query(
            "SELECT ap.payment_id, ap.credits, ap.amount::float AS amount, ap.method,
                    ap.transaction_ref, ap.created_at,
                    COALESCE(u.full_name, 'Customer #' || ap.user_id) AS customer_name
             FROM appointment_payments ap
             LEFT JOIN users u ON u.user_id = ap.user_id
             WHERE ap.purpose = 'ai_credits' AND ap.status = 'Captured'
             ORDER BY ap.created_at DESC
             LIMIT 10"
        )->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $e) {
        // purpose/credits are lazily added columns; a shop that has never sold
        // a credit may not have them yet. Zero is the honest answer.
        error_log('Credit sales query skipped: ' . $e->getMessage());
    }

    $aiFunnel = [
        'scanCount' => 0,
        'selectionCount' => 0,
        'bookingCount' => 0,
        'generationCount' => 0,
        'scanToSelectionRate' => 0,
        'selectionToBookingRate' => 0,
        'scanToBookingRate' => 0,
        'available' => false,
    ];
    $mostGenerated = [];
    $mostSelected = [];
    $mostBookedStyles = [];
    $faceShapeDistribution = [];
    $hairTextureDistribution = [];

    if (analytics_table_exists($pdo, 'ai_recommendation_events')) {
        $aiFunnel['available'] = true;
        $scanCount = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'scan_completed'
               AND scan_session_id IS NOT NULL AND scan_session_id <> ''
               AND {$eventWhere}"
        )->fetchColumn();
        $selectionCount = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'style_selected'
               AND scan_session_id IS NOT NULL AND scan_session_id <> ''
               AND {$eventWhere}"
        )->fetchColumn();
        $bookingCountAi = (int)$pdo->query(
            "SELECT COUNT(DISTINCT scan_session_id)
             FROM ai_recommendation_events
             WHERE event_type = 'booking_created'
               AND scan_session_id IS NOT NULL AND scan_session_id <> ''
               AND {$eventWhere}"
        )->fetchColumn();

        $aiFunnel['scanCount'] = $scanCount;
        $aiFunnel['selectionCount'] = $selectionCount;
        $aiFunnel['bookingCount'] = $bookingCountAi;
        $aiFunnel['scanToSelectionRate'] = $scanCount > 0 ? min(100, round(($selectionCount / $scanCount) * 100, 1)) : 0;
        $aiFunnel['selectionToBookingRate'] = $selectionCount > 0 ? min(100, round(($bookingCountAi / $selectionCount) * 100, 1)) : 0;
        $aiFunnel['scanToBookingRate'] = $scanCount > 0 ? min(100, round(($bookingCountAi / $scanCount) * 100, 1)) : 0;

        try {
            $mostSelected = $pdo->query(
                "SELECT COALESCE(hs.style_name, 'Style #' || e.variant_id::text) AS style_name,
                        e.variant_id, COUNT(*)::int AS count
                 FROM ai_recommendation_events e
                 LEFT JOIN hairstyle_variants hv ON hv.variant_id = e.variant_id
                 LEFT JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
                 WHERE e.event_type = 'style_selected'
                   AND e.variant_id IS NOT NULL
                   AND {$eventWhereE}
                 GROUP BY hs.style_name, e.variant_id
                 ORDER BY count DESC
                 LIMIT 8"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $mostSelected = [];
        }

        try {
            $faceShapeDistribution = $pdo->query(
                "SELECT COALESCE(NULLIF(TRIM(face_shape), ''), 'Unknown') AS label, COUNT(*)::int AS count
                 FROM ai_recommendation_events
                 WHERE event_type = 'scan_completed'
                   AND {$eventWhere}
                 GROUP BY 1
                 ORDER BY count DESC"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $faceShapeDistribution = [];
        }

        try {
            $hairTextureDistribution = $pdo->query(
                "SELECT COALESCE(NULLIF(TRIM(hair_texture), ''), 'Unknown') AS label, COUNT(*)::int AS count
                 FROM ai_recommendation_events
                 WHERE event_type = 'scan_completed'
                   AND {$eventWhere}
                 GROUP BY 1
                 ORDER BY count DESC"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $hairTextureDistribution = [];
        }
    }

    if (analytics_table_exists($pdo, 'face_scan_previews')) {
        try {
            $aiFunnel['generationCount'] = (int)$pdo->query(
                "SELECT COUNT(*) FROM face_scan_previews
                 WHERE created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
                   AND created_at < (CURRENT_DATE + INTERVAL '1 day')"
            )->fetchColumn();

            $mostGenerated = $pdo->query(
                "SELECT COALESCE(hs.style_name, 'Style #' || fsp.variant_id::text) AS style_name,
                        fsp.variant_id, COUNT(*)::int AS generation_count
                 FROM face_scan_previews fsp
                 LEFT JOIN hairstyle_variants hv ON hv.variant_id = fsp.variant_id
                 LEFT JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
                 WHERE fsp.created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
                   AND fsp.created_at < (CURRENT_DATE + INTERVAL '1 day')
                   AND fsp.variant_id IS NOT NULL
                 GROUP BY hs.style_name, fsp.variant_id
                 ORDER BY generation_count DESC
                 LIMIT 8"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            // ignore
        }
    }

    if ($faceShapeDistribution === [] && analytics_table_exists($pdo, 'face_scan_sessions')) {
        try {
            $faceShapeDistribution = $pdo->query(
                "SELECT COALESCE(NULLIF(TRIM(face_shape), ''), 'Unknown') AS label, COUNT(*)::int AS count
                 FROM face_scan_sessions
                 WHERE face_shape IS NOT NULL
                   AND created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
                   AND created_at < (CURRENT_DATE + INTERVAL '1 day')
                 GROUP BY 1
                 ORDER BY count DESC"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $faceShapeDistribution = [];
        }
    }

    if ($hairTextureDistribution === [] && analytics_table_exists($pdo, 'face_scan_sessions')) {
        try {
            $hairTextureDistribution = $pdo->query(
                "SELECT COALESCE(NULLIF(TRIM(hair_texture), ''), 'Unknown') AS label, COUNT(*)::int AS count
                 FROM face_scan_sessions
                 WHERE hair_texture IS NOT NULL
                   AND created_at >= (CURRENT_DATE - INTERVAL '{$daysBack} days')
                   AND created_at < (CURRENT_DATE + INTERVAL '1 day')
                 GROUP BY 1
                 ORDER BY count DESC"
            )->fetchAll(PDO::FETCH_ASSOC);
        } catch (Throwable $e) {
            $hairTextureDistribution = [];
        }
    }

    try {
        // Ranked per haircut, not per variant: "Blowout Taper" has several
        // variants, and counting them separately let a style lose the top spot
        // to itself. variant_id is the haircut's most-booked variant.
        $mostBookedStyles = $pdo->query(
            "WITH booked AS (
                 SELECT hs.hairstyle_id, hs.style_name, ad.variant_id, COUNT(*)::int AS n
                 FROM appointment_details ad
                 JOIN appointments a ON a.appointment_id = ad.appointment_id
                 JOIN hairstyle_variants hv ON hv.variant_id = ad.variant_id
                 JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
                 WHERE {$apptWhereA}
                   AND a.status IN {$activeBookingStatuses}
                   AND ad.variant_id IS NOT NULL AND ad.variant_id > 0
                 GROUP BY hs.hairstyle_id, hs.style_name, ad.variant_id
             )
             SELECT style_name,
                    (ARRAY_AGG(variant_id ORDER BY n DESC, variant_id))[1] AS variant_id,
                    SUM(n)::int AS booking_count
             FROM booked
             GROUP BY hairstyle_id, style_name
             ORDER BY booking_count DESC, style_name ASC
             LIMIT 8"
        )->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        $mostBookedStyles = [];
    }

    $ratingDistribution = [];
    $ratingByBarber = [];
    $recentFeedback = [];

    if (analytics_table_exists($pdo, 'barber_feedback')) {
        try {
            $ratingDistribution = $pdo->query(
                "SELECT rating::int AS rating, COUNT(*)::int AS count
                 FROM barber_feedback
                 WHERE {$feedbackWhere}
                 GROUP BY rating
                 ORDER BY rating"
            )->fetchAll(PDO::FETCH_ASSOC);

            $ratingByBarber = $pdo->query(
                "SELECT b.full_name AS barber_name,
                        ROUND(AVG(bf.rating)::numeric, 2)::float AS avg_rating,
                        COUNT(*)::int AS rating_count
                 FROM barber_feedback bf
                 JOIN barbers b ON b.barber_id = bf.barber_id
                 WHERE {$feedbackWhere}
                 GROUP BY b.full_name
                 ORDER BY avg_rating DESC, rating_count DESC
                 LIMIT 10"
            )->fetchAll(PDO::FETCH_ASSOC);

            $recentRows = $pdo->query(
                "SELECT b.full_name AS barber_name, bf.rating, bf.comment, bf.created_at
                 FROM barber_feedback bf
                 JOIN barbers b ON b.barber_id = bf.barber_id
                 WHERE {$feedbackWhere}
                 ORDER BY bf.created_at DESC
                 LIMIT 8"
            )->fetchAll(PDO::FETCH_ASSOC);

            $recentFeedback = array_map(static function (array $row): array {
                $comment = trim((string)($row['comment'] ?? ''));
                if (strlen($comment) > 120) {
                    $comment = substr($comment, 0, 117) . '...';
                }

                return [
                    'barberName' => (string)$row['barber_name'],
                    'rating' => (int)$row['rating'],
                    'comment' => $comment,
                    'createdAt' => (string)$row['created_at'],
                ];
            }, $recentRows);
        } catch (Throwable $e) {
            // ignore
        }
    }

    $kpis = [
        'totalRevenue' => $periodRevenue,
        'totalAppointments' => $totalAppointments,
        'completedAppointments' => $completedAppointments,
        'cancelledOrNoShow' => $cancelledCount + $noShowCount,
        'cancelled' => $cancelledCount,
        'noShow' => $noShowCount,
        'totalCustomers' => $totalCustomers,
        'averageRating' => $avgRating,
        'ratingCount' => $ratingCount,
    ];

    $metrics = [
        'period' => $cfg['key'],
        'periodLabel' => $cfg['label'],
        'startDate' => $startDate,
        'endDate' => $endDate,
        'kpis' => $kpis,
        'periodRevenue' => $periodRevenue,
        'monthlyRevenue' => $periodRevenue,
        'appointmentsInPeriod' => $totalAppointments,
        'totalUsers' => $totalCustomers,
        'appointmentStatusCounts' => $statusCounts,
        'trends' => [
            'appointments' => $appointmentTrend,
            'revenue' => $revenueTrend,
            'statusByBucket' => $statusTrendByBucket,
        ],
        'barberPerformance' => $barberRows,
        'operations' => [
            'peakHours' => $peakHours,
            'busiestDays' => $busiestDays,
            'appointmentVolume' => $totalAppointments,
            'walkinVolume' => $walkinCount,
            'cancellationRate' => $cancellationRate,
            'noShowRate' => $noShowRate,
        ],
        'customers' => [
            'totalCustomers' => $totalCustomers,
            'newCustomers' => $newCustomers,
            'returningCustomers' => $returningCustomers,
            'mostBookedBarber' => $mostBookedBarber,
            'mostFavoritedHairstyles' => $mostFavoritedHairstyles,
        ],
        'ai' => [
            'funnel' => $aiFunnel,
            'mostGenerated' => $mostGenerated,
            'mostSelected' => $mostSelected,
            'mostBooked' => $mostBookedStyles,
            'faceShapeDistribution' => $faceShapeDistribution,
            'hairTextureDistribution' => $hairTextureDistribution,
            'creditSales' => $creditSales,
        ],
        'aiFunnel' => $aiFunnel,
        'feedback' => [
            'averageRating' => $avgRating,
            'ratingCount' => $ratingCount,
            'ratingDistribution' => $ratingDistribution,
            'ratingByBarber' => $ratingByBarber,
            'ratingByServiceAvailable' => false,
            'ratingByServiceNote' => 'Service-level ratings are not stored in the current database.',
            'recentFeedback' => $recentFeedback,
        ],
        'dataNotes' => [
            'revenueSource' => 'Completion payments ledger (payments.payment_status = Paid). '
                . 'Preview-credit sales are reported separately under AI and are not included here.',
            'barberFavorites' => 'Barber favorites are not collected; showing most-booked barber instead.',
            'serviceRatings' => 'Service-level ratings are not available in the current schema.',
        ],
    ];

    $apiKey = trim((string)(getenv('GEMINI_API_KEY') ?: ($_ENV['GEMINI_API_KEY'] ?? '')));
    $summary = null;
    $insight = null;
    $recommendation = null;
    $prediction = null;
    $dataSparse = $totalAppointments < 3 && $periodRevenue <= 0 && $ratingCount === 0;

    if ($apiKey !== '' && !$dataSparse) {
        $statusText = implode(', ', array_map(
            static fn(array $row): string => ($row['status'] ?? '') . ':' . ($row['count'] ?? 0),
            $statusCounts
        ));
        $prompt = "You are a barbershop business analyst. Use ONLY the provided metrics. "
            . "Do not invent numbers. If data is thin, say so. "
            . "Return plain text with exactly 3 labeled lines:\n"
            . "INSIGHT: <one sentence>\n"
            . "RECOMMENDATION: <one actionable sentence>\n"
            . "PREDICTION: <one cautious sentence or 'Insufficient data for a reliable prediction.'>\n\n"
            . "Period: {$cfg['label']} ({$startDate} to {$endDate}). "
            . "Revenue=₱" . number_format($periodRevenue, 2)
            . ", appointments={$totalAppointments}, completed={$completedAppointments}, "
            . "cancelled={$cancelledCount}, no_show={$noShowCount}, "
            . "new_customers={$newCustomers}, returning_customers={$returningCustomers}, "
            . "avg_rating=" . ($avgRating !== null ? (string)$avgRating : 'n/a')
            . ", cancellation_rate={$cancellationRate}%, no_show_rate={$noShowRate}%. "
            . "Status mix: {$statusText}. "
            . "AI scans={$aiFunnel['scanCount']}, selections={$aiFunnel['selectionCount']}, "
            . "AI bookings={$aiFunnel['bookingCount']}, generations={$aiFunnel['generationCount']}.";

        $raw = analytics_gemini_summary($prompt, $apiKey);
        if (is_string($raw) && trim($raw) !== '') {
            $summary = trim($raw);
            if (preg_match('/INSIGHT:\s*(.+)/i', $raw, $m)) {
                $insight = trim($m[1]);
            }
            if (preg_match('/RECOMMENDATION:\s*(.+)/i', $raw, $m)) {
                $recommendation = trim($m[1]);
            }
            if (preg_match('/PREDICTION:\s*(.+)/i', $raw, $m)) {
                $prediction = trim($m[1]);
            }
        }
    }

    if ($dataSparse) {
        $insight = 'Insufficient data in this period for a reliable business insight.';
        $recommendation = 'Continue recording appointments, payments, and ratings so analytics can guide decisions.';
        $prediction = 'Insufficient data for a reliable prediction.';
        $summary = $insight;
    } elseif ($insight === null) {
        if ($totalAppointments === 0) {
            $insight = 'No appointments were recorded in the selected period.';
            $recommendation = 'Confirm schedule availability and promote booking channels if the shop was open.';
            $prediction = 'Insufficient data for a reliable prediction.';
        } else {
            $insight = "In {$cfg['label']}, the shop recorded {$totalAppointments} appointments"
                . ($completedAppointments > 0 ? " ({$completedAppointments} completed)" : '')
                . ' and ₱' . number_format($periodRevenue, 2) . ' in paid completion revenue.';
            if ($cancellationRate >= 15 || $noShowRate >= 10) {
                $recommendation = 'Focus on reducing cancellations/no-shows with reminders before peak days.';
            } elseif ($aiFunnel['scanCount'] > 0 && $aiFunnel['scanToBookingRate'] < 20) {
                $recommendation = 'Improve AI try-on follow-through — scans are happening but few convert to bookings.';
            } else {
                $recommendation = 'Protect peak booking hours with enough barber coverage based on the operations chart.';
            }
            $prediction = ($totalAppointments >= 10)
                ? 'Near-term volume is likely to resemble the recent period if hours and staffing stay similar. This is directional, not a guarantee.'
                : 'Insufficient data for a reliable prediction.';
        }
        $summary = $insight;
    }

    json_response([
        'metrics' => $metrics,
        'summary' => $summary ?? 'Configure GEMINI_API_KEY for AI-written insights, or use the metric panels below.',
        'aiInsights' => [
            'insight' => $insight,
            'recommendation' => $recommendation,
            'prediction' => $prediction,
            'dataSparse' => $dataSparse,
        ],
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response(['error' => 'Server error', 'details' => $e->getMessage()], 500);
}
