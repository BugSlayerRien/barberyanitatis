<?php
// Lock time_slots only after payment (Scheduled+). PendingPayment does not block calendar slots.

declare(strict_types=1);

require_once __DIR__ . '/group_booking.php';
require_once __DIR__ . '/shop_schedule.php';

/**
 * @return string[]
 */
function slot_locking_statuses(): array
{
    return ['Scheduled', 'CheckedIn', 'InProgress', 'Completed'];
}

function lock_time_slot(PDO $pdo, int $barberId, string $slotDate, string $slotTime): void
{
    $normalized = shop_normalize_slot_time($slotTime);
    if ($normalized === null) {
        return;
    }

    $pdo->prepare(
        "INSERT INTO time_slots (barber_id, slot_date, slot_time, status)
         VALUES (:barber_id, :slot_date, :slot_time, 'Booked')
         ON CONFLICT (barber_id, slot_date, slot_time)
         DO UPDATE SET status = 'Booked'"
    )->execute([
        ':barber_id' => $barberId,
        ':slot_date' => $slotDate,
        ':slot_time' => $normalized,
    ]);
}

function release_time_slot(PDO $pdo, int $barberId, string $slotDate, string $slotTime): void
{
    $normalized = shop_normalize_slot_time($slotTime);
    if ($normalized === null) {
        return;
    }

    $pdo->prepare(
        "UPDATE time_slots
         SET status = 'Available'
         WHERE barber_id = :barber_id
           AND slot_date = :slot_date
           AND slot_time = :slot_time"
    )->execute([
        ':barber_id' => $barberId,
        ':slot_date' => $slotDate,
        ':slot_time' => $normalized,
    ]);
}

/**
 * @return list<array{barber_id:int, appointment_date:string, start_time:string}>
 */
