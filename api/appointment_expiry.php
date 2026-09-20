<?php
// Expire appointments whose slot has passed while still awaiting payment.

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/schema_cache.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/slot_locking.php';

/**
 * Grace after the slot's end before an unpaid booking is written off, so a
 * customer paying at the chair a few minutes late is not cancelled mid-payment.
 */
function appointment_expiry_grace_minutes(): int
{
    $raw = trim((string)(getenv('APPOINTMENT_EXPIRY_GRACE_MINUTES')
        ?: ($_ENV['APPOINTMENT_EXPIRY_GRACE_MINUTES'] ?? '')));
    $minutes = $raw !== '' ? (int)$raw : 60;

    return $minutes >= 0 ? $minutes : 60;
}

/** How far ahead of the slot an unpaid customer gets a "payment due" nudge. */
function appointment_payment_due_lead_hours(): int
{
    $raw = trim((string)(getenv('APPOINTMENT_PAYMENT_DUE_LEAD_HOURS')
        ?: ($_ENV['APPOINTMENT_PAYMENT_DUE_LEAD_HOURS'] ?? '')));
    $hours = $raw !== '' ? (int)$raw : 24;

    return $hours > 0 ? $hours : 24;
}

/**
 * One-time marker so the payment-due nudge is not re-sent on every sweep.
 * A column rather than a notifications lookup: the sweep runs on list loads,
 * so this is checked far more often than it is written.
 */
function ensure_payment_due_notice_column(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS payment_due_notified_at TIMESTAMPTZ'
    );
}

/**
 * The cancel UPDATE below writes cancel_reason. booking.php ensures that column
 * too, but this file must not depend on having been reached through that
 * endpoint -- duplicated here so the sweep is safe to call from anywhere.
 */
function ensure_expiry_cancel_reason_column(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS cancel_reason TEXT'
    );
}

/**
 * Cancel bookings still sitting in PendingPayment after their slot has passed.
 *
 * Only the unpaid case is handled here. A *paid* past appointment is already
 * resolved by auto_complete_due_appointments() in shop_schedule.php, which
 * completes stale Scheduled/CheckedIn rows and records revenue -- this function
 * deliberately does not compete with that.
 *
 * MUST run after sync_paid_appointments_from_payments() /
 * sync_paid_groups_from_payments(), which promote rows that actually paid but
 * were never flipped to Scheduled. Running first would cancel paid bookings.
 *
 * Group bookings are cancelled as a whole unit, never member-by-member, so a
 * group cannot end up half-cancelled.
 *
 * @return int number of appointment rows cancelled
 */
function expire_unpaid_past_appointments(PDO $pdo, bool $force = false): int
{
    static $done = false;
    if (!$force) {
        if ($done) {
            return 0;
        }
        if (!schema_cache_should_run('expire_unpaid_past_appointments', 120)) {
            $done = true;

            return 0;
        }
    }

    schema_ensure_once('appointments.expiry_cancel_reason', static function () use ($pdo): void {
        ensure_expiry_cancel_reason_column($pdo);
    });

    $endTs = shop_local_ts_sql('appointment_date', 'end_time');
    $startTs = shop_local_ts_sql('appointment_date', 'start_time');
    $duration = shop_appointment_duration_minutes();
    $grace = appointment_expiry_grace_minutes();

    // end_time is not always populated; fall back to start + the shop's default
    // appointment length so a row with a blank end_time still expires.
    $slotEndExpr = "CASE
            WHEN end_time IS NOT NULL
                 AND end_time <> '00:00:00'::time
                 AND end_time > start_time
            THEN {$endTs}
            ELSE {$startTs} + make_interval(mins => :duration)
        END";

    $stmt = $pdo->prepare(
        "SELECT appointment_id, booking_group_id, user_id, barber_id, booking_code
         FROM appointments
         WHERE status = 'PendingPayment'
           AND ({$slotEndExpr}) + make_interval(mins => :grace) <= NOW()
         ORDER BY appointment_id"
    );
    $stmt->execute([':duration' => $duration, ':grace' => $grace]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if ($rows === []) {
        if (!$force) {
            schema_cache_done('expire_unpaid_past_appointments');
        }

        return 0;
    }

    $cancelReason = 'Automatically cancelled: payment was not completed before the appointment time.';
    $cancelled = 0;
    $seenGroups = [];

    $notifyStmt = $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
         VALUES (:recipient_type, :recipient_id, 'Appointment', :title, :message, TRUE)"
    );

    foreach ($rows as $row) {
        $groupId = isset($row['booking_group_id']) ? (int)$row['booking_group_id'] : 0;
        if ($groupId > 0) {
            if (isset($seenGroups[$groupId])) {
                continue;
            }
            $seenGroups[$groupId] = true;
        }

        $appointmentId = (int)$row['appointment_id'];

        // Each unit is atomic on its own, but the caller may already own a
        // transaction -- PDO cannot nest beginTransaction, so fall back to a
        // savepoint and leave the outer transaction intact either way.
        $nested = $pdo->inTransaction();

        try {
            if ($nested) {
                $pdo->exec('SAVEPOINT appointment_expiry_unit');
            } else {
                $pdo->beginTransaction();
            }

            if ($groupId > 0) {
                $update = $pdo->prepare(
                    "UPDATE appointments
                     SET status = 'Cancelled', cancel_reason = :reason, updated_at = CURRENT_TIMESTAMP
                     WHERE booking_group_id = :group_id
                       AND status = 'PendingPayment'"
                );
                $update->execute([':reason' => $cancelReason, ':group_id' => $groupId]);
            } else {
                $update = $pdo->prepare(
                    "UPDATE appointments
                     SET status = 'Cancelled', cancel_reason = :reason, updated_at = CURRENT_TIMESTAMP
                     WHERE appointment_id = :appointment_id
                       AND status = 'PendingPayment'"
                );
                $update->execute([
                    ':reason' => $cancelReason,
                    ':appointment_id' => $appointmentId,
                ]);
            }

            $affected = $update->rowCount();
            if ($affected === 0) {
                // Something else resolved it between the SELECT and here.
                if ($nested) {
                    $pdo->exec('ROLLBACK TO SAVEPOINT appointment_expiry_unit');
                } else {
                    $pdo->rollBack();
                }
                continue;
            }

            // PendingPayment is not supposed to hold a calendar slot (see
            // slot_locking.php), but reconcile_pending_payment_slots exists
            // because it sometimes does. Release defensively.
            release_slots_for_appointment($pdo, $appointmentId);

            if ($nested) {
                $pdo->exec('RELEASE SAVEPOINT appointment_expiry_unit');
            } else {
                $pdo->commit();
            }
            $cancelled += $affected;
        } catch (Throwable $e) {
            try {
                if ($nested) {
                    $pdo->exec('ROLLBACK TO SAVEPOINT appointment_expiry_unit');
                } elseif ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
            } catch (Throwable $rollbackError) {
                error_log('Expiry rollback failed for #' . $appointmentId . ': ' . $rollbackError->getMessage());
            }
            error_log('Unpaid appointment expiry skipped for #' . $appointmentId . ': ' . $e->getMessage());
            continue;
        }

        $code = (string)($row['booking_code'] ?? '');
        $userId = (int)($row['user_id'] ?? 0);
        $barberId = (int)($row['barber_id'] ?? 0);

        try {
            if ($userId > 0) {
                $notifyStmt->execute([
                    ':recipient_type' => 'User',
                    ':recipient_id' => $userId,
                    ':title' => 'Booking cancelled',
                    ':message' => 'Booking ' . $code . ' was cancelled because payment was not completed before the appointment time.',
                ]);
            }
            if ($barberId > 0) {
                $notifyStmt->execute([
                    ':recipient_type' => 'Barber',
                    ':recipient_id' => $barberId,
                    ':title' => 'Booking cancelled',
                    ':message' => 'Booking ' . $code . ' was cancelled automatically: payment was never completed.',
                ]);
            }
        } catch (Throwable $e) {
            // The cancellation itself is committed; a failed notice must not
            // make the caller think the sweep failed.
            error_log('Expiry notification skipped for #' . $appointmentId . ': ' . $e->getMessage());
        }
    }

    if (!$force) {
        schema_cache_done('expire_unpaid_past_appointments');
    }

    return $cancelled;
}

