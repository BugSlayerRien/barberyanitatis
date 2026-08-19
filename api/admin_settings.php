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

/**
 * @return array<string, mixed>
 */
function settings_schedule_summary(PDO $pdo): array
{
    $dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    try {
        $cfg = function_exists('shop_schedule_config') ? shop_schedule_config(true) : [
            'slot_minutes' => 60,
            'appointment_minutes' => 60,
            'walkin_minutes' => 35,
            'timezone' => function_exists('shop_timezone') ? shop_timezone() : 'Asia/Manila',
        ];

        $weekly = $pdo->query(
            'SELECT day_of_week, is_closed, open_time, close_time
             FROM shop_weekly_hours
             ORDER BY day_of_week'
        )->fetchAll(PDO::FETCH_ASSOC);

        $byDow = [];
        foreach ($weekly as $row) {
            $byDow[(int)$row['day_of_week']] = $row;
        }
        $openDays = [];
        foreach ([1, 2, 3, 4, 5, 6, 0] as $dow) {
            $row = $byDow[$dow] ?? null;
            if ($row === null || !empty($row['is_closed'])) {
                continue;
            }
            $openDays[] = $dayNames[$dow] . ' '
                . substr((string)$row['open_time'], 0, 5) . '-'
                . substr((string)$row['close_time'], 0, 5);
        }

        $upcomingClosures = (int)$pdo->query(
            "SELECT COUNT(*) FROM shop_closed_dates WHERE closed_date >= CURRENT_DATE"
        )->fetchColumn();

        $breakCount = (int)$pdo->query('SELECT COUNT(*) FROM shop_break_windows')->fetchColumn();

        return [
            'available' => true,
            'openDaysSummary' => $openDays !== []
                ? implode(' · ', $openDays)
                : ($weekly === [] ? 'Weekly hours not configured yet.' : 'No open days configured.'),
            'breakCount' => $breakCount,
            'upcomingClosures' => $upcomingClosures,
            'timezone' => (string)($cfg['timezone'] ?? (function_exists('shop_timezone') ? shop_timezone() : 'Asia/Manila')),
            'slotMinutes' => (int)($cfg['slot_minutes'] ?? 60),
            'appointmentMinutes' => (int)($cfg['appointment_minutes'] ?? 60),
            'walkinMinutes' => (int)($cfg['walkin_minutes'] ?? 35),
        ];
    } catch (Throwable $e) {
        return [
            'available' => false,
            'error' => 'Could not load schedule summary.',
            'openDaysSummary' => '',
            'breakCount' => 0,
            'upcomingClosures' => 0,
        ];
    }
}

/**
 * @return array<string, mixed>
 */
function settings_backup_info(): array
{
    $dir = api_project_root() . DIRECTORY_SEPARATOR . 'storage' . DIRECTORY_SEPARATOR . 'backups';
    $latest = null;
    if (is_dir($dir)) {
        $files = glob($dir . DIRECTORY_SEPARATOR . 'tatis_backup_*.json') ?: [];
        rsort($files);
        if ($files !== []) {
            $path = $files[0];
            $latest = [
                'fileName' => basename($path),
                'modifiedAt' => date('c', (int)filemtime($path)),
                'sizeBytes' => (int)filesize($path),
            ];
        }
    }

    return [
        'manualBackupSupported' => true,
        'manualRestoreSupported' => true,
        'automaticBackupImplemented' => false,
        'latest' => $latest,
        'note' => 'Manual JSON backups are supported. Automatic scheduled backups are not implemented.',
    ];
}

/**
 * @return array<string, mixed>
 */
function settings_notification_meta(PDO $pdo): array
{
    $pending = 0;
    try {
        $pending = (int)$pdo->query(
            'SELECT COUNT(*) FROM notifications WHERE is_sent = FALSE'
        )->fetchColumn();
    } catch (Throwable $e) {
        $pending = 0;
    }

    return [
        'pendingQueueCount' => $pending,
        'inAppEvents' => [
            'appointmentConfirmation' => true,
            'appointmentReminderEmail' => false,
            'cancellation' => true,
            'reschedule' => true,
            'payment' => true,
        ],
        'notes' => [
            'In-app notifications are created for bookings, cancellations, reschedules, and payments.',
            'Dedicated email reminder scheduling is not implemented.',
            'Queue processing marks pending notification rows as sent; outbound SMTP is only attempted for the test email action via PHP mail().',
        ],
    ];
}

