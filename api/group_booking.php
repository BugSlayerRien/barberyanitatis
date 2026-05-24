<?php
// Group booking helpers — up to 5 consecutive slots per booking unit.

declare(strict_types=1);

require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/appointment_notifications.php';
require_once __DIR__ . '/schema_cache.php';

function ensure_group_booking_schema(PDO $pdo): void
{
    static $done = false;
    if ($done || !schema_cache_should_run('group_booking_schema', 86400)) {
        return;
    }

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_groups (
            group_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            user_id BIGINT NOT NULL,
            primary_barber_id BIGINT NOT NULL,
            people_count INT NOT NULL CHECK (people_count >= 1 AND people_count <= 5),
            slot_date DATE NOT NULL,
            first_slot_time TIME NOT NULL,
            total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'PendingPayment',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_groups_user FOREIGN KEY (user_id) REFERENCES users(user_id),
            CONSTRAINT fk_appointment_groups_barber FOREIGN KEY (primary_barber_id) REFERENCES barbers(barber_id)
        )"
    );

    $pdo->exec(
        'ALTER TABLE appointments ADD COLUMN IF NOT EXISTS booking_group_id BIGINT'
    );

    $pdo->exec(
        'DO $do$
         BEGIN
             IF NOT EXISTS (
                 SELECT 1 FROM pg_constraint WHERE conname = \'fk_appointments_booking_group\'
             ) THEN
                 ALTER TABLE appointments
                     ADD CONSTRAINT fk_appointments_booking_group
                     FOREIGN KEY (booking_group_id) REFERENCES appointment_groups(group_id) ON DELETE SET NULL;
             END IF;
         END $do$'
    );
    $pdo->exec(
        "ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS group_member_name TEXT"
    );
    $pdo->exec(
        "ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS group_sequence INT"
    );

    schema_cache_done('group_booking_schema');
    $done = true;
}

/**
 * @return array{people_count: int, total_amount: float, status: string}|null
 */