/**
 * Nudge customers whose appointment is coming up while still unpaid, before
 * expire_unpaid_past_appointments() writes it off.
 *
 * Sent at most once per appointment (payment_due_notified_at). This piggybacks
 * on request traffic rather than a scheduler, so delivery is best-effort: it
 * fires the first time any sweep runs inside the lead window. A dependable
 * reminder needs a real cron hitting this function.
 *
 * @return int number of reminders sent
 */
function notify_unpaid_appointments_due_soon(PDO $pdo, bool $force = false): int
{
    static $done = false;
    if (!$force) {
        if ($done) {
            return 0;
        }
        if (!schema_cache_should_run('notify_unpaid_appointments_due_soon', 300)) {
            $done = true;

            return 0;
        }
    }

    schema_ensure_once('appointments.payment_due_notice', static function () use ($pdo): void {
        ensure_payment_due_notice_column($pdo);
    });

    $startTs = shop_local_ts_sql('appointment_date', 'start_time');
    $leadHours = appointment_payment_due_lead_hours();

    $stmt = $pdo->prepare(
        "SELECT appointment_id, user_id, booking_code, appointment_date, start_time
         FROM appointments
         WHERE status = 'PendingPayment'
           AND payment_due_notified_at IS NULL
           AND {$startTs} > NOW()
           AND {$startTs} <= NOW() + make_interval(hours => :lead_hours)
         ORDER BY appointment_id"
    );
    $stmt->execute([':lead_hours' => $leadHours]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $sent = 0;
    if ($rows !== []) {
        $notifyStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :user_id, 'Payment', :title, :message, TRUE)"
        );
        // Marked regardless of delivery so a persistently failing row cannot be
        // retried forever on every sweep.
        $markStmt = $pdo->prepare(
            'UPDATE appointments
             SET payment_due_notified_at = NOW()
             WHERE appointment_id = :appointment_id'
        );

        foreach ($rows as $row) {
            $userId = (int)($row['user_id'] ?? 0);
            $appointmentId = (int)$row['appointment_id'];
            $code = (string)($row['booking_code'] ?? '');
            $when = trim((string)($row['appointment_date'] ?? '') . ' ' . (string)($row['start_time'] ?? ''));

            try {
                if ($userId > 0) {
                    $notifyStmt->execute([
                        ':user_id' => $userId,
                        ':title' => 'Payment still needed',
                        ':message' => 'Booking ' . $code . ($when !== '' ? ' on ' . $when : '')
                            . ' is not paid yet. Complete payment to confirm it, or it will be cancelled after the appointment time.',
                    ]);
                    $sent++;
                }
                $markStmt->execute([':appointment_id' => $appointmentId]);
            } catch (Throwable $e) {
                error_log('Payment-due notice skipped for #' . $appointmentId . ': ' . $e->getMessage());
            }
        }
    }

    if (!$force) {
        schema_cache_done('notify_unpaid_appointments_due_soon');
    }

    return $sent;
}
