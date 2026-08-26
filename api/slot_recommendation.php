<?php
// Deterministic smart-appointment ranking. Scoring weights are constants so
// they can be tuned without changing shop hours, lead time, or booking rules.

declare(strict_types=1);

/**
 * @return array{
 *   weight_barber: int,
 *   weight_barber_single: int,
 *   weight_time_bucket: int,
 *   weight_time_single: int,
 *   weight_weekday: int,
 *   weight_earliest_max: int,
 *   earliest_decay_per_day: int,
 *   weight_gap_fill: int,
 *   weight_orphan_penalty: int,
 *   barber_full_bonus_days: int,
 *   barber_decay_to_zero_days: int,
 *   usual_min_visits: int,
 *   usual_min_share: float,
 *   history_limit: int,
 *   history_months: int,
 *   candidate_cap: int,
 *   alternative_count: int,
 *   shop_hours: list<int>
 * }
 */
function slot_recommendation_config(): array
{
    return [
        // Tuned against scripts/test_slot_recommendation.php (not the first-pass +40/+25/+15/+20).
        'weight_barber' => 28,
        'weight_barber_single' => 8,
        'weight_time_bucket' => 26,
        'weight_time_single' => 20,
        'weight_weekday' => 16,
        'weight_earliest_max' => 24,
        'earliest_decay_per_day' => 4,
        'weight_gap_fill' => 8,
        'weight_orphan_penalty' => 10,
        'barber_full_bonus_days' => 3,
        'barber_decay_to_zero_days' => 10,
        'usual_min_visits' => 2,
        'usual_min_share' => 0.5,
        'history_limit' => 40,
        'history_months' => 18,
        'candidate_cap' => 80,
        'alternative_count' => 2,
        'shop_hours' => [9, 10, 11, 13, 14, 15, 16, 17, 18, 19],
    ];
}

function slot_recommendation_timezone(): DateTimeZone
{
    if (function_exists('shop_timezone')) {
        return new DateTimeZone(shop_timezone());
    }

    return new DateTimeZone('Asia/Manila');
}

function slot_recommendation_weekday(string $date): ?int
{
    $dt = DateTimeImmutable::createFromFormat(
        '!Y-m-d',
        $date,
        slot_recommendation_timezone()
    );

    return $dt === false ? null : (int)$dt->format('w');
}

function slot_recommendation_hour(string $time): ?int
{
    $parts = explode(':', trim($time));
    if ($parts === [] || $parts[0] === '') {
        return null;
    }
    $hour = (int)$parts[0];

    return $hour >= 0 && $hour <= 23 ? $hour : null;
}

/** @return 'morning'|'afternoon'|'evening'|null */
function slot_recommendation_bucket(?int $hour): ?string
{
    if ($hour === null) {
        return null;
    }
    if ($hour >= 9 && $hour <= 11) {
        return 'morning';
    }
    if ($hour >= 13 && $hour <= 16) {
        return 'afternoon';
    }
    if ($hour >= 17 && $hour <= 19) {
        return 'evening';
    }

    return null;
}

function slot_recommendation_buckets_adjacent(string $a, string $b): bool
{
    $pair = [$a, $b];
    sort($pair);

    return $pair === ['afternoon', 'morning'] || $pair === ['afternoon', 'evening'];
}

function slot_recommendation_bucket_label(string $bucket): string
{
    return match ($bucket) {
        'morning' => 'morning',
        'afternoon' => 'afternoon',
        'evening' => 'evening',
        default => $bucket,
    };
}

function slot_recommendation_weekday_label(int $dow): string
{
    return ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][$dow] ?? 'that day';
}

