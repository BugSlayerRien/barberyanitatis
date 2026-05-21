<?php
/**
 * One-time / repair: create group-booking tables and columns.
 * Run: php scripts/ensure_group_schema.php
 */
declare(strict_types=1);

require_once dirname(__DIR__) . '/api/db.php';
require_once dirname(__DIR__) . '/api/group_booking.php';

$pdo = get_db_connection();

echo "Ensuring group booking schema...\n";
ensure_group_booking_schema($pdo);

$pdo->exec(
    'ALTER TABLE appointment_details
     ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
     ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
     ADD COLUMN IF NOT EXISTS customer_right_url TEXT'
);

$pdo->exec(
    'ALTER TABLE appointment_payment_intents
     ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()'
);
$pdo->exec(
    'ALTER TABLE appointment_payment_intents
     ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()'
);

echo "Done. Group booking schema is ready.\n";