function appointments_in_paid_group(PDO $pdo, int $groupId): array
{
    $stmt = $pdo->prepare(
        "SELECT appointment_id, barber_id, appointment_date, start_time, status, booking_group_id
         FROM appointments
         WHERE booking_group_id = :group_id
         ORDER BY group_sequence ASC NULLS LAST, start_time ASC"
    );
    $stmt->execute([':group_id' => $groupId]);

    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

/**
 * @param int[] $excludeAppointmentIds
 */
function paid_slot_conflict_exists(
    PDO $pdo,
    int $barberId,
    string $slotDate,
    string $slotTime,
    array $excludeAppointmentIds = []
): bool {
    $normalized = shop_normalize_slot_time($slotTime);
    if ($normalized === null) {
        return true;
    }

    $statuses = slot_locking_statuses();
    $statusPlaceholders = implode(',', array_fill(0, count($statuses), '?'));
    $sql = "SELECT COUNT(*) FROM appointments
            WHERE barber_id = ?
              AND appointment_date = ?
              AND start_time = ?
              AND status IN ($statusPlaceholders)";
    $params = [$barberId, $slotDate, $normalized, ...$statuses];
    $excludeAppointmentIds = array_values(array_filter(array_map('intval', $excludeAppointmentIds)));
    if ($excludeAppointmentIds !== []) {
        $excludePlaceholders = implode(',', array_fill(0, count($excludeAppointmentIds), '?'));
        $sql .= " AND appointment_id NOT IN ($excludePlaceholders)";
        $params = array_merge($params, $excludeAppointmentIds);
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);

    return (int)$stmt->fetchColumn() > 0;
}

/**
 * Lock slots after payment. Returns false when another paid booking already holds a slot.
 */
function lock_slots_after_payment(PDO $pdo, int $appointmentId): bool
{
    ensure_group_booking_schema($pdo);

    $stmt = $pdo->prepare(
        'SELECT appointment_id, barber_id, appointment_date, start_time, booking_group_id
         FROM appointments WHERE appointment_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return false;
    }

    $groupId = (int)($row['booking_group_id'] ?? 0);
    $rows = $groupId > 0
        ? appointments_in_paid_group($pdo, $groupId)
        : [$row];

    $excludeIds = array_map(static fn(array $r): int => (int)$r['appointment_id'], $rows);

    foreach ($rows as $slotRow) {
        if (paid_slot_conflict_exists(
            $pdo,
            (int)$slotRow['barber_id'],
            (string)$slotRow['appointment_date'],
            (string)$slotRow['start_time'],
            $excludeIds
        )) {
            return false;
        }
    }

    foreach ($rows as $slotRow) {
        lock_time_slot(
            $pdo,
            (int)$slotRow['barber_id'],
            (string)$slotRow['appointment_date'],
            (string)$slotRow['start_time']
        );
    }

    return true;
}

/**
 * Promote PendingPayment → Scheduled for a booking unit (single or whole group) and lock slots.
 */
function promote_paid_booking_unit(PDO $pdo, int $appointmentId): string
{
    ensure_group_booking_schema($pdo);

    $stmt = $pdo->prepare(
        'SELECT appointment_id, user_id, barber_id, booking_code, status, booking_group_id
         FROM appointments WHERE appointment_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return 'Scheduled';
    }

    $currentStatus = (string)$row['status'];
    if ($currentStatus !== 'PendingPayment') {
        return $currentStatus;
    }

    $groupId = (int)($row['booking_group_id'] ?? 0);
    $ids = [$appointmentId];
    if ($groupId > 0) {
        $groupStmt = $pdo->prepare(
            "SELECT appointment_id FROM appointments WHERE booking_group_id = :group_id"
        );
        $groupStmt->execute([':group_id' => $groupId]);
        $ids = array_map(static fn(array $r): int => (int)$r['appointment_id'], $groupStmt->fetchAll(PDO::FETCH_ASSOC));
    }

    if (!lock_slots_after_payment($pdo, $appointmentId)) {
        return 'PendingPayment';
    }

    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $update = $pdo->prepare(
        "UPDATE appointments SET status = 'Scheduled', updated_at = CURRENT_TIMESTAMP
         WHERE appointment_id IN ($placeholders) AND status = 'PendingPayment'"
    );
    $update->execute($ids);

    if ($update->rowCount() > 0) {
        if ($groupId > 0) {
            $pdo->prepare(
                "UPDATE appointment_groups
                 SET status = 'Scheduled'
                 WHERE group_id = :group_id AND status = 'PendingPayment'"
            )->execute([':group_id' => $groupId]);
        }

        notify_appointment_paid($pdo, [
            'user_id' => (int)$row['user_id'],
            'barber_id' => (int)$row['barber_id'],
            'booking_code' => (string)$row['booking_code'],
        ]);
    }

    return 'Scheduled';
}

/** Release time_slots incorrectly marked Booked while appointment is still PendingPayment. */
function reconcile_pending_payment_slots(PDO $pdo): void
{
    static $done = false;
    if ($done) {
        return;
    }
    require_once __DIR__ . '/schema_cache.php';
    if (!schema_cache_should_run('reconcile_pending_payment_slots', 300)) {
        $done = true;

        return;
    }

    $pdo->exec(
        "UPDATE time_slots ts
         SET status = 'Available'
         FROM appointments a
         WHERE a.barber_id = ts.barber_id
           AND a.appointment_date = ts.slot_date
           AND a.start_time = ts.slot_time
           AND a.status = 'PendingPayment'
           AND ts.status = 'Booked'"
    );

    schema_cache_done('reconcile_pending_payment_slots');
    $done = true;
}

function release_slots_for_appointment(PDO $pdo, int $appointmentId): void
{
    $stmt = $pdo->prepare(
        'SELECT appointment_id, barber_id, appointment_date, start_time, booking_group_id, status
         FROM appointments WHERE appointment_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }

    if (!in_array((string)$row['status'], slot_locking_statuses(), true)) {
        return;
    }

    $groupId = (int)($row['booking_group_id'] ?? 0);
    $rows = $groupId > 0
        ? appointments_in_paid_group($pdo, $groupId)
        : [$row];

    foreach ($rows as $slotRow) {
        release_time_slot(
            $pdo,
            (int)$slotRow['barber_id'],
            (string)$slotRow['appointment_date'],
            (string)$slotRow['start_time']
        );
    }
}

/**
 * Derive a single status for a booking unit from member appointment rows.
 *
 * @param list<string> $statuses
 */
function aggregate_booking_unit_status(array $statuses): string
{
    $statuses = array_values(array_unique(array_map(static fn($s): string => trim((string)$s), $statuses)));
    if ($statuses === []) {
        return 'Scheduled';
    }

    if (in_array('PendingPayment', $statuses, true)) {
        return 'PendingPayment';
    }
    if (in_array('InProgress', $statuses, true)) {
        return 'InProgress';
    }
    if (in_array('CheckedIn', $statuses, true)) {
        return 'CheckedIn';
    }
    if (in_array('Scheduled', $statuses, true)) {
        return 'Scheduled';
    }

    $terminal = ['Completed', 'Cancelled', 'NoShow'];
    $nonTerminal = array_values(array_filter(
        $statuses,
        static fn(string $status): bool => !in_array($status, $terminal, true)
    ));
    if ($nonTerminal === [] && in_array('Completed', $statuses, true)) {
        return 'Completed';
    }
    if ($nonTerminal === [] && in_array('Cancelled', $statuses, true)) {
        return 'Cancelled';
    }
    if ($nonTerminal === [] && in_array('NoShow', $statuses, true)) {
        return 'NoShow';
    }

    return $statuses[0];
}

/**
 * Mark a single appointment or entire group complete, release slots, and record revenue once.
 *
 * @return int 1 when a booking unit was completed, 0 when nothing changed
 */
function complete_booking_unit(PDO $pdo, int $appointmentId, ?string $completionTime = null): int
{
    ensure_group_booking_schema($pdo);

    $stmt = $pdo->prepare(
        'SELECT appointment_id, user_id, barber_id, booking_code, booking_group_id, status
         FROM appointments
         WHERE appointment_id = :appointment_id
         LIMIT 1'
    );
    $stmt->execute([':appointment_id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return 0;
    }

    $groupId = (int)($row['booking_group_id'] ?? 0);
    $members = $groupId > 0
        ? appointments_in_paid_group($pdo, $groupId)
        : [$row];

    $activeStatuses = ['Scheduled', 'CheckedIn', 'InProgress'];
    $toComplete = array_values(array_filter(
        $members,
        static fn(array $member): bool => in_array((string)($member['status'] ?? ''), $activeStatuses, true)
    ));
    if ($toComplete === []) {
        return 0;
    }

    $completion = $completionTime ?? date('Y-m-d H:i:s');
    $ids = array_map(static fn(array $member): int => (int)$member['appointment_id'], $toComplete);
    $placeholders = implode(',', array_fill(0, count($ids), '?'));

    $pdo->prepare(
        "UPDATE appointments
         SET status = 'Completed',
             completion_time = COALESCE(completion_time, ?),
             updated_at = CURRENT_TIMESTAMP
         WHERE appointment_id IN ($placeholders)"
    )->execute(array_merge([$completion], $ids));

    if ($groupId > 0) {
        $pdo->prepare(
            "UPDATE appointment_groups
             SET status = 'Completed'
             WHERE group_id = :group_id
               AND status NOT IN ('Cancelled', 'Completed')"
        )->execute([':group_id' => $groupId]);
    }

    release_slots_for_appointment($pdo, (int)$toComplete[0]['appointment_id']);

    require_once __DIR__ . '/payment_recording.php';
    record_booking_unit_completion_payment($pdo, (int)$row['appointment_id']);

    return 1;
}

function format_time_range_label(string $startTime, string $endTime): string
{
    return format_time_range_12h($startTime, $endTime);
}

/**
 * @param list<array<string, mixed>> $members
 */
function resolve_group_payment_state(array $members): string
{
    $states = array_map(
        static fn(array $member): string => (string)($member['paymentState'] ?? 'Unpaid'),
        $members
    );

    if (in_array('Paid', $states, true)) {
        return 'Paid';
    }
    if (in_array('Verifying', $states, true)) {
        return 'Verifying';
    }
    if (in_array('Failed', $states, true)) {
        return 'Failed';
    }

    return 'Unpaid';
}

/**
 * Copy paid state from any group member that has a captured payment to siblings.
 *
 * @param list<array<string, mixed>> $appointments
 * @return list<array<string, mixed>>
 */
/** Promote group rows that have a captured payment but are still PendingPayment. */
function sync_paid_groups_from_payments(PDO $pdo, bool $force = false): void
{
    static $done = false;
    if ($done && !$force) {
        return;
    }

    if (!$force) {
        require_once __DIR__ . '/schema_cache.php';
        if (!schema_cache_should_run('sync_paid_groups_from_payments', 120)) {
            $done = true;

            return;
        }
    }

    $stmt = $pdo->query(
        "SELECT MIN(a.appointment_id) AS appointment_id
         FROM appointments a
         WHERE a.booking_group_id IS NOT NULL
           AND a.status = 'PendingPayment'
           AND (
                EXISTS (
                    SELECT 1
                    FROM appointments a_pay
                    INNER JOIN appointment_payments ap ON ap.appointment_id = a_pay.appointment_id
                    WHERE a_pay.booking_group_id = a.booking_group_id
                      AND LOWER(ap.status) IN ('captured', 'paid', 'succeeded')
                )
                OR EXISTS (
                    SELECT 1
                    FROM appointments a_int
                    INNER JOIN appointment_payment_intents i ON i.appointment_id = a_int.appointment_id
                    WHERE a_int.booking_group_id = a.booking_group_id
                      AND LOWER(i.status) IN ('paid', 'succeeded', 'captured')
                )
                OR EXISTS (
                    SELECT 1
                    FROM payments p
                    INNER JOIN appointments a2 ON a2.appointment_id = p.appointment_id
                    WHERE a2.booking_group_id = a.booking_group_id
                      AND p.payment_status = 'Paid'
                )
           )
         GROUP BY a.booking_group_id"
    );
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $appointmentId = (int)($row['appointment_id'] ?? 0);
        if ($appointmentId > 0) {
            try {
                promote_paid_booking_unit($pdo, $appointmentId);
            } catch (Throwable $e) {
                // Continue syncing other groups.
            }
        }
    }

    if (!$force) {
        schema_cache_done('sync_paid_groups_from_payments');
    }
    $done = true;
}

/** Promote solo appointments that have a Paid row in `payments` but are still PendingPayment. */
function sync_paid_appointments_from_payments(PDO $pdo, bool $force = false): void
{
    static $done = false;
    if ($done && !$force) {
        return;
    }

    if (!$force) {
        require_once __DIR__ . '/schema_cache.php';
        if (!schema_cache_should_run('sync_paid_appointments_from_payments', 60)) {
            $done = true;

            return;
        }
    }

    $stmt = $pdo->query(
        "SELECT DISTINCT a.appointment_id
         FROM appointments a
         INNER JOIN payments p ON p.appointment_id = a.appointment_id
         WHERE a.status = 'PendingPayment'
           AND p.payment_status = 'Paid'"
    );
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $appointmentId = (int)($row['appointment_id'] ?? 0);
        if ($appointmentId > 0) {
            try {
                promote_paid_booking_unit($pdo, $appointmentId);
            } catch (Throwable $e) {
                // Continue with other rows.
            }
        }
    }

    if (!$force) {
        schema_cache_done('sync_paid_appointments_from_payments');
    }
    $done = true;
}

