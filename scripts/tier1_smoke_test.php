<?php
/**
 * Tier 1 smoke test — run: php scripts/tier1_smoke_test.php
 * Optional env: TIER1_USER_ID=1 TIER1_BARBER_ID=1
 */

declare(strict_types=1);

$root = dirname(__DIR__);
require_once $root . '/api/db.php';
require_once $root . '/api/service_channel.php';
require_once $root . '/api/barber_channel.php';
require_once $root . '/api/shop_schedule.php';
require_once $root . '/api/slot_locking.php';

$userId = (int)(getenv('TIER1_USER_ID') ?: 1);
$barberId = (int)(getenv('TIER1_BARBER_ID') ?: 1);

$ok = 0;
$fail = 0;

function check(string $label, callable $fn): void
{
    global $ok, $fail;
    try {
        $fn();
        echo "[OK] {$label}\n";
        $ok++;
    } catch (Throwable $e) {
        echo "[FAIL] {$label}: {$e->getMessage()}\n";
        $fail++;
    }
}

echo "=== Tier 1 smoke test ===\n";

check('DB connection', static function (): void {
    $pdo = get_db_connection();
    $pdo->query('SELECT 1');
});

check('ensure_service_channel_column (idempotent)', static function (): void {
    ensure_service_channel_column(get_db_connection());
    ensure_service_channel_column(get_db_connection());
});

check('ensure_barber_channel_column (idempotent)', static function (): void {
    ensure_barber_channel_column(get_db_connection());
    ensure_barber_channel_column(get_db_connection());
});

check('run_tracking_automation', static function (): void {
    run_tracking_automation(get_db_connection(), true);
});

check('listByCustomer query', static function () use ($userId): void {
    $pdo = get_db_connection();
    $paymentsExists = (int)$pdo->query(
        "SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = current_schema() AND table_name = 'payments'"
    )->fetchColumn() > 0;
    $legacy = $paymentsExists
        ? "LEFT JOIN LATERAL (
            SELECT payment_status AS status FROM payments
            WHERE appointment_id = a.appointment_id AND payment_status = 'Paid'
            LIMIT 1
        ) legacy_pay ON TRUE"
        : '';
    $payExpr = $paymentsExists ? 'COALESCE(ap.status, legacy_pay.status)' : 'ap.status';
    $sql = "SELECT a.appointment_id, a.status, {$payExpr} AS payment_status
            FROM appointments a
            LEFT JOIN LATERAL (
                SELECT status FROM appointment_payments
                WHERE appointment_id = a.appointment_id ORDER BY payment_id DESC LIMIT 1
            ) ap ON TRUE
            {$legacy}
            WHERE a.user_id = :uid LIMIT 5";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([':uid' => $userId]);
    $stmt->fetchAll();
});

check('availability window (7 days)', static function () use ($barberId): void {
    $today = shop_today();
    $end = shop_window_end_date(7);
    echo "    bookable window: {$today} → {$end}\n";
    $pdo = get_db_connection();
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM time_slots
         WHERE barber_id = :bid AND status = 'Available'
           AND slot_date >= :today AND slot_date <= :end"
    );
    $stmt->execute([':bid' => $barberId, ':today' => $today, ':end' => $end]);
    echo '    available slots in window: ' . $stmt->fetchColumn() . "\n";
});

echo "\nResult: {$ok} passed, {$fail} failed\n";
exit($fail > 0 ? 1 : 0);