/**
 * @param list<array{barber_id?:int,barberId?:int,appointment_date?:string,slot_date?:string,start_time?:string,slot_time?:string}> $history
 * @param array{barber_id?:int,barber_name?:string,source?:string}|null $ratedFavorite
 * @return array{
 *   visit_count: int,
 *   preferred_barber_id: ?int,
 *   preferred_barber_name: ?string,
 *   preferred_barber_usual: bool,
 *   preferred_bucket: ?string,
 *   preferred_bucket_usual: bool,
 *   preferred_weekday: ?int,
 *   preferred_weekday_usual: bool,
 *   has_history: bool
 * }
 */
function slot_recommendation_build_profile(array $history, ?array $ratedFavorite = null): array
{
    $cfg = slot_recommendation_config();
    $visitCount = count($history);
    $barberCounts = [];
    $bucketCounts = [];
    $weekdayCounts = [];
    $barberNames = [];

    foreach ($history as $row) {
        $barberId = (int)($row['barber_id'] ?? $row['barberId'] ?? 0);
        $date = (string)($row['appointment_date'] ?? $row['slot_date'] ?? '');
        $time = (string)($row['start_time'] ?? $row['slot_time'] ?? '');
        $hour = slot_recommendation_hour($time);
        $bucket = slot_recommendation_bucket($hour);
        $dow = $date !== '' ? slot_recommendation_weekday($date) : null;

        if ($barberId > 0) {
            $barberCounts[$barberId] = ($barberCounts[$barberId] ?? 0) + 1;
            $name = trim((string)($row['barber_name'] ?? $row['barberName'] ?? ''));
            if ($name !== '') {
                $barberNames[$barberId] = $name;
            }
        }
        if ($bucket !== null) {
            $bucketCounts[$bucket] = ($bucketCounts[$bucket] ?? 0) + 1;
        }
        if ($dow !== null) {
            $weekdayCounts[$dow] = ($weekdayCounts[$dow] ?? 0) + 1;
        }
    }

    $modeBarber = slot_recommendation_mode_key($barberCounts);
    $modeBucket = slot_recommendation_mode_key($bucketCounts);
    $modeWeekday = slot_recommendation_mode_key($weekdayCounts);

    $barberUsual = slot_recommendation_is_usual($modeBarber === null ? 0 : (int)$barberCounts[$modeBarber], $visitCount, $cfg);
    $bucketUsual = slot_recommendation_is_usual($modeBucket === null ? 0 : (int)$bucketCounts[$modeBucket], $visitCount, $cfg);
    $weekdayUsual = slot_recommendation_is_usual($modeWeekday === null ? 0 : (int)$weekdayCounts[$modeWeekday], $visitCount, $cfg);

    $preferredBarberId = $modeBarber !== null ? (int)$modeBarber : null;
    $preferredBarberName = $preferredBarberId !== null ? ($barberNames[$preferredBarberId] ?? null) : null;
    $preferredBarberUsual = $barberUsual;

    $ratedId = (int)($ratedFavorite['barber_id'] ?? 0);
    if ($ratedId > 0) {
        $preferredBarberId = $ratedId;
        $preferredBarberName = trim((string)($ratedFavorite['barber_name'] ?? $preferredBarberName ?? '')) ?: $preferredBarberName;
        $preferredBarberUsual = $barberUsual && $modeBarber !== null && (int)$modeBarber === $ratedId
            ? true
            : ($visitCount >= (int)$cfg['usual_min_visits'] && $modeBarber !== null && (int)$modeBarber === $ratedId);
        if ($visitCount >= (int)$cfg['usual_min_visits'] && $modeBarber !== null && (int)$modeBarber === $ratedId) {
            $preferredBarberUsual = true;
        } elseif ($visitCount < (int)$cfg['usual_min_visits']) {
            $preferredBarberUsual = false;
        }
    }

    return [
        'visit_count' => $visitCount,
        'preferred_barber_id' => $preferredBarberId,
        'preferred_barber_name' => $preferredBarberName,
        'preferred_barber_usual' => $preferredBarberUsual,
        'preferred_bucket' => $modeBucket !== null ? (string)$modeBucket : null,
        'preferred_bucket_usual' => $bucketUsual,
        'preferred_weekday' => $modeWeekday !== null ? (int)$modeWeekday : null,
        'preferred_weekday_usual' => $weekdayUsual,
        'has_history' => $visitCount > 0,
    ];
}

