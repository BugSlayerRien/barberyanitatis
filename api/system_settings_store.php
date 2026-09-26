<?php

// The system_settings key/value store, split out of admin_settings.php.
//
// admin_settings.php is an endpoint: including it runs its request handler and
// its admin gate, so any other file that just wanted to read or write a
// setting got a 401 instead. These two functions are all a caller needs.

declare(strict_types=1);

require_once __DIR__ . '/db.php';

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