function propagate_group_payment_states(array $appointments): array
{
    $paidLeadByGroup = [];
    foreach ($appointments as $row) {
        $groupId = (int)($row['bookingGroupID'] ?? 0);
        if ($groupId <= 0 || ($row['paymentState'] ?? '') !== 'Paid') {
            continue;
        }
        $paidLeadByGroup[$groupId] = $row;
    }

    foreach ($appointments as &$row) {
        $groupId = (int)($row['bookingGroupID'] ?? 0);
        if ($groupId <= 0 || !isset($paidLeadByGroup[$groupId])) {
            continue;
        }

        $lead = $paidLeadByGroup[$groupId];
        $row['paymentState'] = 'Paid';
        $row['paymentStatus'] = $lead['paymentStatus'] ?? null;
        $row['receiptRef'] = $lead['receiptRef'] ?? null;
        $row['paidAt'] = $lead['paidAt'] ?? null;
        $row['intentID'] = $row['intentID'] ?? ($lead['intentID'] ?? null);
        $row['intentStatus'] = $row['intentStatus'] ?? ($lead['intentStatus'] ?? null);
        $row['intentMethod'] = $row['intentMethod'] ?? ($lead['intentMethod'] ?? null);
        $row['canRetryPayment'] = false;
        $row['canReschedule'] = true;
        if (($row['status'] ?? '') === 'PendingPayment' && ($lead['status'] ?? '') === 'Scheduled') {
            $row['status'] = 'Scheduled';
        }
    }
    unset($row);

    return $appointments;
}