function slot_recommendation_is_usual(int $modeCount, int $visitCount, array $cfg): bool
{
    if ($visitCount < (int)$cfg['usual_min_visits'] || $modeCount <= 0) {
        return false;
    }

    return $modeCount >= (int)$cfg['usual_min_visits']
        || ($modeCount / $visitCount) >= (float)$cfg['usual_min_share'];
}

/**
 * @param array<int|string, int> $counts
 * @return int|string|null
 */
function slot_recommendation_mode_key(array $counts): int|string|null
{
    if ($counts === []) {
        return null;
    }
    arsort($counts);
    $topCount = reset($counts);
    $topKey = key($counts);
    $tied = 0;
    foreach ($counts as $count) {
        if ($count === $topCount) {
            $tied++;
        }
    }
    if ($tied > 1) {
        return null;
    }

    return $topKey;
}

function slot_recommendation_days_from(string $fromDate, string $toDate): int
{
    $tz = slot_recommendation_timezone();
    $from = DateTimeImmutable::createFromFormat('!Y-m-d', $fromDate, $tz);
    $to = DateTimeImmutable::createFromFormat('!Y-m-d', $toDate, $tz);
    if ($from === false || $to === false) {
        return 0;
    }

    return (int)$from->diff($to)->format('%r%a');
}

/**
 * @param list<int> $availableHours
 * @param list<int> $shopHours
 * @return array{gap_fill: bool, orphan: bool}
 */
function slot_recommendation_gap_flags(int $hour, array $availableHours, array $shopHours, bool $occupancyKnown): array
{
    if (!$occupancyKnown) {
        return ['gap_fill' => false, 'orphan' => false];
    }

    $shopHours = array_values(array_unique($shopHours));
    sort($shopHours);
    $index = array_search($hour, $shopHours, true);
    if ($index === false) {
        return ['gap_fill' => false, 'orphan' => false];
    }

    $prev = $index > 0 ? $shopHours[$index - 1] : null;
    $next = $index < count($shopHours) - 1 ? $shopHours[$index + 1] : null;
    $avail = array_fill_keys($availableHours, true);
    $prevOpen = $prev !== null && isset($avail[$prev]);
    $nextOpen = $next !== null && isset($avail[$next]);

    return [
        'gap_fill' => $prev !== null && $next !== null && !$prevOpen && !$nextOpen,
        'orphan' => $prev !== null && $next !== null && $prevOpen && $nextOpen,
    ];
}

function slot_recommendation_barber_weight(array $profile, array $cfg): int
{
    if (empty($profile['preferred_barber_id'])) {
        return 0;
    }
    if (!empty($profile['preferred_barber_usual'])) {
        return (int)$cfg['weight_barber'];
    }
    if ((int)$profile['visit_count'] === 1) {
        return (int)$cfg['weight_barber_single'];
    }

    return 0;
}

function slot_recommendation_time_weight(array $profile, array $cfg): int
{
    if (empty($profile['preferred_bucket'])) {
        return 0;
    }
    if (!empty($profile['preferred_bucket_usual'])) {
        return (int)$cfg['weight_time_bucket'];
    }
    if ((int)$profile['visit_count'] === 1) {
        return (int)$cfg['weight_time_single'];
    }

    return 0;
}

function slot_recommendation_weekday_weight(array $profile, array $cfg): int
{
    if ($profile['preferred_weekday'] === null) {
        return 0;
    }
    if (!empty($profile['preferred_weekday_usual'])) {
        return (int)$cfg['weight_weekday'];
    }

    return 0;
}

