<?php
// Record paid revenue in `payments` when walk-ins or appointments complete.

declare(strict_types=1);

function generate_payment_ref(PDO $pdo): string
{
    do {
        $ref = 'PAY-' . date('Ymd') . '-' . strtoupper(bin2hex(random_bytes(3)));
        $check = $pdo->prepare('SELECT 1 FROM payments WHERE payment_ref = :ref LIMIT 1');
        $check->execute([':ref' => $ref]);
    } while ($check->fetchColumn());

    return $ref;
}

function appointment_total_amount(PDO $pdo, int $appointmentId): float
{
    $stmt = $pdo->prepare(
        'SELECT COALESCE(SUM(final_price), 0)::numeric
         FROM appointment_details
         WHERE appointment_id = :appointment_id'
    );
    $stmt->execute([':appointment_id' => $appointmentId]);

    return (float)$stmt->fetchColumn();
}

function walkin_total_amount(PDO $pdo, int $queueId): float
{
    $stmt = $pdo->prepare(
        'SELECT COALESCE(SUM(final_price), 0)::numeric
         FROM walkin_service_details
         WHERE queue_id = :queue_id'
    );
    $stmt->execute([':queue_id' => $queueId]);

    return (float)$stmt->fetchColumn();
}

function booking_group_total_amount(PDO $pdo, int $groupId): float
{
    $stmt = $pdo->prepare(
        'SELECT COALESCE(total_amount, 0)::numeric
         FROM appointment_groups
         WHERE group_id = :group_id
         LIMIT 1'
    );
    $stmt->execute([':group_id' => $groupId]);
    $amount = (float)$stmt->fetchColumn();
    if ($amount > 0) {
        return $amount;
    }

    $sumStmt = $pdo->prepare(
        'SELECT COALESCE(SUM(ad.final_price), 0)::numeric
         FROM appointment_details ad
         INNER JOIN appointments a ON a.appointment_id = ad.appointment_id
         WHERE a.booking_group_id = :group_id'
    );
    $sumStmt->execute([':group_id' => $groupId]);

    return (float)$sumStmt->fetchColumn();
}

function group_completion_payment_exists(PDO $pdo, int $groupId): bool
{
    $stmt = $pdo->prepare(
        "SELECT 1
         FROM payments p
         INNER JOIN appointments a ON a.appointment_id = p.appointment_id
         WHERE a.booking_group_id = :group_id
           AND p.payment_status = 'Paid'
         LIMIT 1"
    );
    $stmt->execute([':group_id' => $groupId]);

    return (bool)$stmt->fetchColumn();
}

/**
 * Record revenue once for a booking unit (single appointment or whole group).
 */
function record_booking_unit_completion_payment(PDO $pdo, int $appointmentId): void
{
    if ($appointmentId <= 0) {
        return;
    }

    $stmt = $pdo->prepare(
        'SELECT appointment_id, booking_group_id
         FROM appointments
         WHERE appointment_id = :appointment_id
         LIMIT 1'
    );
    $stmt->execute([':appointment_id' => $appointmentId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }

    $groupId = (int)($row['booking_group_id'] ?? 0);
    if ($groupId <= 0) {
        record_completion_payment($pdo, $appointmentId, null);

        return;
    }

    if (group_completion_payment_exists($pdo, $groupId)) {
        return;
    }

    $leadStmt = $pdo->prepare(
        'SELECT appointment_id
         FROM appointments
         WHERE booking_group_id = :group_id
         ORDER BY group_sequence ASC NULLS LAST, start_time ASC, appointment_id ASC
         LIMIT 1'
    );
    $leadStmt->execute([':group_id' => $groupId]);
    $leadId = (int)$leadStmt->fetchColumn();
    if ($leadId <= 0) {
        $leadId = $appointmentId;
    }

    $amount = booking_group_total_amount($pdo, $groupId);
    if ($amount <= 0) {
        $amount = 500.0;
    }

    $insert = $pdo->prepare(
        "INSERT INTO payments (
            payment_ref, appointment_id, queue_id,
            amount, discount_amount, tax_amount, total_amount,
            payment_method, payment_status, paid_at
         ) VALUES (
            :payment_ref, :appointment_id, NULL,
            :amount, 0, 0, :total_amount,
            'Cash', 'Paid', NOW()
         )"
    );
    $insert->execute([
        ':payment_ref' => generate_payment_ref($pdo),
        ':appointment_id' => $leadId,
        ':amount' => $amount,
        ':total_amount' => $amount,
    ]);
}

/**
 * Insert a Paid row into payments (idempotent per appointment_id or queue_id).
 */
function record_completion_payment(PDO $pdo, ?int $appointmentId, ?int $queueId): void
{
    if (($appointmentId === null || $appointmentId <= 0) && ($queueId === null || $queueId <= 0)) {
        return;
    }

    if ($appointmentId !== null && $appointmentId > 0) {
        $exists = $pdo->prepare(
            "SELECT 1 FROM payments
             WHERE appointment_id = :appointment_id AND payment_status = 'Paid'
             LIMIT 1"
        );
        $exists->execute([':appointment_id' => $appointmentId]);
        if ($exists->fetchColumn()) {
            return;
        }

        $amount = appointment_total_amount($pdo, $appointmentId);
        if ($amount <= 0) {
            $amount = 500.0;
        }

        $insert = $pdo->prepare(
            "INSERT INTO payments (
                payment_ref, appointment_id, queue_id,
                amount, discount_amount, tax_amount, total_amount,
                payment_method, payment_status, paid_at
             ) VALUES (
                :payment_ref, :appointment_id, NULL,
                :amount, 0, 0, :total_amount,
                'Cash', 'Paid', NOW()
             )"
        );
        $insert->execute([
            ':payment_ref' => generate_payment_ref($pdo),
            ':appointment_id' => $appointmentId,
            ':amount' => $amount,
            ':total_amount' => $amount,
        ]);

        return;
    }

    if ($queueId === null || $queueId <= 0) {
        return;
    }

    $exists = $pdo->prepare(
        "SELECT 1 FROM payments
         WHERE queue_id = :queue_id AND payment_status = 'Paid'
         LIMIT 1"
    );
    $exists->execute([':queue_id' => $queueId]);
    if ($exists->fetchColumn()) {
        return;
    }

    $amount = walkin_total_amount($pdo, $queueId);
    if ($amount <= 0) {
        $amount = 100.0;
    }

    $insert = $pdo->prepare(
        "INSERT INTO payments (
            payment_ref, appointment_id, queue_id,
            amount, discount_amount, tax_amount, total_amount,
            payment_method, payment_status, paid_at
         ) VALUES (
            :payment_ref, NULL, :queue_id,
            :amount, 0, 0, :total_amount,
            'Cash', 'Paid', NOW()
         )"
    );
    $insert->execute([
        ':payment_ref' => generate_payment_ref($pdo),
        ':queue_id' => $queueId,
        ':amount' => $amount,
        ':total_amount' => $amount,
    ]);
}
