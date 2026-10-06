<?php
// Analytics for one barber: the numbers behind the charts on the barber app's
// Insights tab.
//
// Kept separate from the endpoint so tests and scripts can build a payload
// without the request plumbing -- including an endpoint file runs it.

declare(strict_types=1);

require_once __DIR__ . '/shop_schedule.php';

const BARBER_ANALYTICS_RANGES = [7, 30, 90];

/**
 * A haircut longer than this is a data artefact, not a slow barber: a session
 * left open overnight, or a completion stamped the next morning. Averaging
 * those in produced a "12 hour average cut" from real rows.
 */
const BARBER_ANALYTICS_MAX_SERVICE_MINUTES = 240;

function analytics_relation_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare('SELECT to_regclass(:name) IS NOT NULL');
    $stmt->execute([':name' => 'public.' . $table]);

    return (bool)$stmt->fetchColumn();
}

/**
 * Resolves the signed-in barber the same way barbers.php does: email first,
 * because a colliding users.user_id must never read someone else's numbers.
 */
function analytics_resolve_barber(PDO $pdo, int $barberId, string $email): array
{
    if ($email !== '') {
        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name FROM barbers
             WHERE lower(email) = lower(?) AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$email]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return ['id' => (int)$row['barber_id'], 'name' => (string)$row['full_name']];
        }
    }

    if ($barberId > 0) {
        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name FROM barbers
             WHERE barber_id = ? AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$barberId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return ['id' => (int)$row['barber_id'], 'name' => (string)$row['full_name']];
        }
    }

    return ['id' => 0, 'name' => ''];
}

/**
 * Every day in the range, including the empty ones.
 *
 * A chart drawn only from days that have rows reads as busier than reality --
 * the quiet days vanish instead of showing as the gaps they were.
 */
function analytics_fill_days(string $from, string $to, array $byDate): array
{
    $out = [];
    $cursor = new DateTimeImmutable($from);
    $end = new DateTimeImmutable($to);

    while ($cursor <= $end) {
        $key = $cursor->format('Y-m-d');
        $row = $byDate[$key] ?? [];
        $out[] = [
            'date' => $key,
            'completed' => (int)($row['completed'] ?? 0),
            'cancelled' => (int)($row['cancelled'] ?? 0),
            'booked' => (int)($row['booked'] ?? 0),
            'walkins' => (int)($row['walkins'] ?? 0),
        ];
        $cursor = $cursor->modify('+1 day');
    }

    return $out;
}

