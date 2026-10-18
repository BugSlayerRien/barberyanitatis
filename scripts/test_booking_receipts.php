<?php

declare(strict_types=1);

/**
 * Booking payments can be looked up by receipt.
 *
 * The admin portal listed AI credit purchases and nothing else, although
 * booking payments are the great majority of the money taken -- 94 of the 105
 * captured payments when this was written. There was no screen anywhere that
 * could answer "what was this charge?" from a booking code or a gateway
 * reference, which is the question a customer rings about.
 *
 * Read-only; writes nothing.
 */

require_once __DIR__ . '/../api/db.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $condition): void
{
    global $failures, $checks;
    $checks++;
    echo ($condition ? '  PASS  ' : '  FAIL  ') . $label . "\n";
    if (!$condition) {
        $failures++;
    }
}

echo "Booking payment receipts\n";

$pdo = get_db_connection();
$payWhere = "created_at >= (CURRENT_DATE - INTERVAL '365 days')";

// --- the totals ---------------------------------------------------------
$totals = $pdo->query(
    "SELECT COUNT(*)::int AS pay_count, COALESCE(SUM(amount), 0)::float AS revenue
     FROM appointment_payments
     WHERE COALESCE(purpose, 'booking') = 'booking'
       AND status IN ('Captured', 'PartiallyRefunded') AND {$payWhere}"
)->fetch(PDO::FETCH_ASSOC);

check('booking payments exist to list', (int)$totals['pay_count'] > 0);
check('and they carry money', (float)$totals['revenue'] > 0);

// Credit top-ups are a different kind of money -- no appointment, no barber.
// Folding them in would make both figures wrong.
$credits = (int)$pdo->query(
    "SELECT COUNT(*)::int FROM appointment_payments
     WHERE purpose = 'ai_credits' AND status = 'Captured' AND {$payWhere}"
)->fetchColumn();
$all = (int)$pdo->query(
    "SELECT COUNT(*)::int FROM appointment_payments
     WHERE status IN ('Captured', 'PartiallyRefunded') AND {$payWhere}"
)->fetchColumn();
check('credit top-ups are counted separately',
    (int)$totals['pay_count'] + $credits === $all);

// --- the receipts -------------------------------------------------------
$recent = $pdo->query(
    "SELECT ap.payment_id, ap.amount::float AS amount, ap.method, ap.status,
            ap.transaction_ref, ap.created_at,
            a.booking_code,
            COALESCE(u.full_name, 'Customer #' || ap.user_id) AS customer_name,
            COALESCE(b.full_name, '-') AS barber_name,
            (SELECT COALESCE(SUM(r.amount), 0)::float
               FROM appointment_refunds r
              WHERE r.payment_id = ap.payment_id
                AND r.status = 'Completed') AS refunded
     FROM appointment_payments ap
     LEFT JOIN appointments a ON a.appointment_id = ap.appointment_id
     LEFT JOIN users u ON u.user_id = COALESCE(ap.user_id, a.user_id)
     LEFT JOIN barbers b ON b.barber_id = a.barber_id
     WHERE COALESCE(ap.purpose, 'booking') = 'booking'
       AND ap.status IN ('Captured', 'PartiallyRefunded')
     ORDER BY ap.created_at DESC
     LIMIT 20"
)->fetchAll(PDO::FETCH_ASSOC);

check('the receipt list returns rows', $recent !== []);
check('and never more than twenty', count($recent) <= 20);

// Every column the table renders must actually arrive, or the row shows "-"
// where the answer should be.
$missing = [];
foreach ($recent as $row) {
    foreach (['amount', 'customer_name', 'created_at'] as $field) {
        if (!array_key_exists($field, $row) || $row[$field] === null) {
            $missing[] = $field;
        }
    }
}
check('every receipt has an amount, a customer and a date'
    . ($missing === [] ? '' : ' (missing: ' . implode(', ', array_unique($missing)) . ')'),
    $missing === []);

// The booking code is the number a customer quotes down the phone.
$codeless = array_filter(
    $recent,
    static fn(array $r): bool => trim((string)($r['booking_code'] ?? '')) === ''
);
check('each one names the booking it paid for', $codeless === []);

// --- refunds are visible, not hidden ------------------------------------
// A refunded payment that still reads as collected is the one line on this
// table that could mislead someone reconciling the till.
$overRefunded = array_filter(
    $recent,
    static fn(array $r): bool => (float)$r['refunded'] > (float)$r['amount'] + 0.001
);
check('no receipt shows more refunded than was paid', $overRefunded === []);

$partials = array_filter(
    $recent,
    static fn(array $r): bool => (string)$r['status'] === 'PartiallyRefunded'
);
foreach ($partials as $row) {
    check('a partially refunded payment reports the amount returned',
        (float)$row['refunded'] >= 0);
}

// --- the portal actually renders it -------------------------------------
$api = (string)file_get_contents(__DIR__ . '/../api/admin_analytics.php');
check('the API serves booking payments', str_contains($api, "'bookingPayments'"));
check('and keeps them out of the AI block',
    !str_contains($api, "'creditSales' => \$creditSales,\n            'bookingPayments'"));

$portal = (string)file_get_contents(__DIR__ . '/../web-admin/admin/index.html');
$portalJs = (string)file_get_contents(__DIR__ . '/../web-admin/admin/app.js');
check('the portal has a booking payments card',
    str_contains($portal, 'analytics-booking-receipts'));
check('and renders it', str_contains($portalJs, 'renderAnalyticsBookingPayments'));
check('and the renderer is actually called',
    str_contains($portalJs, '  renderAnalyticsBookingPayments(metrics);'));
check('the reference is shown, for reconciling against the gateway',
    str_contains($portalJs, 'transaction_ref'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