/**
 * @return array<string, mixed>
 */
function settings_system_info(PDO $pdo): array
{
    $dbOk = true;
    try {
        $pdo->query('SELECT 1');
    } catch (Throwable $e) {
        $dbOk = false;
    }

    $env = strtolower(trim((string)(
        getenv('APP_ENV') ?: ($_ENV['APP_ENV'] ?? getenv('ENVIRONMENT') ?: ($_ENV['ENVIRONMENT'] ?? 'development'))
    )));
    if ($env === '') {
        $env = 'development';
    }

    $version = trim((string)(getenv('APP_VERSION') ?: ($_ENV['APP_VERSION'] ?? '')));
    if ($version === '') {
        $version = '1.0.0';
    }

    return [
        'applicationVersion' => $version,
        'environment' => $env,
        'apiStatus' => 'ok',
        'databaseStatus' => $dbOk ? 'ok' : 'error',
        'phpVersion' => PHP_VERSION,
        'checkedAt' => date('c'),
        'capabilities' => [
            'emailNotificationsToggle' => true,
            'testEmail' => true,
            'notificationQueueMarkSent' => true,
            'staffMfaEnforced' => false,
            'automaticBackups' => false,
            'manualBackupDownload' => true,
            'manualBackupRestore' => true,
            'aiProviderEditableInUi' => false,
        ],
    ];
}

/**
 * @return array<string, mixed>
 */
