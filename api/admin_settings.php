<?php
// Admin system settings: shop hours, notifications, backups, exports.

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';

function ensure_system_settings_table(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS system_settings (
            setting_key VARCHAR(100) PRIMARY KEY,
            setting_value TEXT,
            setting_type TEXT NOT NULL DEFAULT 'String',
            category VARCHAR(50),
            description TEXT,
            is_editable BOOLEAN NOT NULL DEFAULT TRUE,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );
}

function setting_defaults(): array
{
    return [
        'email_notifications_enabled' => '0',
        'notification_from_email' => 'noreply@barberyatatis.local',
        'auto_backup_enabled' => '0',
        'force_mfa' => '0',
        'shop_open_time' => '09:00',
        'shop_close_time' => '20:00',
    ];
}

function load_settings_map(PDO $pdo): array
{
    ensure_system_settings_table($pdo);
    $defaults = setting_defaults();
    $rows = $pdo->query('SELECT setting_key, setting_value FROM system_settings')->fetchAll(PDO::FETCH_ASSOC);
    $map = $defaults;
    foreach ($rows as $row) {
        $map[(string)$row['setting_key']] = (string)($row['setting_value'] ?? '');
    }
    return $map;
}

function upsert_setting(PDO $pdo, string $key, string $value, string $type = 'String', string $category = 'admin'): void
{
    $stmt = $pdo->prepare(
        "INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_editable, updated_at)
         VALUES (:setting_key, :setting_value, :setting_type, :category, '', TRUE, NOW())
         ON CONFLICT (setting_key)
         DO UPDATE SET setting_value = EXCLUDED.setting_value, updated_at = NOW()"
    );
    $stmt->execute([
        ':setting_key' => $key,
        ':setting_value' => $value,
        ':setting_type' => $type,
        ':category' => $category,
    ]);
}

function settings_payload(array $map): array
{
    return [
        'emailNotificationsEnabled' => (int)($map['email_notifications_enabled'] === '1' || strtolower($map['email_notifications_enabled']) === 'true'),
        'notificationFromEmail' => $map['notification_from_email'] ?? 'noreply@barberyatatis.local',
        'autoBackupEnabled' => (int)($map['auto_backup_enabled'] === '1' || strtolower($map['auto_backup_enabled']) === 'true'),
        'forceMfa' => (int)($map['force_mfa'] === '1' || strtolower($map['force_mfa']) === 'true'),
        'openTime' => $map['shop_open_time'] ?? '09:00',
        'closeTime' => $map['shop_close_time'] ?? '20:00',
    ];
}

function export_table_csv(PDO $pdo, string $table): string
{
    $allowed = [
        'users' => 'user_id, full_name, email, phone, is_active, created_at',
        'barbers' => 'barber_id, full_name, email, specialty, is_active, created_at',
        'staff_users' => 'staff_id, full_name, email, role, is_active, created_at',
        'services' => 'service_id, service_name, category, base_price, base_duration, is_active',
        'appointments' => 'appointment_id, booking_code, user_id, barber_id, appointment_date, start_time, status, created_at',
        'notifications' => 'notification_id, recipient_type, recipient_id, notification_type, title, message, is_sent, created_at',
    ];

    if (!isset($allowed[$table])) {
        json_response(['error' => 'Unsupported export table'], 422);
    }

    $stmt = $pdo->query("SELECT {$allowed[$table]} FROM {$table} ORDER BY 1 DESC LIMIT 5000");
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if (!$rows) {
        return implode(',', array_map(static fn(string $col): string => trim(explode(',', $col)[0]), explode(',', $allowed[$table]))) . "\n";
    }

    $columns = array_keys($rows[0]);
    $lines = [implode(',', $columns)];
    foreach ($rows as $row) {
        $escaped = array_map(static function ($value): string {
            $text = str_replace('"', '""', (string)$value);
            return '"' . $text . '"';
        }, array_values($row));
        $lines[] = implode(',', $escaped);
    }

    return implode("\n", $lines);
}

