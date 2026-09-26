<?php
// Barber channel: walk-in (kiosk) vs appointment (mobile booking).

declare(strict_types=1);

require_once __DIR__ . '/schema_helpers.php';

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
    static $initialized = false;
    if ($initialized) {
        return;
    }

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

    ensure_check_constraint(
        $pdo,
        'barbers',
        'barbers_barber_channel_check',
        "barber_channel IN ('walk_in', 'appointment')"
    );

    // Every endpoint that filters by channel already calls this, so it is the
    // natural place to load the merge toggle once per request.
    queue_merge_enabled($pdo);

    $initialized = true;
}

/**
 * Queue merge: show every barber in both the kiosk queue and the appointment
 * views, instead of splitting them by `barber_channel`.
 *
 * Read-side only, and deliberately so -- this flips what a query selects, it
 * does not rewrite any barber's channel, so turning it off restores the split
 * exactly. Pricing is untouched: walk-in and appointment keep their own
 * service rows and tiers (P100 / P500).
 *
 * The flag is read once per request and cached, because
 * barber_channel_filter_sql() is called from about ten places per page.
 */
function queue_merge_enabled(?PDO $pdo = null): bool
{
    static $cached = null;

    if ($cached !== null) {
        return $cached;
    }
    if ($pdo === null) {
        // No connection to ask with yet: assume the split (current behaviour).
        return false;
    }

    try {
        $stmt = $pdo->prepare(
            "SELECT setting_value FROM system_settings WHERE setting_key = 'queue_merge_enabled' LIMIT 1"
        );
        $stmt->execute();
        $value = $stmt->fetchColumn();
        $cached = $value !== false && in_array(strtolower(trim((string)$value)), ['1', 'true', 'yes', 'on'], true);
    } catch (PDOException $e) {
        // Settings table missing on a fresh database: keep the split.
        $cached = false;
    }

    return $cached;
}

/** Test seam / explicit override for callers that already know the flag. */
function queue_merge_set_for_request(bool $enabled): void
{
    queue_merge_reset();
    $GLOBALS['__queue_merge_override'] = $enabled;
}

function queue_merge_reset(): void
{
    unset($GLOBALS['__queue_merge_override']);
}

function barber_channel_filter_sql(string $channel, string $column = 'barber_channel'): string
{
    if (isset($GLOBALS['__queue_merge_override'])) {
        if ($GLOBALS['__queue_merge_override'] === true) {
            return '';
        }
    } elseif (queue_merge_enabled()) {
        return '';
    }

    $normalized = normalize_barber_channel($channel);
    if ($normalized === null) {
        return '';
    }

    return " AND {$column} = '" . str_replace("'", "''", $normalized) . "'";
}
