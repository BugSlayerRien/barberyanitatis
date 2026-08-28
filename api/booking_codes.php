<?php
// Appointment booking-code allocation: APP-YYYYMMDD-### from max existing suffix.

declare(strict_types=1);

function appointment_booking_code_prefix(string $slotDate): string
{
    $ymd = date('Ymd', strtotime($slotDate));
    if (!preg_match('/^\d{8}$/', $ymd)) {
        $ymd = date('Ymd');
    }

    return 'APP-' . $ymd;
}

function appointment_booking_code_conflict(PDOException $e): bool
{
    $states = [(string)($e->errorInfo[0] ?? ''), (string)$e->getCode()];
    foreach ($states as $state) {
        if ($state === '23505') {
            return true;
        }
    }

    return str_contains($e->getMessage(), 'appointments_booking_code_key');
}

function next_appointment_booking_code(PDO $pdo, string $slotDate): string
{
    $prefix = appointment_booking_code_prefix($slotDate);
    $stmt = $pdo->prepare(
        "SELECT COALESCE(MAX(CAST(SUBSTRING(booking_code FROM 14) AS INTEGER)), 0)
         FROM appointments
         WHERE booking_code LIKE :pattern
           AND SUBSTRING(booking_code FROM 14) ~ '^[0-9]+$'"
    );
    $stmt->execute([
        ':pattern' => $prefix . '-%',
    ]);
    $max = (int)$stmt->fetchColumn();

    return $prefix . '-' . str_pad((string)($max + 1), 3, '0', STR_PAD_LEFT);
}

/**
 * Run an INSERT that uses a freshly allocated booking_code.
 * Uses a savepoint so a unique violation does not abort the outer transaction.
 *
 * @template T
 * @param callable(string):T $insertWithCode
 * @return T
 */
function insert_appointment_with_unique_code(
    PDO $pdo,
    string $slotDate,
    callable $insertWithCode,
    int $maxAttempts = 8
) {
    $inTransaction = $pdo->inTransaction();
    $last = null;

    for ($attempt = 1; $attempt <= $maxAttempts; $attempt++) {
        $code = next_appointment_booking_code($pdo, $slotDate);
        if ($inTransaction) {
            $pdo->exec('SAVEPOINT booking_code_alloc');
        }
        try {
            $result = $insertWithCode($code);
            if ($inTransaction) {
                $pdo->exec('RELEASE SAVEPOINT booking_code_alloc');
            }

            return $result;
        } catch (PDOException $e) {
            if ($inTransaction) {
                $pdo->exec('ROLLBACK TO SAVEPOINT booking_code_alloc');
            }
            $last = $e;
            if (!appointment_booking_code_conflict($e)) {
                throw $e;
            }
        }
    }

    throw $last ?? new RuntimeException('Could not allocate a unique booking code.');
}

/**
 * Prefer the requested variant when it exists; otherwise last used by this user; else catalog.
 */
function resolve_group_booking_variant_id(PDO $pdo, int $userId, int $requestedVariantId): int
{
    if ($requestedVariantId > 0) {
        $stmt = $pdo->prepare(
            'SELECT variant_id FROM hairstyle_variants WHERE variant_id = :id LIMIT 1'
        );
        $stmt->execute([':id' => $requestedVariantId]);
        $found = (int)$stmt->fetchColumn();
        if ($found > 0) {
            return $found;
        }
    }

    if ($userId > 0) {
        $stmt = $pdo->prepare(
            'SELECT ad.variant_id
             FROM appointment_details ad
             JOIN appointments a ON a.appointment_id = ad.appointment_id
             JOIN hairstyle_variants hv ON hv.variant_id = ad.variant_id
             WHERE a.user_id = :user_id
             ORDER BY a.appointment_id DESC
             LIMIT 1'
        );
        $stmt->execute([':user_id' => $userId]);
        $last = (int)$stmt->fetchColumn();
        if ($last > 0) {
            return $last;
        }
    }

    $catalog = (int)$pdo->query(
        'SELECT hv.variant_id
         FROM hairstyle_variants hv
         JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
         WHERE hs.is_active = TRUE
         ORDER BY hv.variant_id
         LIMIT 1'
    )->fetchColumn();

    return $catalog;
}