/**
 * @param list<array<string, mixed>> $rows Raw appointment rows with services attached
 * @return list<array<string, mixed>>
 */
function collapse_customer_appointments(PDO $pdo, array $rows): array
{
    $byGroup = [];
    $singles = [];

    foreach ($rows as $row) {
        $groupId = (int)($row['bookingGroupID'] ?? $row['booking_group_id'] ?? 0);
        if ($groupId > 0) {
            $byGroup[$groupId][] = $row;
        } else {
            $singles[] = $row;
        }
    }

    $collapsed = [];

    foreach ($singles as $row) {
        $collapsed[] = $row;
    }

    foreach ($byGroup as $groupId => $members) {
        usort($members, static function (array $a, array $b): int {
            $seqA = (int)($a['groupSequence'] ?? $a['group_sequence'] ?? 0);
            $seqB = (int)($b['groupSequence'] ?? $b['group_sequence'] ?? 0);
            if ($seqA !== $seqB) {
                return $seqA <=> $seqB;
            }

            return strcmp((string)($a['startTime'] ?? ''), (string)($b['startTime'] ?? ''));
        });

        $primary = $members[0];
        $last = $members[count($members) - 1];
        $groupMeta = fetch_booking_group_meta($pdo, $groupId);
        $peopleCount = (int)($groupMeta['people_count'] ?? 0);
        if ($peopleCount <= 0) {
            $peopleCount = count($members);
        }
        $displayEndTime = booking_group_display_end_time($last);

        $customerName = trim((string)($primary['customerName'] ?? ''));
        $leadName = trim((string)($primary['groupMemberName'] ?? $primary['group_member_name'] ?? ''));
        if ($customerName !== '') {
            $leadName = $customerName;
        } elseif ($leadName === '' || preg_match('/^Person \d+$/', $leadName) === 1 || $leadName === 'Guest') {
            $leadName = 'You';
        }

        $memberDetails = [];
        $memberNames = [$leadName];
        foreach ($members as $index => $member) {
            $slotLabel = $index === 0
                ? $leadName
                : 'Additional guest';
            if ($index > 0) {
                $memberNames[] = $slotLabel;
            }
            $memberDetails[] = [
                'name' => $slotLabel,
                'startTime' => (string)($member['startTime'] ?? ''),
                'endTime' => (string)($member['endTime'] ?? ''),
                'appointmentID' => (int)($member['appointmentID'] ?? 0),
                'isPrimary' => $index === 0,
            ];
        }

        $others = max(0, $peopleCount - 1);
        $displayTitle = $others > 0
            ? $leadName . ' + ' . $others . ' other' . ($others === 1 ? '' : 's')
            : $leadName;

        $totalPrice = 0.0;
        foreach ($members as $member) {
            foreach ($member['services'] ?? [] as $service) {
                $totalPrice += (float)($service['price'] ?? 0);
            }
        }

        $memberStatuses = array_map(static fn(array $m): string => (string)($m['status'] ?? 'Scheduled'), $members);
        $status = aggregate_booking_unit_status($memberStatuses);
        $paymentState = resolve_group_payment_state($members);
        if ($paymentState === 'Paid' && $status === 'PendingPayment') {
            $status = 'Scheduled';
        }

        $perPersonMinutes = 0;
        foreach ($primary['services'] ?? [] as $service) {
            $perPersonMinutes = max($perPersonMinutes, (int)($service['durationMinutes'] ?? shop_appointment_duration_minutes()));
        }
        if ($perPersonMinutes <= 0) {
            $perPersonMinutes = shop_appointment_duration_minutes();
        }
        $totalDurationMinutes = $perPersonMinutes * $peopleCount;

        $holdEndsAt = null;
        $holdMinutes = shop_reservation_hold_minutes();
        foreach ($members as $member) {
            $createdRaw = $member['intentCreatedAt'] ?? null;
            if ($createdRaw === null || (string)$member['status'] !== 'PendingPayment') {
                continue;
            }
            $createdTs = strtotime((string)$createdRaw);
            if ($createdTs === false) {
                continue;
            }
            $candidate = date('Y-m-d H:i:s', $createdTs + ($holdMinutes * 60));
            if ($holdEndsAt === null || strtotime($candidate) < strtotime($holdEndsAt)) {
                $holdEndsAt = $candidate;
            }
        }

        $collapsed[] = array_merge($primary, [
            'isGroup' => true,
            'bookingGroupID' => $groupId,
            'peopleCount' => $peopleCount,
            'displayTitle' => $displayTitle,
            'groupMemberNames' => $memberNames,
            'groupMembers' => $memberDetails,
            'startTime' => (string)($primary['startTime'] ?? ''),
            'endTime' => $displayEndTime,
            'timeRange' => format_time_range_label(
                (string)($primary['startTime'] ?? ''),
                $displayEndTime
            ),
            'totalPrice' => number_format($totalPrice, 2, '.', ''),
            'status' => $status,
            'paymentState' => $paymentState,
            'appointmentIDs' => array_map(static fn(array $m): int => (int)($m['appointmentID'] ?? 0), $members),
            'totalDurationMinutes' => $totalDurationMinutes,
            'holdExpiresAt' => $holdEndsAt,
        ]);
    }

    usort($collapsed, static function (array $a, array $b): int {
        $dateCmp = strcmp((string)($b['appointmentDate'] ?? ''), (string)($a['appointmentDate'] ?? ''));
        if ($dateCmp !== 0) {
            return $dateCmp;
        }

        return strcmp((string)($b['startTime'] ?? ''), (string)($a['startTime'] ?? ''));
    });

    return $collapsed;
}