function build_backup_payload(PDO $pdo): array
{
    $tables = ['users', 'barbers', 'staff_users', 'services', 'appointments', 'appointment_details', 'time_slots', 'notifications', 'system_settings'];
    $backup = [
        'generatedAt' => (new DateTimeImmutable('now', new DateTimeZone(shop_timezone())))->format(DateTimeInterface::ATOM),
        'tables' => [],
    ];

    foreach ($tables as $table) {
        try {
            $rows = $pdo->query("SELECT * FROM {$table} ORDER BY 1 DESC LIMIT 2000")->fetchAll(PDO::FETCH_ASSOC);
            $backup['tables'][$table] = $rows;
        } catch (Throwable) {
            $backup['tables'][$table] = [];
        }
    }

    return $backup;
}

function queue_pending_notifications(PDO $pdo, int $limit = 50): int
{
    $stmt = $pdo->prepare(
        "SELECT notification_id, recipient_type, recipient_id, title, message
         FROM notifications
         WHERE is_sent = FALSE
         ORDER BY created_at ASC
         LIMIT :limit"
    );
    $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $markSent = $pdo->prepare(
        'UPDATE notifications SET is_sent = TRUE, sent_at = NOW() WHERE notification_id = :notification_id'
    );

    $sent = 0;
    foreach ($rows as $row) {
        $markSent->execute([':notification_id' => (int)$row['notification_id']]);
        $sent++;
    }

    return $sent;
}

function send_test_notification_email(PDO $pdo, string $toEmail, string $fromEmail): array
{
    $toEmail = trim($toEmail);
    if ($toEmail === '' || !filter_var($toEmail, FILTER_VALIDATE_EMAIL)) {
        return ['success' => false, 'message' => 'Invalid recipient email.'];
    }

    $subject = 'Barberya ni Tatis — test notification';
    $body = "This is a test email from the Tatis Barbershop admin settings panel.\nSent at: " . date('c');
    $headers = 'From: ' . $fromEmail . "\r\n" . 'Content-Type: text/plain; charset=UTF-8';

    $queued = $pdo->prepare(
        "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
         VALUES ('User', 0, 'System', :title, :message, FALSE)
         RETURNING notification_id"
    );
    $queued->execute([
        ':title' => $subject,
        ':message' => $body . ' (recipient: ' . $toEmail . ')',
    ]);
    $notificationId = (int)$queued->fetchColumn();

    $mailed = false;
    if (function_exists('mail')) {
        $mailed = @mail($toEmail, $subject, $body, $headers);
    }

    if ($mailed) {
        $pdo->prepare('UPDATE notifications SET is_sent = TRUE, sent_at = NOW() WHERE notification_id = :id')
            ->execute([':id' => $notificationId]);
        return ['success' => true, 'message' => 'Test email sent to ' . $toEmail];
    }

    return [
        'success' => true,
        'message' => 'Email queued in notifications (ID ' . $notificationId . '). Configure PHP mail/SMTP on the server to deliver externally.',
        'queuedNotificationId' => $notificationId,
    ];
}

