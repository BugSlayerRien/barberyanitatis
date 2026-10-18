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

    $initialized = true;
}

/**
 * Always true: every barber works both queues.
 *
 * The shop has four barbers. Splitting them into "walk-in only" and
 * "appointment only" meant a customer could be shown a barber the booking
 * then refused, and it took a barber off the board for half the shop's work
 * for no gain at that size. The owner's decision: everyone is available for
 * both, whatever the old toggle said.
 *
 * `barbers.barber_channel` is still stored and still editable -- it records
 * where a barber mainly works, and the kiosk and the portal label them with
 * it -- but nothing filters on it any more.
 *
 * Kept as a function rather than deleted because about ten call sites and the
 * receptionist payload ask it, and a constant true is clearer than a
 * find-and-replace across all of them. Pricing was never involved: walk-in and
 * appointment keep their own service rows and tiers (P100 / P500).
 */
function queue_merge_enabled(?PDO $pdo = null): bool
{
    return true;
}

function barber_channel_filter_sql(string $channel, string $column = 'barber_channel'): string
{
    // Nothing. Every barber is available in both queues; see
    // queue_merge_enabled() above.
    //
    // Left in place rather than removed from its callers: the queries read
    // naturally with it, and one function returning '' is a smaller change --
    // and a reversible one -- than editing ten WHERE clauses. If the shop ever
    // grows enough to want the split back, it comes back here.
    unset($channel, $column);

    return '';
}