/**
 * @return list<array<string, mixed>>
 */
function fetch_appointments_for_booking_group(PDO $pdo, int $groupId): array
{
    $stmt = $pdo->prepare(
        "SELECT a.appointment_id, a.booking_code, a.booking_group_id, a.group_sequence,
                a.appointment_date, a.start_time, a.end_time, a.status, a.barber_id,
                u.user_id AS customer_id, u.full_name AS customer_name
         FROM appointments a
         JOIN users u ON a.user_id = u.user_id
         WHERE a.booking_group_id = :group_id
         ORDER BY a.group_sequence ASC NULLS LAST, a.start_time ASC"
    );
    $stmt->execute([':group_id' => $groupId]);

    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}

function barber_dashboard_card_fingerprint(array $row): string
{
    if (!empty($row['isGroup'])) {
        return implode('|', [
            'g',
            (int)($row['customerID'] ?? 0),
            (string)($row['appointmentDate'] ?? ''),
            (string)($row['timeRange'] ?? ''),
            (string)($row['status'] ?? ''),
            (int)($row['peopleCount'] ?? 0),
        ]);
    }

    return 'a:' . (int)($row['appointmentID'] ?? 0);
}

/**
 * @param list<array<string, mixed>> $rows Barber-scoped appointment rows
 * @return list<array<string, mixed>>
 */
