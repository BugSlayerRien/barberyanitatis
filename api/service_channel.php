<?php
// Service channel: walk_in (kiosk / regular) vs appointment (exclusive mobile booking).

declare(strict_types=1);

/**
 * @return 'walk_in'|'appointment'|null
 */
function normalize_service_channel(?string $raw): ?string
{
    $value = strtolower(trim((string)$raw));
    if ($value === 'walk_in' || $value === 'walkin' || $value === 'regular' || $value === 'kiosk') {
        return 'walk_in';
    }
    if ($value === 'appointment' || $value === 'appointments' || $value === 'exclusive') {
        return 'appointment';
    }

    return null;
}

function ensure_service_channel_column(PDO $pdo): void
{
    $pdo->exec(
        "ALTER TABLE services
         ADD COLUMN IF NOT EXISTS service_channel TEXT NOT NULL DEFAULT 'appointment'"
    );

    $pdo->exec(
        "UPDATE services
         SET service_channel = CASE
             WHEN LOWER(category) = 'haircut' AND base_price <= 150 THEN 'walk_in'
             ELSE COALESCE(NULLIF(TRIM(service_channel), ''), 'appointment')
         END
         WHERE service_channel IS NULL
            OR TRIM(service_channel) = ''"
    );

    $pdo->exec('ALTER TABLE services DROP CONSTRAINT IF EXISTS services_service_channel_check');
    $pdo->exec(
        "ALTER TABLE services ADD CONSTRAINT services_service_channel_check
         CHECK (service_channel IN ('walk_in', 'appointment'))"
    );
}

function service_channel_filter_sql(string $channel, string $column = 'service_channel'): string
{
    $normalized = normalize_service_channel($channel);
    if ($normalized === null) {
        return '';
    }

    return " AND {$column} = '" . str_replace("'", "''", $normalized) . "'";
}
