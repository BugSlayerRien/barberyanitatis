<?php
// Notifications API (customer + barber list / markRead / delete)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/schema_cache.php';

require_method('POST');

function ensure_notification_type_constraint(PDO $pdo): void
{
    static $done = false;
    if ($done || !schema_cache_should_run('notification_type_check', 86400)) {
        return;
    }

    $pdo->exec(
        "ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_notification_type_check"
    );
    $pdo->exec(
        "ALTER TABLE notifications ADD CONSTRAINT notifications_notification_type_check
         CHECK (notification_type IN ('Appointment', 'Reminder', 'Queue', 'Promotion', 'System', 'Payment'))"
    );

    schema_cache_done('notification_type_check');
    $done = true;
}

/**
 * @return array{recipient_type: string, recipient_id: int}
 */
function resolve_notification_recipient(array $input): array
{
    $explicitType = strtolower(trim((string)($input['recipientType'] ?? '')));
    $barberId = (int)($input['barberID'] ?? $input['barberId'] ?? 0);
    $userId = (int)($input['userID'] ?? $input['userId'] ?? 0);

    if ($explicitType === 'barber' || $barberId > 0) {
        if ($barberId <= 0) {
            json_response(['error' => 'Invalid barberID'], 422);
        }

        return ['recipient_type' => 'Barber', 'recipient_id' => $barberId];
    }

    if ($userId <= 0) {
        json_response(['error' => 'Invalid userID or barberID'], 422);
    }

    return ['recipient_type' => 'User', 'recipient_id' => $userId];
}

$input = get_json_input();
$action = trim((string)($input['action'] ?? 'list'));
$allowedActions = ['list', 'markRead', 'markAllRead', 'delete', 'unreadCount'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();
    ensure_notification_type_constraint($pdo);

    $recipient = resolve_notification_recipient($input);
    $recipientType = $recipient['recipient_type'];
    $recipientId = $recipient['recipient_id'];

    if ($action === 'unreadCount') {
        $countStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM notifications
             WHERE recipient_type = :recipient_type
               AND recipient_id = :recipient_id
               AND is_read = FALSE"
        );
        $countStmt->execute([
            ':recipient_type' => $recipientType,
            ':recipient_id' => $recipientId,
        ]);
        json_response(['unreadCount' => (int)$countStmt->fetchColumn()]);
    }

    if ($action === 'markRead') {
        $notificationID = (int)($input['notificationID'] ?? 0);
        if ($notificationID <= 0) {
            json_response(['error' => 'Invalid notificationID'], 422);
        }

        $stmt = $pdo->prepare(
            "UPDATE notifications
             SET is_read = TRUE
             WHERE notification_id = :notification_id
               AND recipient_type = :recipient_type
               AND recipient_id = :recipient_id"
        );
        $stmt->execute([
            ':notification_id' => $notificationID,
            ':recipient_type' => $recipientType,
            ':recipient_id' => $recipientId,
        ]);

        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Notification not found'], 404);
        }

        json_response(['message' => 'Notification marked as read']);
    }

    if ($action === 'markAllRead') {
        $stmt = $pdo->prepare(
            "UPDATE notifications
             SET is_read = TRUE
             WHERE recipient_type = :recipient_type
               AND recipient_id = :recipient_id
               AND is_read = FALSE"
        );
        $stmt->execute([
            ':recipient_type' => $recipientType,
            ':recipient_id' => $recipientId,
        ]);

        json_response([
            'message' => 'All notifications marked as read',
            'updatedCount' => $stmt->rowCount(),
        ]);
    }

    if ($action === 'delete') {
        $notificationID = (int)($input['notificationID'] ?? 0);
        if ($notificationID <= 0) {
            json_response(['error' => 'Invalid notificationID'], 422);
        }

        $stmt = $pdo->prepare(
            "DELETE FROM notifications
             WHERE notification_id = :notification_id
               AND recipient_type = :recipient_type
               AND recipient_id = :recipient_id"
        );
        $stmt->execute([
            ':notification_id' => $notificationID,
            ':recipient_type' => $recipientType,
            ':recipient_id' => $recipientId,
        ]);

        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Notification not found'], 404);
        }

        json_response(['message' => 'Notification deleted']);
    }

    $stmt = $pdo->prepare(
        "SELECT notification_id, title, message, is_read, created_at
         FROM notifications
         WHERE recipient_type = :recipient_type
           AND recipient_id = :recipient_id
         ORDER BY created_at DESC
         LIMIT 30"
    );
    $stmt->execute([
        ':recipient_type' => $recipientType,
        ':recipient_id' => $recipientId,
    ]);
    $rows = $stmt->fetchAll();

    $notifications = array_map(static function ($row) {
        return [
            'notificationID' => (int)$row['notification_id'],
            'title' => (string)$row['title'],
            'subtitle' => (string)$row['message'],
            'isRead' => (bool)$row['is_read'],
            'createdAt' => (string)$row['created_at'],
        ];
    }, $rows);

    $unreadStmt = $pdo->prepare(
        "SELECT COUNT(*) FROM notifications
         WHERE recipient_type = :recipient_type
           AND recipient_id = :recipient_id
           AND is_read = FALSE"
    );
    $unreadStmt->execute([
        ':recipient_type' => $recipientType,
        ':recipient_id' => $recipientId,
    ]);

    json_response([
        'notifications' => $notifications,
        'unreadCount' => (int)$unreadStmt->fetchColumn(),
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
