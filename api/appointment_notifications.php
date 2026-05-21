<?php
// Insert in-app notifications for appointment lifecycle (create + paid).

declare(strict_types=1);

function ensure_notification_types(PDO $pdo): void
{
    $pdo->exec(
        "ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_notification_type_check"
    );
    $pdo->exec(
        "ALTER TABLE notifications ADD CONSTRAINT notifications_notification_type_check
         CHECK (notification_type IN ('Appointment', 'Reminder', 'Queue', 'Promotion', 'System', 'Payment'))"
    );
}

/**
 * @param array{user_id:int,barber_id:int,booking_code:string,appointment_date?:string,start_time?:string} $ctx
 */
function notify_appointment_created(PDO $pdo, array $ctx): void
{
    ensure_notification_types($pdo);

    $userId = (int)($ctx['user_id'] ?? 0);
    $barberId = (int)($ctx['barber_id'] ?? 0);
    $code = (string)($ctx['booking_code'] ?? '');
    $date = (string)($ctx['appointment_date'] ?? '');
    $time = (string)($ctx['start_time'] ?? '');
    $when = trim($date . ($time !== '' ? ' at ' . $time : ''));

    if ($userId > 0) {
        $stmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :id, 'Appointment', :title, :message, TRUE)"
        );
        $stmt->execute([
            ':id' => $userId,
            ':title' => 'Appointment booked',
            ':message' => 'Booking ' . $code . ' is reserved' . ($when !== '' ? ' for ' . $when : '') . '. Complete payment to confirm.',
        ]);
    }

    if ($barberId > 0) {
        $stmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('Barber', :id, 'Appointment', :title, :message, TRUE)"
        );
        $stmt->execute([
            ':id' => $barberId,
            ':title' => 'New appointment',
            ':message' => 'Booking ' . $code . ' was created' . ($when !== '' ? ' for ' . $when : '') . '. Awaiting payment.',
        ]);
    }
}

/**
 * @param array{user_id:int,barber_id:int,booking_code:string} $ctx
 */
function notify_appointment_paid(PDO $pdo, array $ctx): void
{
    ensure_notification_types($pdo);

    $userId = (int)($ctx['user_id'] ?? 0);
    $barberId = (int)($ctx['barber_id'] ?? 0);
    $code = (string)($ctx['booking_code'] ?? '');

    if ($userId > 0) {
        $exists = $pdo->prepare(
            "SELECT 1 FROM notifications
             WHERE recipient_type = 'User' AND recipient_id = :id
               AND notification_type IN ('Appointment', 'Payment')
               AND title = 'Payment confirmed'
               AND message LIKE :pattern
             LIMIT 1"
        );
        $exists->execute([':id' => $userId, ':pattern' => '%' . $code . '%']);
        if (!$exists->fetchColumn()) {
            $stmt = $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
                 VALUES ('User', :id, 'Appointment', 'Payment confirmed', :message, TRUE)"
            );
            $stmt->execute([
                ':id' => $userId,
                ':message' => 'Your payment for booking ' . $code . ' was received. Your appointment is confirmed.',
            ]);
        }
    }

    if ($barberId > 0) {
        $exists = $pdo->prepare(
            "SELECT 1 FROM notifications
             WHERE recipient_type = 'Barber' AND recipient_id = :id
               AND notification_type IN ('Appointment', 'Payment')
               AND title = 'Payment received'
               AND message LIKE :pattern
             LIMIT 1"
        );
        $exists->execute([':id' => $barberId, ':pattern' => '%' . $code . '%']);
        if (!$exists->fetchColumn()) {
            $stmt = $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
                 VALUES ('Barber', :id, 'Appointment', 'Payment received', :message, TRUE)"
            );
            $stmt->execute([
                ':id' => $barberId,
                ':message' => 'Booking ' . $code . ' has been paid and is confirmed.',
            ]);
        }
    }
}