function slot_recommendation_barber_decay_multiplier(int $daysAfterEarliest, array $cfg): float
{
    $full = (int)$cfg['barber_full_bonus_days'];
    $zero = (int)$cfg['barber_decay_to_zero_days'];
    if ($daysAfterEarliest <= $full) {
        return 1.0;
    }
    if ($daysAfterEarliest >= $zero || $zero <= $full) {
        return 0.0;
    }

    return max(0.0, ($zero - $daysAfterEarliest) / ($zero - $full));
}

/**
 * @param list<array<string, mixed>> $candidates
 * @param array<string, list<int>> $dayAvailableHours  key: "{barberId}|{Y-m-d}"
 * @param array<string, true> $knownOccupancyDays  days where neighbor hours are known
 * @return array{
 *   ranked: list<array<string, mixed>>,
 *   primary: ?array<string, mixed>,
 *   alternatives: list<array<string, mixed>>
 * }
 */
function slot_recommendation_rank(
    array $candidates,
    array $profile,
    array $dayAvailableHours,
    string $earliestDate,
    array $knownOccupancyDays = []
): array {
    $cfg = slot_recommendation_config();
    $shopHours = $cfg['shop_hours'];
    $barberWeight = slot_recommendation_barber_weight($profile, $cfg);
    $timeWeight = slot_recommendation_time_weight($profile, $cfg);
    $weekdayWeight = slot_recommendation_weekday_weight($profile, $cfg);
    $preferredBarber = (int)($profile['preferred_barber_id'] ?? 0);
    $preferredBucket = $profile['preferred_bucket'] !== null ? (string)$profile['preferred_bucket'] : '';
    $preferredWeekday = $profile['preferred_weekday'] ?? null;

    $scored = [];
    foreach ($candidates as $candidate) {
        $date = (string)($candidate['slot_date'] ?? $candidate['slotDate'] ?? '');
        $time = (string)($candidate['slot_time'] ?? $candidate['slotTime'] ?? '');
        $barberId = (int)($candidate['barber_id'] ?? $candidate['barberID'] ?? 0);
        $hour = slot_recommendation_hour($time);
        $bucket = slot_recommendation_bucket($hour);
        $dow = $date !== '' ? slot_recommendation_weekday($date) : null;
        if ($date === '' || $time === '' || $barberId <= 0 || $hour === null) {
            continue;
        }

        $daysOut = max(0, slot_recommendation_days_from($earliestDate, $date));
        $earliestScore = max(0, (int)$cfg['weight_earliest_max'] - ($daysOut * (int)$cfg['earliest_decay_per_day']));

        $matchedBarber = $preferredBarber > 0 && $barberId === $preferredBarber;
        $barberScore = 0;
        if ($matchedBarber && $barberWeight > 0) {
            $barberScore = (int)round($barberWeight * slot_recommendation_barber_decay_multiplier($daysOut, $cfg));
        }

        $matchedTime = $preferredBucket !== '' && $bucket === $preferredBucket;
        $adjacentTime = $preferredBucket !== '' && $bucket !== null && $bucket !== $preferredBucket
            && slot_recommendation_buckets_adjacent($preferredBucket, $bucket);
        $timeScore = 0;
        if ($matchedTime && $timeWeight > 0) {
            $timeScore = $timeWeight;
        } elseif ($adjacentTime && $timeWeight > 0) {
            $timeScore = (int)floor($timeWeight * 10 / 26);
        }

        $matchedWeekday = $preferredWeekday !== null && $dow !== null && (int)$dow === (int)$preferredWeekday;
        $weekdayScore = ($matchedWeekday && $weekdayWeight > 0) ? $weekdayWeight : 0;

        $dayKey = $barberId . '|' . $date;
        $occupancyKnown = !empty($profile['has_history']) && isset($knownOccupancyDays[$dayKey]);
        $flags = slot_recommendation_gap_flags(
            $hour,
            $dayAvailableHours[$dayKey] ?? [$hour],
            $shopHours,
            $occupancyKnown
        );
        $gapScore = $flags['gap_fill'] ? (int)$cfg['weight_gap_fill'] : 0;
        $orphanScore = $flags['orphan'] ? -(int)$cfg['weight_orphan_penalty'] : 0;

        $total = $barberScore + $timeScore + $weekdayScore + $earliestScore + $gapScore + $orphanScore;
        $reasonMeta = slot_recommendation_reason(
            $profile,
            [
                'matched_barber' => $matchedBarber && $barberScore > 0,
                'matched_time' => $matchedTime && $timeScore > 0,
                'matched_weekday' => $matchedWeekday && $weekdayScore > 0,
                'gap_fill' => $flags['gap_fill'],
            ]
        );

        $scored[] = array_merge($candidate, [
            'barber_id' => $barberId,
            'slot_date' => $date,
            'slot_time' => $time,
            'rank_score' => $total,
            'score_barber' => $barberScore,
            'score_time' => $timeScore,
            'score_weekday' => $weekdayScore,
            'score_earliest' => $earliestScore,
            'score_gap' => $gapScore + $orphanScore,
            'reason_code' => $reasonMeta['code'],
            'suggestionReason' => $reasonMeta['text'],
            'isFallback' => $reasonMeta['code'] === 'earliest',
            'time_bucket' => $bucket,
            'weekday' => $dow,
        ]);
    }

    usort($scored, static function (array $a, array $b): int {
        $scoreCmp = ($b['rank_score'] <=> $a['rank_score']);
        if ($scoreCmp !== 0) {
            return $scoreCmp;
        }
        $dateCmp = strcmp((string)$a['slot_date'], (string)$b['slot_date']);
        if ($dateCmp !== 0) {
            return $dateCmp;
        }
        $timeCmp = strcmp((string)$a['slot_time'], (string)$b['slot_time']);
        if ($timeCmp !== 0) {
            return $timeCmp;
        }

        return ((int)$a['barber_id']) <=> ((int)$b['barber_id']);
    });

    $primary = $scored[0] ?? null;
    $alternatives = $primary === null
        ? []
        : slot_recommendation_pick_alternatives($scored, $primary, (int)$cfg['alternative_count']);

    return [
        'ranked' => $scored,
        'primary' => $primary,
        'alternatives' => $alternatives,
    ];
}