function collapse_barber_dashboard_appointments(PDO $pdo, array $rows, int $barberId): array
{
    $singles = [];
    $groupIdsForBarber = [];

    foreach ($rows as $row) {
        $groupId = (int)($row['bookingGroupID'] ?? 0);
        if ($groupId > 0) {
            $groupIdsForBarber[$groupId] = true;
        } else {
            $singles[] = $row;
        }
    }

    $collapsed = $singles;
    $seenGroupIds = [];

    foreach (array_keys($groupIdsForBarber) as $groupId) {
        if (isset($seenGroupIds[$groupId])) {
            continue;
        }
        $seenGroupIds[$groupId] = true;

        $allMembers = fetch_appointments_for_booking_group($pdo, $groupId);
        if ($allMembers === []) {
            continue;
        }

        $barberMemberRows = array_values(array_filter(
            $allMembers,
            static fn(array $member): bool => (int)($member['barber_id'] ?? 0) === $barberId
        ));
        if ($barberMemberRows === []) {
            continue;
        }

        $primary = $allMembers[0];
        $last = $allMembers[count($allMembers) - 1];
        $groupMeta = fetch_booking_group_meta($pdo, $groupId);
        $customerName = trim((string)($primary['customer_name'] ?? 'Customer'));
        $peopleCount = (int)($groupMeta['people_count'] ?? 0);
        if ($peopleCount <= 0) {
            $peopleCount = count($allMembers);
        }
        $displayEndTime = booking_group_display_end_time($last);
        $others = max(0, $peopleCount - 1);
        $displayTitle = $others > 0
            ? $customerName . ' + ' . $others . ' other' . ($others === 1 ? '' : 's')
            : $customerName;

        $memberStatuses = array_map(
            static fn(array $member): string => (string)($member['status'] ?? 'Scheduled'),
            $allMembers
        );
        $status = aggregate_booking_unit_status($memberStatuses);

        $primaryBarberRow = $barberMemberRows[0];
        $detailExtras = [];
        foreach ($rows as $sourceRow) {
            if ((int)($sourceRow['bookingGroupID'] ?? 0) === $groupId) {
                $detailExtras = $sourceRow;
                break;
            }
        }

        $collapsed[] = array_merge($detailExtras, [
            'appointmentID' => (int)($primaryBarberRow['appointment_id'] ?? $primary['appointment_id']),
            'bookingCode' => (string)($primary['booking_code'] ?? ''),
            'bookingGroupID' => $groupId,
            'appointmentDate' => (string)($primary['appointment_date'] ?? ''),
            'startTime' => (string)($primary['start_time'] ?? ''),
            'endTime' => $displayEndTime,
            'status' => $status,
            'customerID' => (int)($primary['customer_id'] ?? 0),
            'customerName' => $displayTitle,
            'isGroup' => true,
            'peopleCount' => $peopleCount,
            'displayTitle' => $displayTitle,
            'timeRange' => format_time_range_label(
                (string)($primary['start_time'] ?? ''),
                $displayEndTime
            ),
            'appointmentIDs' => array_map(
                static fn(array $m): int => (int)($m['appointment_id'] ?? 0),
                $allMembers
            ),
        ]);
    }

    $deduped = [];
    $fingerprints = [];
    foreach ($collapsed as $row) {
        $key = barber_dashboard_card_fingerprint($row);
        if (isset($fingerprints[$key])) {
            continue;
        }
        $fingerprints[$key] = true;
        $deduped[] = $row;
    }

    usort($deduped, static function (array $a, array $b): int {
        $dateCmp = strcmp((string)($b['appointmentDate'] ?? ''), (string)($a['appointmentDate'] ?? ''));
        if ($dateCmp !== 0) {
            return $dateCmp;
        }

        return strcmp((string)($b['startTime'] ?? ''), (string)($a['startTime'] ?? ''));
    });

    return $deduped;
}

