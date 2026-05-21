<?php
// Barber channel: walk-in (kiosk) vs appointment (mobile booking).

declare(strict_types=1);

/**
 * @return 'walk_in'|'appointment'|null
 */
function normalize_barber_channel(?string $raw): ?string
{
    $value = strtolower(trim((string)$raw));
    if ($value === 'walk_in' || $value === 'walkin' || $value === 'regular') {
        return 'walk_in';
    }
    if ($value === 'appointment' || $value === 'appointments' || $value === 'exclusive') {
        return 'appointment';
    }

    return null;
}

function ensure_barber_channel_column(PDO $pdo): void
{
    $pdo->exec(
        "ALTER TABLE barbers
         ADD COLUMN IF NOT EXISTS barber_channel TEXT NOT NULL DEFAULT 'appointment'"
    );

    $pdo->exec(
        "UPDATE barbers
         SET barber_channel = 'appointment'
         WHERE barber_channel IS NULL
            OR TRIM(barber_channel) = ''"
    );

    $pdo->exec('ALTER TABLE barbers DROP CONSTRAINT IF EXISTS barbers_barber_channel_check');
    $pdo->exec(
        "ALTER TABLE barbers ADD CONSTRAINT barbers_barber_channel_check
         CHECK (barber_channel IN ('walk_in', 'appointment'))"
    );
}

function barber_channel_filter_sql(string $channel, string $column = 'barber_channel'): string
{
    $normalized = normalize_barber_channel($channel);
    if ($normalized === null) {
        return '';
    }

    return " AND {$column} = '" . str_replace("'", "''", $normalized) . "'";
}
