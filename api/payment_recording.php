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
