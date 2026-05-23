<?php
// Service channel: walk_in (kiosk / regular) vs appointment (exclusive mobile booking).

declare(strict_types=1);

require_once __DIR__ . '/schema_helpers.php';

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
    static $initialized = false;
    if ($initialized) {
        return;
    }

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

    ensure_check_constraint(
        $pdo,
        'services',
        'services_service_channel_check',
        "service_channel IN ('walk_in', 'appointment')"
    );

    $initialized = true;
}

function service_channel_filter_sql(string $channel, string $column = 'service_channel'): string
{
    $normalized = normalize_service_channel($channel);
    if ($normalized === null) {
        return '';
    }

    return " AND {$column} = '" . str_replace("'", "''", $normalized) . "'";
}

/**
 * @param list<int|string> $serviceIds
 * @return list<int>
 */
function filter_walk_in_service_ids(PDO $pdo, array $serviceIds): array
{
    ensure_service_channel_column($pdo);

    $ids = array_values(array_unique(array_filter(array_map(static fn($id): int => (int)$id, $serviceIds))));
    if ($ids === []) {
        return [];
    }

    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    $stmt = $pdo->prepare(
        "SELECT service_id
         FROM services
         WHERE service_id IN ($placeholders)
           AND is_active = TRUE
           AND service_channel = 'walk_in'"
    );
    $stmt->execute($ids);

    return array_map(static fn($id): int => (int)$id, $stmt->fetchAll(PDO::FETCH_COLUMN));
}

function default_walk_in_service_id(PDO $pdo): ?int
{
    ensure_service_channel_column($pdo);
    $stmt = $pdo->query(
        "SELECT service_id
         FROM services
         WHERE is_active = TRUE
           AND service_channel = 'walk_in'
         ORDER BY service_id ASC
         LIMIT 1"
    );
    $id = $stmt->fetchColumn();

    return $id === false ? null : (int)$id;
}