/**
 * @param array{matched_barber: bool, matched_time: bool, matched_weekday: bool, gap_fill: bool} $matched
 * @return array{code: string, text: string}
 */
function slot_recommendation_reason(array $profile, array $matched): array
{
    $usualBarber = !empty($profile['preferred_barber_usual']) && !empty($matched['matched_barber']);
    $usualTime = !empty($profile['preferred_bucket_usual']) && !empty($matched['matched_time']);
    $usualDay = !empty($profile['preferred_weekday_usual']) && !empty($matched['matched_weekday']);
    $lastTime = (int)($profile['visit_count'] ?? 0) === 1 && !empty($matched['matched_time']);
    $lastBarber = (int)($profile['visit_count'] ?? 0) === 1 && !empty($matched['matched_barber']);
    $bucket = (string)($profile['preferred_bucket'] ?? '');
    $bucketLabel = $bucket !== '' ? slot_recommendation_bucket_label($bucket) : '';
    $dayLabel = isset($profile['preferred_weekday']) && $profile['preferred_weekday'] !== null
        ? slot_recommendation_weekday_label((int)$profile['preferred_weekday'])
        : '';

    if ($usualBarber && $usualTime) {
        return [
            'code' => 'usual_barber_and_time',
            'text' => 'Recommended because it matches your usual barber and ' . $bucketLabel . ' booking time.',
        ];
    }
    if ($usualTime) {
        return [
            'code' => 'usual_time',
            'text' => 'Recommended because it matches your usual ' . $bucketLabel . ' booking time.',
        ];
    }
    if ($usualDay) {
        return [
            'code' => 'usual_day',
            'text' => 'Recommended because it matches your usual ' . $dayLabel . ' visits.',
        ];
    }
    if ($usualBarber) {
        return [
            'code' => 'usual_barber',
            'text' => 'Recommended because it is with your usual barber.',
        ];
    }
    if ($lastTime && $lastBarber) {
        return [
            'code' => 'last_time',
            'text' => 'Recommended because it matches your last ' . $bucketLabel . ' appointment.',
        ];
    }
    if ($lastTime) {
        return [
            'code' => 'last_time',
            'text' => 'Recommended because it matches your last ' . $bucketLabel . ' appointment.',
        ];
    }
    if ($lastBarber) {
        return [
            'code' => 'last_barber',
            'text' => 'Recommended because it is with the barber from your last appointment.',
        ];
    }
    if (!empty($matched['gap_fill']) && !empty($profile['has_history']) && empty($matched['matched_barber']) && empty($matched['matched_time']) && empty($matched['matched_weekday'])) {
        return [
            'code' => 'gap_fill',
            'text' => 'Recommended because it fills an open hour in the schedule.',
        ];
    }

    return [
        'code' => 'earliest',
        'text' => 'Recommended because it is the earliest suitable appointment available.',
    ];
}