try {
    $pdo = get_db_connection();
    ensure_system_settings_table($pdo);
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

    if ($method === 'GET') {
        json_response(['settings' => settings_payload(load_settings_map($pdo))]);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = strtolower(trim((string)($input['action'] ?? 'update')));

    if ($action === 'update') {
        // Shop hours are managed via operating_schedule.php (shop_weekly_hours).
        upsert_setting($pdo, 'email_notifications_enabled', !empty($input['emailNotificationsEnabled']) ? '1' : '0', 'Boolean', 'notifications');
        upsert_setting($pdo, 'auto_backup_enabled', !empty($input['autoBackupEnabled']) ? '1' : '0', 'Boolean', 'backup');
        upsert_setting($pdo, 'force_mfa', !empty($input['forceMfa']) ? '1' : '0', 'Boolean', 'security');
        if (!empty($input['notificationFromEmail'])) {
            upsert_setting($pdo, 'notification_from_email', trim((string)$input['notificationFromEmail']), 'String', 'notifications');
        }

        json_response([
            'message' => 'Settings saved.',
            'settings' => settings_payload(load_settings_map($pdo)),
        ]);
    }

    if ($action === 'exportcsv') {
        $table = trim((string)($input['table'] ?? ''));
        json_response(['csv' => export_table_csv($pdo, $table)]);
    }

    if ($action === 'downloadbackup') {
        $backup = build_backup_payload($pdo);
        $json = json_encode($backup, JSON_PRETTY_PRINT);
        if ($json === false) {
            json_response(['error' => 'Unable to build backup'], 500);
        }

        $dir = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'storage' . DIRECTORY_SEPARATOR . 'backups';
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            json_response(['error' => 'Unable to create backup directory'], 500);
        }

        $fileName = 'tatis_backup_' . date('Ymd_His') . '.json';
        $path = $dir . DIRECTORY_SEPARATOR . $fileName;
        file_put_contents($path, $json);

        json_response([
            'message' => 'Backup created.',
            'fileName' => $fileName,
            'downloadUrl' => '../storage/backups/' . $fileName,
            'backup' => $backup,
        ]);
    }

    if ($action === 'sendtestemail') {
        $map = load_settings_map($pdo);
        $to = trim((string)($input['email'] ?? ''));
        $from = $map['notification_from_email'] ?? 'noreply@barberyatatis.local';
        $result = send_test_notification_email($pdo, $to, $from);
        json_response($result, $result['success'] ? 200 : 422);
    }

    if ($action === 'processnotifications') {
        $map = load_settings_map($pdo);
        if (($map['email_notifications_enabled'] ?? '0') !== '1') {
            json_response(['message' => 'Email notifications are disabled in settings.', 'processed' => 0]);
        }
        $processed = queue_pending_notifications($pdo, 100);
        json_response(['message' => "Marked {$processed} notification(s) as sent.", 'processed' => $processed]);
    }

    if ($action === 'importservicescsv') {
        $csvText = (string)($input['csvText'] ?? '');
        if (trim($csvText) === '') {
            json_response(['error' => 'CSV text is required'], 422);
        }
        $lines = preg_split('/\r\n|\r|\n/', trim($csvText)) ?: [];
        if (count($lines) < 2) {
            json_response(['error' => 'CSV must include a header row and at least one data row'], 422);
        }
        $header = str_getcsv(array_shift($lines));
        $imported = 0;
        $stmt = $pdo->prepare(
            "INSERT INTO services (service_code, service_name, description, base_duration, base_price, category, is_active)
             VALUES (:service_code, :service_name, :description, :base_duration, :base_price, :category, TRUE)
             ON CONFLICT (service_code)
             DO UPDATE SET
                service_name = EXCLUDED.service_name,
                description = EXCLUDED.description,
                base_duration = EXCLUDED.base_duration,
                base_price = EXCLUDED.base_price,
                category = EXCLUDED.category,
                is_active = TRUE"
        );
        foreach ($lines as $line) {
            if (trim($line) === '') {
                continue;
            }
            $cols = str_getcsv($line);
            $row = [];
            foreach ($header as $index => $colName) {
                $row[strtolower(trim($colName))] = $cols[$index] ?? '';
            }
            $serviceCode = $row['service_code'] ?? $row['code'] ?? ('SRV-' . strtoupper(substr(sha1($line), 0, 8)));
            $stmt->execute([
                ':service_code' => $serviceCode,
                ':service_name' => $row['service_name'] ?? $row['name'] ?? 'Service',
                ':description' => $row['description'] ?? '',
                ':base_duration' => (int)($row['base_duration'] ?? $row['duration'] ?? 60),
                ':base_price' => (float)($row['base_price'] ?? $row['price'] ?? 100),
                ':category' => $row['category'] ?? 'Haircut',
            ]);
            $imported++;
        }
        json_response(['message' => "Imported {$imported} service row(s).", 'imported' => $imported]);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response(['error' => 'Unexpected error', 'details' => $e->getMessage()], 500);
}
