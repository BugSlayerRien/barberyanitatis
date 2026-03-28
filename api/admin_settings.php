<?php
// Admin system settings API (get/update + CSV export/import)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'POST') {
    json_response(['error' => 'Method not allowed'], 405);
}

function get_setting(PDO $pdo, string $key, string $default): string
{
    $stmt = $pdo->prepare('SELECT setting_value FROM system_settings WHERE setting_key = :key');
    $stmt->execute([':key' => $key]);
    $value = $stmt->fetchColumn();
    return $value !== false ? (string)$value : $default;
}

function set_setting(PDO $pdo, string $key, string $value): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO system_settings (setting_key, setting_value)
         VALUES (:key, :value)
         ON CONFLICT (setting_key) DO UPDATE SET setting_value = EXCLUDED.setting_value'
    );
    $stmt->execute([':key' => $key, ':value' => $value]);
}

function to_csv(array $rows): string
{
    if (count($rows) === 0) {
        return "";
    }
    $headers = array_keys($rows[0]);
    $fh = fopen('php://temp', 'r+');
    fputcsv($fh, $headers);
    foreach ($rows as $row) {
        $line = [];
        foreach ($headers as $header) {
            $line[] = $row[$header] ?? '';
        }
        fputcsv($fh, $line);
    }
    rewind($fh);
    $csv = stream_get_contents($fh);
    fclose($fh);
    return $csv;
}

try {
    $pdo = get_db_connection();

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = get_json_input();
        $action = $input['action'] ?? 'update';

        if ($action === 'update') {
            set_setting($pdo, 'email_notifications_enabled', (string)((int)($input['emailNotificationsEnabled'] ?? 0)));
            set_setting($pdo, 'open_time', (string)($input['openTime'] ?? '09:00'));
            set_setting($pdo, 'close_time', (string)($input['closeTime'] ?? '18:00'));
            set_setting($pdo, 'force_mfa', (string)((int)($input['forceMfa'] ?? 0)));
            set_setting($pdo, 'auto_backup_enabled', (string)((int)($input['autoBackupEnabled'] ?? 0)));

            $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
                 VALUES ('Admin', 0, 'System', 'System settings updated', 'Admin updated system settings')"
            )->execute();

            json_response(['message' => 'Settings updated']);
        }

        if ($action === 'exportCsv') {
            $table = $input['table'] ?? '';
            $allowed = [
                'users' => 'SELECT user_id, full_name, email, phone, is_active, created_at FROM users',
                'barbers' => 'SELECT barber_id, full_name, email, specialty, years_experience, rating, is_active, created_at FROM barbers',
                'services' => 'SELECT service_id, service_code, service_name, description, base_duration, base_price, category, is_active, created_at FROM services',
                'appointments' => 'SELECT appointment_id, booking_code, user_id, barber_id, appointment_date, start_time, end_time, status, created_at FROM appointments',
            ];
            if (!isset($allowed[$table])) {
                json_response(['error' => 'Invalid table'], 422);
            }
            $rows = $pdo->query($allowed[$table])->fetchAll();
            json_response(['csv' => to_csv($rows)]);
        }

        if ($action === 'importServicesCsv') {
            $csvText = (string)($input['csvText'] ?? '');
            if ($csvText === '') {
                json_response(['error' => 'Missing CSV data'], 422);
            }

            $fh = fopen('php://temp', 'r+');
            fwrite($fh, $csvText);
            rewind($fh);
            $headers = fgetcsv($fh);
            if (!$headers) {
                fclose($fh);
                json_response(['error' => 'Invalid CSV format'], 422);
            }

            $pdo->beginTransaction();
            $stmt = $pdo->prepare(
                'INSERT INTO services (service_code, service_name, description, base_duration, base_price, category, is_active)
                 VALUES (:service_code, :service_name, :description, :base_duration, :base_price, :category, :is_active)
                                 ON CONFLICT (service_code) DO UPDATE
                                     SET service_name = EXCLUDED.service_name,
                                             description = EXCLUDED.description,
                                             base_duration = EXCLUDED.base_duration,
                                             base_price = EXCLUDED.base_price,
                                             category = EXCLUDED.category,
                                             is_active = EXCLUDED.is_active'
            );

            $rowCount = 0;
            while (($row = fgetcsv($fh)) !== false) {
                $data = array_combine($headers, $row);
                if (!$data) {
                    continue;
                }
                $code = trim((string)($data['service_code'] ?? ''));
                $name = trim((string)($data['service_name'] ?? ''));
                if ($code === '' || $name === '') {
                    continue;
                }
                $stmt->execute([
                    ':service_code' => $code,
                    ':service_name' => $name,
                    ':description' => $data['description'] ?? null,
                    ':base_duration' => (int)($data['base_duration'] ?? 0),
                    ':base_price' => (float)($data['base_price'] ?? 0),
                    ':category' => $data['category'] ?? 'Haircut',
                    ':is_active' => isset($data['is_active']) ? (int)$data['is_active'] : 1,
                ]);
                $rowCount++;
            }
            fclose($fh);
            $pdo->commit();

            $pdo->prepare(
                "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message)
                 VALUES ('Admin', 0, 'System', 'Services CSV imported', 'Imported services from CSV')"
            )->execute();

            json_response(['message' => 'Import complete', 'rows' => $rowCount]);
        }

        json_response(['error' => 'Invalid action'], 400);
    }

    $settings = [
        'emailNotificationsEnabled' => (int)get_setting($pdo, 'email_notifications_enabled', '1'),
        'openTime' => get_setting($pdo, 'open_time', '09:00'),
        'closeTime' => get_setting($pdo, 'close_time', '18:00'),
        'forceMfa' => (int)get_setting($pdo, 'force_mfa', '0'),
        'autoBackupEnabled' => (int)get_setting($pdo, 'auto_backup_enabled', '0'),
    ];

    json_response(['settings' => $settings]);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