function fetch_booking_group_meta(PDO $pdo, int $groupId): ?array
{
    ensure_group_booking_schema($pdo);
    if ($groupId <= 0) {
        return null;
    }

    $stmt = $pdo->prepare(
        'SELECT people_count, total_amount, status
         FROM appointment_groups
         WHERE group_id = :group_id
         LIMIT 1'
    );
    $stmt->execute([':group_id' => $groupId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }

    return [
        'people_count' => (int)($row['people_count'] ?? 0),
        'total_amount' => (float)($row['total_amount'] ?? 0),
        'status' => (string)($row['status'] ?? ''),
    ];
}

/**
 * End of the booking window for display (last slot start + service duration).
 *
 * @param array<string, mixed> $lastMember
 */
function booking_group_display_end_time(array $lastMember): string
{
    $start = (string)($lastMember['start_time'] ?? $lastMember['startTime'] ?? '');
    if ($start === '') {
        return (string)($lastMember['end_time'] ?? $lastMember['endTime'] ?? '');
    }

    return shop_add_minutes_to_time($start, shop_appointment_duration_minutes());
}

/**
 * @return string[]
 */
function group_slot_time_order(): array
{
    return shop_default_slot_times();
}

function slot_time_add_hours(string $time, int $hours): string
{
    $parts = explode(':', $time);
    $hour = (int)($parts[0] ?? 0);
    return sprintf('%02d:00:00', $hour + $hours);
}

/**
 * @return array<string, string> time => status
 */
function fetch_barber_slot_map(PDO $pdo, int $barberId, string $slotDate): array
{
    $stmt = $pdo->prepare(
        "SELECT ts.slot_time, ts.status
         FROM time_slots ts
         WHERE ts.barber_id = :barber_id
           AND ts.slot_date = :slot_date
           AND EXTRACT(MINUTE FROM ts.slot_time) = 0"
    );
    $stmt->execute([':barber_id' => $barberId, ':slot_date' => $slotDate]);
    $map = [];
    foreach ($stmt->fetchAll() as $row) {
        $time = shop_normalize_slot_time((string)$row['slot_time']);
        if ($time === null || shop_is_break_slot_time($time)) {
            continue;
        }
        $map[$time] = (string)$row['status'];
    }

    $overlapStmt = $pdo->prepare(
        "SELECT start_time, COUNT(*) AS booked_count
         FROM appointments
         WHERE barber_id = :barber_id
           AND appointment_date = :slot_date
           AND status IN ('Scheduled', 'CheckedIn', 'InProgress', 'Completed')
         GROUP BY start_time"
    );
    $overlapStmt->execute([':barber_id' => $barberId, ':slot_date' => $slotDate]);
    foreach ($overlapStmt->fetchAll() as $row) {
        $time = shop_normalize_slot_time((string)$row['start_time']);
        if ($time !== null) {
            $map[$time] = 'Booked';
        }
    }

    return $map;
}

function is_slot_bookable_for_group(string $slotDate, string $slotTime, array $slotMap): bool
{
    if (shop_is_break_slot_time($slotTime)) {
        return false;
    }
    if (!shop_is_future_slot($slotDate, $slotTime)) {
        return false;
    }

    $status = strtolower($slotMap[$slotTime] ?? 'available');

    return $status === 'available';
}

/**
 * @return list<array{slotTime:string}>
 */
function find_consecutive_runs(array $slotMap, string $slotDate, int $count): array
{
    $times = group_slot_time_order();
    $runs = [];

    for ($start = 0, $len = count($times); $start <= $len - $count; $start++) {
        $segment = [];
        $ok = true;
        for ($offset = 0; $offset < $count; $offset++) {
            $time = $times[$start + $offset];
            if (!is_slot_bookable_for_group($slotDate, $time, $slotMap)) {
                $ok = false;
                break;
            }
            $segment[] = ['slotTime' => $time];
        }
        if ($ok) {
            $runs[] = $segment;
        }
    }

    return $runs;
}

/**
 * @return list<int>
 */
function fetch_appointment_barber_ids(PDO $pdo): array
{
    $appointmentFilter = barber_channel_filter_sql('appointment', 'barber_channel');
    $stmt = $pdo->query(
        "SELECT barber_id FROM barbers WHERE is_active = TRUE{$appointmentFilter} ORDER BY full_name"
    );

    return array_map(static fn(array $row): int => (int)$row['barber_id'], $stmt->fetchAll());
}

/**
 * @param array<int, array<string, string>> $barberMaps
 * @return list<array{barberID:int, slots:list<array{slotTime:string, barberID:int}>}>
 */
function find_split_barber_option(array $barberMaps, string $slotDate, int $count, array $barberNames): ?array
{
    $times = group_slot_time_order();
    foreach ($times as $time) {
        if (!shop_is_future_slot($slotDate, $time)) {
            continue;
        }

        $assignments = [];
        $used = [];
        foreach ($barberMaps as $barberId => $map) {
            if (is_slot_bookable_for_group($slotDate, $time, $map)) {
                $assignments[] = ['slotTime' => $time, 'barberID' => $barberId];
                $used[$barberId] = true;
                if (count($assignments) === $count) {
                    break;
                }
            }
        }

        if (count($assignments) === $count) {
            return [
                'type' => 'split_barbers',
                'slotDate' => $slotDate,
                'description' => 'Same start time (' . substr($time, 0, 5) . ') across ' . $count
                    . ' appointment barbers on ' . $slotDate . '.',
                'slots' => $assignments,
                'barberNames' => $barberNames,
            ];
        }
    }

    return null;
}

/**
 * @return array<string, mixed>
 */
function find_group_booking_options(PDO $pdo, int $preferredBarberId, int $peopleCount, ?string $preferredDate): array
{
    $windowEnd = shop_window_end_date();
    $dates = [];
    $start = shop_earliest_bookable_slot_start()->setTime(0, 0);
    $end = DateTimeImmutable::createFromFormat('Y-m-d', $windowEnd, new DateTimeZone(shop_timezone()));
    if ($end === false) {
        $end = $start;
    }

    for ($cursor = $start; $cursor <= $end; $cursor = $cursor->modify('+1 day')) {
        $dates[] = $cursor->format('Y-m-d');
    }

    if ($preferredDate !== null && in_array($preferredDate, $dates, true)) {
        $dates = array_values(array_unique(array_merge([$preferredDate], $dates)));
    }

    $barberIds = $preferredBarberId > 0
        ? [$preferredBarberId]
        : fetch_appointment_barber_ids($pdo);

    if ($barberIds === []) {
        return [
            'status' => 'unavailable',
            'reason' => 'No appointment barbers are configured.',
            'options' => [],
            'requiresConfirmation' => true,
        ];
    }

    $nameStmt = $pdo->prepare('SELECT barber_id, full_name FROM barbers WHERE barber_id = :id');
    $barberNames = [];
    foreach ($barberIds as $id) {
        $nameStmt->execute([':id' => $id]);
        $row = $nameStmt->fetch();
        $barberNames[$id] = (string)($row['full_name'] ?? 'Barber');
    }

    $options = [];

    // Priority 1 & 2: consecutive runs, preferred barber first, earliest date/time.
    foreach ($dates as $slotDate) {
        foreach ($barberIds as $barberId) {
            $map = fetch_barber_slot_map($pdo, $barberId, $slotDate);
            $runs = find_consecutive_runs($map, $slotDate, $peopleCount);
            if ($runs === []) {
                continue;
            }

            $first = $runs[0];
            $options[] = [
                'type' => $slotDate === ($preferredDate ?? $slotDate) ? 'exact' : 'alternate_day',
                'barberID' => $barberId,
                'barberName' => $barberNames[$barberId] ?? 'Barber',
                'slotDate' => $slotDate,
                'slots' => array_map(
                    static fn(array $slot, int $index): array => [
                        'slotTime' => $slot['slotTime'],
                        'barberID' => $barberId,
                        'sequence' => $index + 1,
                    ],
                    $first,
                    array_keys($first)
                ),
                'description' => $peopleCount . ' consecutive hour(s) with '
                    . ($barberNames[$barberId] ?? 'barber')
                    . ' on ' . $slotDate . ' starting ' . substr($first[0]['slotTime'], 0, 5) . '.',
            ];

            return [
                'status' => 'exact',
                'reason' => null,
                'options' => $options,
                'requiresConfirmation' => true,
            ];
        }
    }

    // Priority 3: split across barbers (same time).
    foreach ($dates as $slotDate) {
        $maps = [];
        foreach (fetch_appointment_barber_ids($pdo) as $barberId) {
            $maps[$barberId] = fetch_barber_slot_map($pdo, $barberId, $slotDate);
        }
        $split = find_split_barber_option($maps, $slotDate, $peopleCount, $barberNames);
        if ($split !== null) {
            $options[] = $split;

            return [
                'status' => 'split_barbers',
                'reason' => 'No single barber has ' . $peopleCount . ' consecutive hours. '
                    . 'You can book the same time with different barbers.',
                'options' => $options,
                'requiresConfirmation' => true,
            ];
        }
    }

    // Priority 4: largest consecutive block today.
    $today = shop_today();
    $bestPartial = null;
    foreach ($barberIds as $barberId) {
        $map = fetch_barber_slot_map($pdo, $barberId, $today);
        for ($size = $peopleCount - 1; $size >= 1; $size--) {
            $runs = find_consecutive_runs($map, $today, $size);
            if ($runs !== []) {
                $bestPartial = [
                    'type' => 'partial',
                    'barberID' => $barberId,
                    'barberName' => $barberNames[$barberId] ?? 'Barber',
                    'slotDate' => $today,
                    'requestedCount' => $peopleCount,
                    'availableCount' => $size,
                    'slots' => array_map(
                        static fn(array $slot, int $index): array => [
                            'slotTime' => $slot['slotTime'],
                            'barberID' => $barberId,
                            'sequence' => $index + 1,
                        ],
                        $runs[0],
                        array_keys($runs[0])
                    ),
                    'description' => 'Only ' . $size . ' consecutive hour(s) available today with '
                        . ($barberNames[$barberId] ?? 'barber')
                        . ' (requested ' . $peopleCount . ').',
                ];
                break 2;
            }
        }
    }

    if ($bestPartial !== null) {
        $options[] = $bestPartial;

        return [
            'status' => 'partial',
            'reason' => 'Cannot fit all ' . $peopleCount . ' people in one consecutive block in the next '
                . shop_booking_window_days() . ' days. '
                . 'Largest block today has ' . $bestPartial['availableCount'] . ' hour(s). '
                . 'Reduce group size or pick another day — partial groups are not auto-booked.',
            'options' => $options,
            'requiresConfirmation' => true,
        ];
    }

    return [
        'status' => 'unavailable',
        'reason' => 'No consecutive availability for ' . $peopleCount . ' people in the next '
            . shop_booking_window_days() . ' days.',
        'options' => [],
        'requiresConfirmation' => true,
    ];
}

/**
 * First slot uses the booking customer's name; additional guests need no separate names.
 *
 * @param list<string> $memberNames
 * @return list<string>
 */
function booking_customer_member_names(PDO $pdo, int $userId, int $peopleCount, array $memberNames): array
{
    $stmt = $pdo->prepare('SELECT full_name FROM users WHERE user_id = :id LIMIT 1');
    $stmt->execute([':id' => $userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $userName = trim((string)($row['full_name'] ?? ''));
    if ($userName === '') {
        $userName = trim((string)($memberNames[0] ?? ''));
    }
    if ($userName === '') {
        $userName = 'You';
    }

    $names = [];
    for ($i = 0; $i < $peopleCount; $i++) {
        $names[] = $i === 0 ? $userName : '';
    }

    return $names;
}

function user_has_active_booking_unit(PDO $pdo, int $userId): bool
{
    $stmt = $pdo->prepare(
        "SELECT COUNT(DISTINCT COALESCE(booking_group_id::text, 'single-' || appointment_id::text))
         FROM appointments
         WHERE user_id = :user_id
           AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')"
    );
    $stmt->execute([':user_id' => $userId]);

    return (int)$stmt->fetchColumn() > 0;
}

/**
 * @param list<array{slotTime:string, barberID?:int, sequence?:int}> $slots
 * @param list<string> $memberNames
 * @param list<array{serviceID:int, variantID:int, finalPrice?:mixed}> $items
 * @return array<string, mixed>
 */
function create_group_booking(
    PDO $pdo,
    int $userId,
    int $primaryBarberId,
    string $slotDate,
    array $slots,
    array $memberNames,
    array $items,
    bool $allowPartial = false
): array {
    ensure_group_booking_schema($pdo);

    $peopleCount = count($slots);
    if ($peopleCount < 1 || $peopleCount > 5) {
        json_response(['error' => 'Group size must be between 1 and 5'], 422);
    }

    $memberNames = booking_customer_member_names($pdo, $userId, $peopleCount, $memberNames);

    if (user_has_active_booking_unit($pdo, $userId)) {
        json_response(['error' => 'You already have an active appointment or group booking.'], 409);
    }

    if (!$allowPartial) {
        $requested = (int)($GLOBALS['group_booking_requested_count'] ?? $peopleCount);
        if ($requested > $peopleCount) {
            json_response([
                'error' => 'Partial group booking requires explicit confirmation.',
                'requiresConfirmation' => true,
            ], 409);
        }
    }

    $validatedItems = [];
    $serviceInfoStmt = $pdo->prepare(
        'SELECT service_id, base_price FROM services WHERE service_id = :service_id AND is_active = TRUE'
    );
    foreach ($items as $item) {
        $serviceId = (int)($item['serviceID'] ?? 0);
        $variantId = (int)($item['variantID'] ?? 0);
        if ($serviceId <= 0 || $variantId <= 0) {
            continue;
        }
        $serviceInfoStmt->execute([':service_id' => $serviceId]);
        $serviceInfo = $serviceInfoStmt->fetch();
        if (!$serviceInfo) {
            json_response(['error' => 'Invalid service'], 422);
        }
        $price = $item['finalPrice'] ?? $serviceInfo['base_price'];
        $validatedItems[] = [
            'serviceID' => $serviceId,
            'variantID' => $variantId,
            'finalPrice' => $price,
            'selectedView' => $item['selectedView'] ?? 'Front',
            'specialInstructions' => $item['specialInstructions'] ?? '',
        ];
    }

    if ($validatedItems === []) {
        json_response(['error' => 'No valid services for group booking'], 422);
    }

    $perPersonPrice = (float)$validatedItems[0]['finalPrice'];
    $totalAmount = round($perPersonPrice * $peopleCount, 2);

    $firstTime = shop_normalize_slot_time((string)$slots[0]['slotTime']);
    if ($firstTime === null) {
        json_response(['error' => 'Invalid first slot time'], 422);
    }

    foreach ($slots as $slot) {
        $time = shop_normalize_slot_time((string)$slot['slotTime']);
        $barberId = (int)($slot['barberID'] ?? $primaryBarberId);
        if ($time === null || $barberId <= 0) {
            json_response(['error' => 'Invalid slot in group'], 422);
        }
        if (!shop_is_future_slot($slotDate, $time)) {
            json_response(['error' => 'One or more slots are no longer bookable (1-hour minimum notice).'], 422);
        }
        $map = fetch_barber_slot_map($pdo, $barberId, $slotDate);
        if (!is_slot_bookable_for_group($slotDate, $time, $map)) {
            json_response(['error' => 'Slot ' . substr($time, 0, 5) . ' is no longer available.'], 409);
        }
    }

    $pdo->beginTransaction();

    try {
        $groupStmt = $pdo->prepare(
            "INSERT INTO appointment_groups (user_id, primary_barber_id, people_count, slot_date, first_slot_time, total_amount, status)
             VALUES (:user_id, :barber_id, :people_count, :slot_date, :first_time, :total, 'PendingPayment')
             RETURNING group_id"
        );
        $groupStmt->execute([
            ':user_id' => $userId,
            ':barber_id' => $primaryBarberId,
            ':people_count' => $peopleCount,
            ':slot_date' => $slotDate,
            ':first_time' => $firstTime,
            ':total' => $totalAmount,
        ]);
        $groupId = (int)$groupStmt->fetchColumn();

        $duration = shop_appointment_duration_minutes();
        $appointmentIds = [];
        $bookingCodes = [];

        foreach ($slots as $index => $slot) {
            $time = shop_normalize_slot_time((string)$slot['slotTime']);
            $barberId = (int)($slot['barberID'] ?? $primaryBarberId);
            $endTime = shop_add_minutes_to_time((string)$time, $duration);
            $memberName = trim((string)$memberNames[$index]);
            if ($index > 0 && $memberName === '') {
                $memberName = 'Guest';
            }

            $countStmt = $pdo->prepare('SELECT COUNT(*) FROM appointments WHERE appointment_date = :d');
            $countStmt->execute([':d' => $slotDate]);
            $sequence = (int)$countStmt->fetchColumn() + 1;
            $bookingCode = 'APP-' . date('Ymd', strtotime($slotDate)) . '-' . str_pad((string)$sequence, 3, '0', STR_PAD_LEFT);

            $insertAppt = $pdo->prepare(
                "INSERT INTO appointments (booking_code, user_id, barber_id, appointment_date, start_time, end_time, status, booking_group_id, group_member_name, group_sequence)
                 VALUES (:code, :user_id, :barber_id, :date, :start, :end, 'PendingPayment', :group_id, :member_name, :seq)
                 RETURNING appointment_id"
            );
            $insertAppt->execute([
                ':code' => $bookingCode,
                ':user_id' => $userId,
                ':barber_id' => $barberId,
                ':date' => $slotDate,
                ':start' => $time,
                ':end' => $endTime,
                ':group_id' => $groupId,
                ':member_name' => $memberName,
                ':seq' => $index + 1,
            ]);
            $appointmentId = (int)$insertAppt->fetchColumn();
            $appointmentIds[] = $appointmentId;
            $bookingCodes[] = $bookingCode;

            foreach ($validatedItems as $item) {
                $detailStmt = $pdo->prepare(
                    "INSERT INTO appointment_details (appointment_id, service_id, variant_id, selected_view, special_instructions, final_price)
                     VALUES (:appointment_id, :service_id, :variant_id, :view, :instructions, :price)"
                );
                $detailStmt->execute([
                    ':appointment_id' => $appointmentId,
                    ':service_id' => $item['serviceID'],
                    ':variant_id' => $item['variantID'],
                    ':view' => $item['selectedView'],
                    ':instructions' => $item['specialInstructions'],
                    ':price' => $item['finalPrice'],
                ]);
            }

        }

        $pdo->commit();

        notify_appointment_created($pdo, [
            'user_id' => $userId,
            'barber_id' => $primaryBarberId,
            'booking_code' => $bookingCodes[0] ?? ('GRP-' . $groupId),
            'appointment_date' => $slotDate,
            'start_time' => $firstTime,
        ]);

        return [
            'groupID' => $groupId,
            'appointmentIDs' => $appointmentIds,
            'bookingCodes' => $bookingCodes,
            'totalAmount' => $totalAmount,
            'peopleCount' => $peopleCount,
            'status' => 'PendingPayment',
        ];
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}