/**
 * @param list<array<string, mixed>> $ranked
 * @return list<array<string, mixed>>
 */
function slot_recommendation_pick_alternatives(array $ranked, array $primary, int $limit): array
{
    $picked = [];
    $primaryKey = slot_recommendation_candidate_key($primary);

    $scoreDiversity = static function (array $slot, array $primary) use ($picked): int {
        $score = 0;
        if ((string)$slot['slot_date'] !== (string)$primary['slot_date']) {
            $score += 3;
        }
        if (($slot['time_bucket'] ?? '') !== ($primary['time_bucket'] ?? '')) {
            $score += 2;
        }
        if ((int)$slot['barber_id'] !== (int)$primary['barber_id']) {
            $score += 1;
        }
        foreach ($picked as $existing) {
            if ((string)$slot['slot_date'] === (string)$existing['slot_date']
                && ($slot['time_bucket'] ?? '') === ($existing['time_bucket'] ?? '')
                && (int)$slot['barber_id'] === (int)$existing['barber_id']) {
                $score -= 2;
            }
        }

        return $score;
    };

    $remaining = [];
    foreach ($ranked as $slot) {
        if (slot_recommendation_candidate_key($slot) === $primaryKey) {
            continue;
        }
        $remaining[] = $slot;
    }

    while (count($picked) < $limit && $remaining !== []) {
        $bestIndex = 0;
        $bestDiv = -999;
        foreach ($remaining as $index => $slot) {
            $div = $scoreDiversity($slot, $primary);
            if ($div > $bestDiv) {
                $bestDiv = $div;
                $bestIndex = $index;
            }
        }
        $picked[] = $remaining[$bestIndex];
        array_splice($remaining, $bestIndex, 1);
    }

    return $picked;
}

function slot_recommendation_candidate_key(array $slot): string
{
    return (int)($slot['barber_id'] ?? $slot['barberID'] ?? 0)
        . '|' . (string)($slot['slot_date'] ?? $slot['slotDate'] ?? '')
        . '|' . (string)($slot['slot_time'] ?? $slot['slotTime'] ?? '');
}

/**
 * @param list<array<string, mixed>> $rows
 * @return list<array<string, mixed>>
 */
function slot_recommendation_dedupe_candidates(array $rows, int $cap): array
{
    $seen = [];
    $out = [];
    foreach ($rows as $row) {
        $key = slot_recommendation_candidate_key($row);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $out[] = $row;
        if (count($out) >= $cap) {
            break;
        }
    }

    return $out;
}

/**
 * Load qualifying appointment history for ranking.
 *
 * @return list<array<string, mixed>>
 */