/**
 * @param list<array<string, mixed>> $rows
 * @return list<array<string, mixed>>
 */
function collapse_receptionist_appointments(PDO $pdo, array $rows): array
{
    $mapped = [];
    foreach ($rows as $row) {
        $mapped[] = [
            'appointment_id' => (int)$row['appointment_id'],
            'barber_id' => (int)$row['barber_id'],
            'booking_group_id' => (int)($row['booking_group_id'] ?? 0),
            'group_member_name' => (string)($row['group_member_name'] ?? ''),
            'group_sequence' => (int)($row['group_sequence'] ?? 0),
            'name' => (string)$row['name'],
            'booker_name' => (string)($row['booker_name'] ?? $row['name'] ?? ''),
            'payment_status' => $row['payment_status'] ?? null,
            'intent_status' => $row['intent_status'] ?? null,
            'service' => (string)$row['service'],
            'appointment_date' => (string)$row['appointment_date'],
            'time' => (string)$row['time'],
            'end_time' => (string)$row['end_time'],
            'duration' => (string)($row['duration'] ?? '60 min'),
            'price' => $row['price'],
            'status' => (string)$row['status'],
            'barber' => (string)$row['barber'],
        ];
    }

    $byGroup = [];
    $singles = [];
    foreach ($mapped as $row) {
        $gid = (int)($row['booking_group_id'] ?? 0);
        if ($gid > 0) {
            $byGroup[$gid][] = $row;
        } else {
            $singles[] = $row;
        }
    }

    $out = $singles;
    foreach ($byGroup as $gid => $members) {
        usort($members, static fn(array $a, array $b): int => ($a['group_sequence'] <=> $b['group_sequence'])
            ?: strcmp((string)$a['time'], (string)$b['time']));

        $primary = $members[0];
        $last = $members[count($members) - 1];
        $groupMeta = fetch_booking_group_meta($pdo, $gid);
        $displayEndTime = booking_group_display_end_time([
            'start_time' => (string)($last['time'] ?? ''),
            'end_time' => (string)($last['end_time'] ?? ''),
        ]);
        $lead = trim((string)($primary['booker_name'] ?? $primary['name'] ?? ''));
        if ($lead === '') {
            $lead = 'Customer';
        }
        $peopleCount = (int)($groupMeta['people_count'] ?? 0);
        if ($peopleCount <= 0) {
            $peopleCount = count($members);
        }
        $others = max(0, $peopleCount - 1);
        $label = $others > 0
            ? $lead . ' + ' . $others . ' other' . ($others === 1 ? '' : 's')
            : $lead;

        $groupPaid = false;
        foreach ($members as $m) {
            $paymentStatus = strtolower(trim((string)($m['payment_status'] ?? '')));
            $intentStatus = strtolower(trim((string)($m['intent_status'] ?? '')));
            if (in_array($paymentStatus, ['captured', 'paid', 'succeeded'], true)
                || in_array($intentStatus, ['paid', 'succeeded', 'captured'], true)) {
                $groupPaid = true;
                break;
            }
        }

        $memberStatuses = array_map(static fn(array $m): string => (string)$m['status'], $members);
        $status = aggregate_booking_unit_status($memberStatuses);
        if ($groupPaid && $status === 'PendingPayment') {
            $status = 'Scheduled';
            try {
                promote_paid_booking_unit($pdo, (int)$primary['appointment_id']);
            } catch (Throwable $e) {
                // Dashboard listing should still reflect paid state.
            }
        }

        $total = 0.0;
        foreach ($members as $m) {
            $total += (float)($m['price'] ?? 0);
        }

        $out[] = [
            'appointment_id' => (int)$primary['appointment_id'],
            'barber_id' => (int)$primary['barber_id'],
            'is_group' => true,
            'booking_group_id' => $gid,
            'name' => $label,
            'member_names' => [$lead],
            'member_label' => $label,
            'is_paid' => $groupPaid,
            'service' => (string)$primary['service'],
            'appointment_date' => (string)$primary['appointment_date'],
            'time' => (string)$primary['time'],
            'end_time' => $displayEndTime,
            'time_range' => format_time_range_12h((string)$primary['time'], $displayEndTime),
            'duration' => ((int)count($members) * 60) . ' min',
            'price' => $total,
            'status' => $status,
            'barber' => (string)$primary['barber'],
            'people_count' => $peopleCount,
        ];
    }

    usort($out, static function (array $a, array $b): int {
        $da = (string)($a['appointment_date'] ?? '');
        $db = (string)($b['appointment_date'] ?? '');
        if ($da !== $db) {
            return strcmp($da, $db);
        }

        return strcmp((string)($a['time'] ?? ''), (string)($b['time'] ?? ''));
    });

    return $out;
}