function settings_ai_status_safe(): array
{
    // Inline lightweight status (no secrets) — mirrors ai_status.php try-on block.
    $get = static function (string $key, string $default = '') {
        $v = getenv($key);
        if ($v === false || $v === '') {
            $v = $_ENV[$key] ?? $default;
        }
        return trim((string)$v);
    };
    $configured = static function (string ...$keys) use ($get): bool {
        foreach ($keys as $key) {
            $v = $get($key);
            if ($v !== '' && $v !== 'REPLACE_WITH_GEMINI_KEY' && !str_starts_with($v, 'REPLACE_')) {
                return true;
            }
        }
        return false;
    };

    $provider = strtolower($get('AI_TRYON_PROVIDER'));
    if (!in_array($provider, ['gemini', 'grok', 'replicate'], true)) {
        if ($configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY')) {
            $provider = 'gemini';
        } elseif ($configured('XAI_API_KEY')) {
            $provider = 'grok';
        } elseif ($configured('REPLICATE_API_TOKEN')) {
            $provider = 'replicate';
        } else {
            $provider = 'none';
        }
    }

    $model = match ($provider) {
        'gemini' => $get('GEMINI_IMAGE_MODEL', 'gemini-2.5-flash-image'),
        'grok' => $get('GROK_IMAGE_MODEL', 'grok-imagine-image'),
        'replicate' => ($m = $get('REPLICATE_MODEL')) !== '' ? $m : 'replicate',
        default => 'n/a',
    };

    $limitRaw = $get('AI_TRYON_STYLE_LIMIT', '3');
    $limit = ctype_digit($limitRaw) ? (int)$limitRaw : 3;
    $unlimited = in_array(strtolower($get('AI_TRYON_UNLIMITED')), ['1', 'true', 'yes', 'on'], true);

    $providerOk = match ($provider) {
        'gemini' => $configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY'),
        'grok' => $configured('XAI_API_KEY'),
        'replicate' => $configured('REPLICATE_API_TOKEN'),
        default => false,
    };

    return [
        'provider' => $provider,
        'model' => $model,
        'configured' => $providerOk,
        'styleLimit' => $limit,
        'unlimited' => $unlimited,
        'availableProviders' => [
            'gemini' => $configured('GEMINI_IMAGE_API_KEY', 'AI_API_KEY', 'GEMINI_API_KEY'),
            'grok' => $configured('XAI_API_KEY'),
            'replicate' => $configured('REPLICATE_API_TOKEN'),
        ],
        'editableInAdminUi' => false,
        'note' => 'Provider and models are controlled by server .env. API keys are never exposed here.',
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

/**
 * @return list<string>
 */
function backup_table_allowlist(): array
{
    return ['users', 'barbers', 'staff_users', 'services', 'appointments', 'appointment_details', 'time_slots', 'notifications', 'system_settings'];
}

function build_backup_payload(PDO $pdo): array
{
    $backup = [
        'generatedAt' => (new DateTimeImmutable('now', new DateTimeZone(shop_timezone())))->format(DateTimeInterface::ATOM),
        'tables' => [],
    ];

    foreach (backup_table_allowlist() as $table) {
        try {
            $rows = $pdo->query("SELECT * FROM {$table} ORDER BY 1 DESC LIMIT 2000")->fetchAll(PDO::FETCH_ASSOC);
            $backup['tables'][$table] = $rows;
        } catch (Throwable) {
            $backup['tables'][$table] = [];
        }
    }

    return $backup;
}

/**
 * @return list<string>
 */
function table_column_names(PDO $pdo, string $table): array
{
    $stmt = $pdo->prepare(
        "SELECT column_name
         FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = :table
         ORDER BY ordinal_position"
    );
    $stmt->execute([':table' => $table]);
    return array_map(static fn(array $row): string => (string)$row['column_name'], $stmt->fetchAll(PDO::FETCH_ASSOC));
}

function table_has_identity(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare(
        "SELECT 1
         FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = :table
           AND is_identity = 'YES'
         LIMIT 1"
    );
    $stmt->execute([':table' => $table]);
    return (bool)$stmt->fetchColumn();
}

function reset_table_identity(PDO $pdo, string $table): void
{
    $stmt = $pdo->prepare(
        "SELECT column_name
         FROM information_schema.columns
         WHERE table_schema = current_schema()
           AND table_name = :table
           AND is_identity = 'YES'
         LIMIT 1"
    );
    $stmt->execute([':table' => $table]);
    $column = $stmt->fetchColumn();
    if (!is_string($column) || $column === '') {
        return;
    }

    $seqStmt = $pdo->prepare('SELECT pg_get_serial_sequence(:table, :column)');
    $seqStmt->execute([':table' => $table, ':column' => $column]);
    $sequence = $seqStmt->fetchColumn();
    if (!is_string($sequence) || $sequence === '') {
        return;
    }

    $quotedTable = '"' . str_replace('"', '', $table) . '"';
    $quotedColumn = '"' . str_replace('"', '', $column) . '"';
    $pdo->prepare(
        "SELECT setval(:sequence, COALESCE((SELECT MAX({$quotedColumn}) FROM {$quotedTable}), 1), true)"
    )->execute([':sequence' => $sequence]);
}

/**
 * @param array<string, mixed> $backup
 * @return array<string, int>
 */
function restore_backup_payload(PDO $pdo, array $backup): array
{
    if (!isset($backup['tables']) || !is_array($backup['tables'])) {
        throw new InvalidArgumentException('This file is not a Tatis backup. It is missing a tables object.');
    }

    $incoming = [];
    foreach (backup_table_allowlist() as $table) {
        if (!array_key_exists($table, $backup['tables'])) {
            continue;
        }
        $rows = $backup['tables'][$table];
        if (!is_array($rows)) {
            throw new InvalidArgumentException("Backup table \"{$table}\" is not a list of rows.");
        }
        foreach ($rows as $index => $row) {
            if (!is_array($row)) {
                throw new InvalidArgumentException("Backup table \"{$table}\" has an invalid row at index {$index}.");
            }
        }
        $incoming[$table] = $rows;
    }

    if ($incoming === []) {
        throw new InvalidArgumentException('This backup has none of the supported tables.');
    }

    $pdo->beginTransaction();
    try {
        $quoted = implode(', ', array_map(
            static fn(string $table): string => '"' . str_replace('"', '', $table) . '"',
            array_keys($incoming)
        ));
        $pdo->exec('TRUNCATE TABLE ' . $quoted . ' RESTART IDENTITY CASCADE');

        $restored = [];
        foreach ($incoming as $table => $rows) {
            $liveColumns = table_column_names($pdo, $table);
            $hasIdentity = table_has_identity($pdo, $table);
            $count = 0;

            foreach ($rows as $row) {
                $insertCols = [];
                $values = [];
                foreach ($liveColumns as $column) {
                    if (!array_key_exists($column, $row)) {
                        continue;
                    }
                    $insertCols[] = $column;
                    $values[] = $row[$column];
                }
                if ($insertCols === []) {
                    continue;
                }

                $colSql = implode(', ', array_map(
                    static fn(string $column): string => '"' . str_replace('"', '', $column) . '"',
                    $insertCols
                ));
                $placeholders = implode(', ', array_fill(0, count($insertCols), '?'));
                $override = $hasIdentity ? ' OVERRIDING SYSTEM VALUE' : '';
                $quotedTable = '"' . str_replace('"', '', $table) . '"';
                $stmt = $pdo->prepare(
                    "INSERT INTO {$quotedTable} ({$colSql}){$override} VALUES ({$placeholders})"
                );

                foreach ($values as $index => $value) {
                    $param = $index + 1;
                    if ($value === null) {
                        $stmt->bindValue($param, null, PDO::PARAM_NULL);
                    } elseif (is_bool($value)) {
                        $stmt->bindValue($param, $value, PDO::PARAM_BOOL);
                    } elseif (is_array($value) || is_object($value)) {
                        $stmt->bindValue($param, json_encode($value, JSON_UNESCAPED_UNICODE));
                    } else {
                        $stmt->bindValue($param, $value);
                    }
                }
                $stmt->execute();
                $count++;
            }

            reset_table_identity($pdo, $table);
            $restored[$table] = $count;
        }

        $pdo->commit();
        return $restored;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
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
        $map = load_settings_map($pdo);
        json_response([
            'settings' => settings_payload($map),
            'notifications' => settings_notification_meta($pdo),
            'schedule' => settings_schedule_summary($pdo),
            'backup' => settings_backup_info(),
            'ai' => settings_ai_status_safe(),
            'system' => settings_system_info($pdo),
        ]);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = strtolower(trim((string)($input['action'] ?? 'update')));

    if ($action === 'update') {
        // Shop hours are managed via operating_schedule.php (shop_weekly_hours).
        // MFA and automatic backups are not enforced by the application — do not
        // accept UI writes that imply those features work. Flags remain readable.
        upsert_setting($pdo, 'email_notifications_enabled', !empty($input['emailNotificationsEnabled']) ? '1' : '0', 'Boolean', 'notifications');
        if (!empty($input['notificationFromEmail'])) {
            upsert_setting($pdo, 'notification_from_email', trim((string)$input['notificationFromEmail']), 'String', 'notifications');
        }

        $map = load_settings_map($pdo);
        json_response([
            'message' => 'Settings saved.',
            'settings' => settings_payload($map),
            'notifications' => settings_notification_meta($pdo),
            'schedule' => settings_schedule_summary($pdo),
            'backup' => settings_backup_info(),
            'ai' => settings_ai_status_safe(),
            'system' => settings_system_info($pdo),
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

        $dir = api_project_root() . DIRECTORY_SEPARATOR . 'storage' . DIRECTORY_SEPARATOR . 'backups';
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

    if ($action === 'restorebackup') {
        $payload = $input['backup'] ?? null;
        if (is_string($payload) && trim($payload) !== '') {
            $decoded = json_decode($payload, true);
            $payload = is_array($decoded) ? $decoded : null;
        }
        if (!is_array($payload)) {
            json_response(['error' => 'Upload a valid Tatis backup JSON file.'], 422);
        }

        $encodedSize = strlen((string)json_encode($payload));
        if ($encodedSize > 8 * 1024 * 1024) {
            json_response(['error' => 'Backup file is too large to restore (8 MB limit).'], 422);
        }

        try {
            $restored = restore_backup_payload($pdo, $payload);
        } catch (InvalidArgumentException $e) {
            json_response(['error' => $e->getMessage()], 422);
        }

        $map = load_settings_map($pdo);
        json_response([
            'message' => 'Backup restored.',
            'restored' => $restored,
            'settings' => settings_payload($map),
            'notifications' => settings_notification_meta($pdo),
            'schedule' => settings_schedule_summary($pdo),
            'backup' => settings_backup_info(),
            'ai' => settings_ai_status_safe(),
            'system' => settings_system_info($pdo),
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
            json_response([
                'message' => 'Email notifications are disabled in settings.',
                'processed' => 0,
                'note' => 'Enable email notifications to process the pending queue.',
            ]);
        }
        $processed = queue_pending_notifications($pdo, 100);
        json_response([
            'message' => "Marked {$processed} pending notification(s) as sent.",
            'processed' => $processed,
            'note' => 'This marks DB rows as sent. It does not deliver SMTP email for appointment events.',
            'notifications' => settings_notification_meta($pdo),
        ]);
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