function slot_recommendation_load_history(PDO $pdo, int $userId): array
{
    $cfg = slot_recommendation_config();
    $months = (int)$cfg['history_months'];
    $limit = (int)$cfg['history_limit'];
    $stmt = $pdo->prepare(
        "SELECT a.barber_id, b.full_name AS barber_name, a.appointment_date, a.start_time
           FROM appointments a
           JOIN barbers b ON b.barber_id = a.barber_id
          WHERE a.user_id = :user_id
            AND a.status IN ('Completed', 'Scheduled', 'CheckedIn', 'InProgress')
            AND a.appointment_date >= (CURRENT_DATE - CAST(:lookback AS interval))
          ORDER BY a.appointment_date DESC, a.start_time DESC
          LIMIT :lim"
    );
    $stmt->bindValue(':user_id', $userId, PDO::PARAM_INT);
    $stmt->bindValue(':lookback', $months . ' months');
    $stmt->bindValue(':lim', $limit, PDO::PARAM_INT);
    $stmt->execute();

    return $stmt->fetchAll(PDO::FETCH_ASSOC) ?: [];
}

/**
 * @return array{barber_id: int, barber_name: string, source: string}|null
 */
function slot_recommendation_load_rated_favorite(PDO $pdo, int $userId): ?array
{
    try {
        $stmt = $pdo->prepare(
            "SELECT b.barber_id, b.full_name
               FROM barber_feedback bf
               JOIN barbers b ON b.barber_id = bf.barber_id
              WHERE bf.user_id = :user_id
                AND b.is_active = TRUE
                AND b.barber_channel = 'appointment'
              GROUP BY b.barber_id, b.full_name
              ORDER BY AVG(bf.rating) DESC, COUNT(*) DESC
              LIMIT 1"
        );
        $stmt->execute([':user_id' => $userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            return null;
        }

        return [
            'barber_id' => (int)$row['barber_id'],
            'barber_name' => (string)$row['full_name'],
            'source' => 'customer_ratings',
        ];
    } catch (Throwable $e) {
        return null;
    }
}

/**
 * @param list<array<string, mixed>> $slots
 * @return array<string, list<int>>
 */
function slot_recommendation_index_available_hours(array $slots): array
{
    $index = [];
    foreach ($slots as $slot) {
        $barberId = (int)($slot['barber_id'] ?? $slot['barberID'] ?? 0);
        $date = (string)($slot['slot_date'] ?? $slot['slotDate'] ?? '');
        $hour = slot_recommendation_hour((string)($slot['slot_time'] ?? $slot['slotTime'] ?? ''));
        if ($barberId <= 0 || $date === '' || $hour === null) {
            continue;
        }
        $key = $barberId . '|' . $date;
        $index[$key] ??= [];
        if (!in_array($hour, $index[$key], true)) {
            $index[$key][] = $hour;
        }
    }

    return $index;
}

/**
 * Shape a ranked slot for the existing Flutter suggestion payload.
 *
 * @param array<string, mixed> $slot
 * @return array<string, mixed>
 */
function slot_recommendation_public_payload(array $slot, int $leadHours): array
{
    return [
        'barberID' => (int)($slot['barber_id'] ?? $slot['barberID'] ?? 0),
        'barberName' => (string)($slot['barber_name'] ?? $slot['barberName'] ?? 'Barber'),
        'specialty' => $slot['specialty'] ?? null,
        'slotDate' => (string)($slot['slot_date'] ?? $slot['slotDate'] ?? ''),
        'slotTime' => (string)($slot['slot_time'] ?? $slot['slotTime'] ?? ''),
        'availableCount' => (int)($slot['available_count'] ?? $slot['availableCount'] ?? 0),
        'suggestionReason' => (string)($slot['suggestionReason'] ?? ''),
        'reasonCode' => (string)($slot['reason_code'] ?? 'earliest'),
        'rankScore' => (int)($slot['rank_score'] ?? 0),
        'leadHours' => $leadHours,
        'isFallback' => !empty($slot['isFallback']),
    ];
}
