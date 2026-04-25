<?php
// Notifications API (user list + markRead + delete)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? 'list'));
$allowedActions = ['list', 'markRead', 'delete'];
if (!in_array($action, $allowedActions, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

$userID = (int)($input['userID'] ?? 0);
if ($userID <= 0) {
    json_response(['error' => 'Invalid userID'], 422);
}

try {
    $pdo = get_db_connection();

    if ($action === 'markRead') {
        $notificationID = (int)($input['notificationID'] ?? 0);
        if ($notificationID <= 0) {
            json_response(['error' => 'Invalid notificationID'], 422);
        }

        $stmt = $pdo->prepare(
            "UPDATE notifications
             SET is_read = TRUE
             WHERE notification_id = :notification_id
               AND recipient_type = 'User'
               AND recipient_id = :recipient_id"
        );
        $stmt->execute([
            ':notification_id' => $notificationID,
            ':recipient_id' => $userID,
        ]);

        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Notification not found'], 404);
        }

        json_response(['message' => 'Notification marked as read']);
    }

    if ($action === 'delete') {
        $notificationID = (int)($input['notificationID'] ?? 0);
        if ($notificationID <= 0) {
            json_response(['error' => 'Invalid notificationID'], 422);
        }

        $stmt = $pdo->prepare(
            "DELETE FROM notifications
             WHERE notification_id = :notification_id
               AND recipient_type = 'User'
               AND recipient_id = :recipient_id"
        );
        $stmt->execute([
            ':notification_id' => $notificationID,
            ':recipient_id' => $userID,
        ]);

        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Notification not found'], 404);
        }

        json_response(['message' => 'Notification deleted']);
    }

    $stmt = $pdo->prepare(
        "SELECT notification_id, title, message, is_read, created_at
         FROM notifications
         WHERE recipient_type = 'User'
           AND recipient_id = :recipient_id
         ORDER BY created_at DESC
         LIMIT 30"
    );
    $stmt->execute([':recipient_id' => $userID]);
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

    json_response(['notifications' => $notifications]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}