function barber_analytics_payload(PDO $pdo, int $barberId, int $days): array
{
    $days = in_array($days, BARBER_ANALYTICS_RANGES, true) ? $days : 30;

    // Anchored to the shop's own day, not the server's. On a UTC host the
    // Philippine morning is still "yesterday", so a barber opening the app at
    // 7am would have seen today's column missing entirely.
    $shopTz = new DateTimeZone(shop_timezone());
    $tzSql = shop_timezone_sql();
    $to = new DateTimeImmutable('today', $shopTz);
    $from = $to->modify('-' . ($days - 1) . ' days');
    $fromKey = $from->format('Y-m-d');
    $toKey = $to->format('Y-m-d');
    $window = [':barber_id' => $barberId, ':from' => $fromKey, ':to' => $toKey];

    // ---- status mix ---------------------------------------------------------
    $stmt = $pdo->prepare(
        'SELECT status, COUNT(*)::int AS c
         FROM appointments
         WHERE barber_id = :barber_id AND appointment_date BETWEEN :from AND :to
         GROUP BY status'
    );
    $stmt->execute($window);

    $statuses = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $statuses[(string)$row['status']] = (int)$row['c'];
    }

    $completed = $statuses['Completed'] ?? 0;
    $cancelled = $statuses['Cancelled'] ?? 0;
    $noShow = $statuses['NoShow'] ?? 0;
    $booked = array_sum($statuses);
    $openCount = $booked - $completed - $cancelled - $noShow;

    // ---- one row per day ----------------------------------------------------
    $stmt = $pdo->prepare(
        "SELECT appointment_date::text AS d,
                COUNT(*) FILTER (WHERE status = 'Completed')::int AS completed,
                COUNT(*) FILTER (WHERE status IN ('Cancelled', 'NoShow'))::int AS cancelled,
                COUNT(*)::int AS booked
         FROM appointments
         WHERE barber_id = :barber_id AND appointment_date BETWEEN :from AND :to
         GROUP BY appointment_date"
    );
    $stmt->execute($window);

    $byDate = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $byDate[(string)$row['d']] = [
            'completed' => (int)$row['completed'],
            'cancelled' => (int)$row['cancelled'],
            'booked' => (int)$row['booked'],
        ];
    }

    $walkinsServed = 0;
    $walkinValue = 0.0;
    if (analytics_relation_exists($pdo, 'walkin_queue')) {
        $stmt = $pdo->prepare(
            "SELECT DATE(created_at AT TIME ZONE '$tzSql')::text AS d, COUNT(*)::int AS c
             FROM walkin_queue
             WHERE barber_id = :barber_id
               AND DATE(created_at AT TIME ZONE '$tzSql') BETWEEN :from AND :to
               AND status <> 'Cancelled'
             GROUP BY 1"
        );
        $stmt->execute($window);
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $key = (string)$row['d'];
            if (!isset($byDate[$key])) {
                $byDate[$key] = [];
            }
            $byDate[$key]['walkins'] = (int)$row['c'];
            $walkinsServed += (int)$row['c'];
        }

        if (analytics_relation_exists($pdo, 'walkin_service_details')) {
            $stmt = $pdo->prepare(
                "SELECT COALESCE(SUM(wsd.final_price), 0)::float AS v
                 FROM walkin_service_details wsd
                 JOIN walkin_queue wq ON wq.queue_id = wsd.queue_id
                 WHERE wq.barber_id = :barber_id
                   AND DATE(wq.created_at AT TIME ZONE '$tzSql') BETWEEN :from AND :to
                   AND wq.status = 'Completed'"
            );
            $stmt->execute($window);
            $walkinValue = (float)$stmt->fetchColumn();
        }
    }

    // ---- demand by hour and weekday ----------------------------------------
    // Cancelled rows are left out: these two charts answer "when am I wanted",
    // and a cancelled slot was still a slot nobody was cutting hair in.
    $stmt = $pdo->prepare(
        "SELECT EXTRACT(HOUR FROM start_time)::int AS h, COUNT(*)::int AS c
         FROM appointments
         WHERE barber_id = :barber_id AND appointment_date BETWEEN :from AND :to
           AND status NOT IN ('Cancelled', 'NoShow')
         GROUP BY 1 ORDER BY 1"
    );
    $stmt->execute($window);
    $hours = array_map(
        fn($row) => ['hour' => (int)$row['h'], 'count' => (int)$row['c']],
        $stmt->fetchAll(PDO::FETCH_ASSOC)
    );

    $stmt = $pdo->prepare(
        "SELECT EXTRACT(ISODOW FROM appointment_date)::int AS w, COUNT(*)::int AS c
         FROM appointments
         WHERE barber_id = :barber_id AND appointment_date BETWEEN :from AND :to
           AND status NOT IN ('Cancelled', 'NoShow')
         GROUP BY 1 ORDER BY 1"
    );
    $stmt->execute($window);
    $weekdays = array_map(
        fn($row) => ['weekday' => (int)$row['w'], 'count' => (int)$row['c']],
        $stmt->fetchAll(PDO::FETCH_ASSOC)
    );

    // ---- what they actually cut -------------------------------------------
    $stmt = $pdo->prepare(
        "SELECT s.service_name AS name, COUNT(*)::int AS c,
                COALESCE(SUM(ad.final_price), 0)::float AS v
         FROM appointment_details ad
         JOIN appointments a ON a.appointment_id = ad.appointment_id
         JOIN services s ON s.service_id = ad.service_id
         WHERE a.barber_id = :barber_id
           AND a.appointment_date BETWEEN :from AND :to
           AND a.status = 'Completed'
         GROUP BY s.service_name
         ORDER BY c DESC, v DESC
         LIMIT 6"
    );
    $stmt->execute($window);
    $topServices = array_map(
        fn($row) => [
            'name' => (string)$row['name'],
            'count' => (int)$row['c'],
            'value' => round((float)$row['v'], 2),
        ],
        $stmt->fetchAll(PDO::FETCH_ASSOC)
    );

    $stmt = $pdo->prepare(
        "SELECT COALESCE(SUM(ad.final_price), 0)::float
         FROM appointment_details ad
         JOIN appointments a ON a.appointment_id = ad.appointment_id
         WHERE a.barber_id = :barber_id
           AND a.appointment_date BETWEEN :from AND :to
           AND a.status = 'Completed'"
    );
    $stmt->execute($window);
    $appointmentValue = (float)$stmt->fetchColumn();

    // ---- how long a cut actually takes -------------------------------------
    // Measured, not estimated: check-in to completion, minus any pause. Only
    // rows carrying both stamps can answer, so the sample size travels with the
    // number -- an average over two haircuts is not a fact about the barber.
    $stmt = $pdo->prepare(
        "SELECT COUNT(*)::int AS n,
                AVG(EXTRACT(EPOCH FROM (completion_time - checkin_time))
                    - COALESCE(paused_seconds, 0))::float AS secs
         FROM appointments
         WHERE barber_id = :barber_id
           AND appointment_date BETWEEN :from AND :to
           AND status = 'Completed'
           AND checkin_time IS NOT NULL
           AND completion_time IS NOT NULL
           AND completion_time > checkin_time
           AND completion_time - checkin_time
               <= make_interval(mins => :max_minutes)"
    );
    $window['max_minutes'] = BARBER_ANALYTICS_MAX_SERVICE_MINUTES;
    $stmt->execute($window);
    unset($window['max_minutes']);
    $duration = $stmt->fetch(PDO::FETCH_ASSOC) ?: [];
    $measured = (int)($duration['n'] ?? 0);
    $avgMinutes = $measured > 0 && ($duration['secs'] ?? null) !== null
        ? round(((float)$duration['secs']) / 60, 1)
        : null;

    // ---- who comes back ----------------------------------------------------
    $stmt = $pdo->prepare(
        "SELECT COUNT(DISTINCT user_id)::int AS uniques
         FROM appointments
         WHERE barber_id = :barber_id
           AND appointment_date BETWEEN :from AND :to
           AND status = 'Completed'"
    );
    $stmt->execute($window);
    $uniqueCustomers = (int)$stmt->fetchColumn();

    $stmt = $pdo->prepare(
        "SELECT COUNT(*)::int FROM (
            SELECT user_id FROM appointments
            WHERE barber_id = :barber_id
              AND appointment_date BETWEEN :from AND :to
              AND status = 'Completed'
            GROUP BY user_id HAVING COUNT(*) > 1
         ) repeats"
    );
    $stmt->execute($window);
    $repeatCustomers = (int)$stmt->fetchColumn();

    // ---- ratings, all time -------------------------------------------------
    // Deliberately not windowed. Feedback is sparse, and a 30-day slice of it
    // would read "no rating yet" for a barber who has been rated -- worse than
    // a figure labelled as covering everything.
    $ratings = [
        'average' => null,
        'count' => 0,
        'distribution' => ['1' => 0, '2' => 0, '3' => 0, '4' => 0, '5' => 0],
        'recent' => [],
        'windowCount' => 0,
    ];

    if (analytics_relation_exists($pdo, 'barber_feedback')) {
        $stmt = $pdo->prepare(
            'SELECT rating, COUNT(*)::int AS c
             FROM barber_feedback WHERE barber_id = :barber_id
             GROUP BY rating'
        );
        $stmt->execute([':barber_id' => $barberId]);

        $total = 0;
        $weighted = 0;
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $score = (int)$row['rating'];
            $count = (int)$row['c'];
            if ($score < 1 || $score > 5) {
                continue;
            }
            $ratings['distribution'][(string)$score] = $count;
            $total += $count;
            $weighted += $score * $count;
        }

        $ratings['count'] = $total;
        $ratings['average'] = $total > 0 ? round($weighted / $total, 2) : null;

        $stmt = $pdo->prepare(
            "SELECT rating, comment, created_at
             FROM barber_feedback
             WHERE barber_id = :barber_id AND COALESCE(TRIM(comment), '') <> ''
             ORDER BY created_at DESC LIMIT 5"
        );
        $stmt->execute([':barber_id' => $barberId]);
        $ratings['recent'] = array_map(
            fn($row) => [
                'rating' => (int)$row['rating'],
                'comment' => (string)$row['comment'],
                'createdAt' => (string)$row['created_at'],
            ],
            $stmt->fetchAll(PDO::FETCH_ASSOC)
        );

        $stmt = $pdo->prepare(
            "SELECT COUNT(*)::int FROM barber_feedback
             WHERE barber_id = :barber_id
               AND DATE(created_at AT TIME ZONE '$tzSql') BETWEEN :from AND :to"
        );
        $stmt->execute($window);
        $ratings['windowCount'] = (int)$stmt->fetchColumn();
    }

    $finished = $completed + $cancelled + $noShow;

    return [
        'range' => ['days' => $days, 'from' => $fromKey, 'to' => $toKey],
        'totals' => [
            'booked' => $booked,
            'completed' => $completed,
            'cancelled' => $cancelled,
            'noShow' => $noShow,
            'open' => max(0, $openCount),
            // Of the appointments that reached an outcome. Counting still-open
            // ones as failures would punish a barber for having a full
            // afternoon ahead of them.
            'completionRate' => $finished > 0 ? (int)round(($completed / $finished) * 100) : null,
            'walkinsServed' => $walkinsServed,
            'serviceValue' => round($appointmentValue + $walkinValue, 2),
            'avgServiceMinutes' => $avgMinutes,
            'avgServiceSample' => $measured,
            'uniqueCustomers' => $uniqueCustomers,
            'repeatCustomers' => $repeatCustomers,
        ],
        'statusMix' => [
            'Completed' => $completed,
            'Cancelled' => $cancelled,
            'NoShow' => $noShow,
            'Open' => max(0, $openCount),
        ],
        'daily' => analytics_fill_days($fromKey, $toKey, $byDate),
        'hours' => $hours,
        'weekdays' => $weekdays,
        'topServices' => $topServices,
        'ratings' => $ratings,
    ];
}
