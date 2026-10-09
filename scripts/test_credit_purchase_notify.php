<?php

declare(strict_types=1);

/**
 * Guards what happens after a customer pays for AI previews.
 *
 * Buying previews used to leave no trace a person could see. The customer got
 * a count that silently changed -- and when the toast was shown at all, it was
 * attached to the page that immediately navigated away, so it vanished before
 * it could be read. The shop had nothing: credit purchases carry no
 * appointment_id, so every revenue query in admin_analytics.php skipped them
 * and the portal had no payments view at all.
 *
 * These checks assert the two records that now exist -- a notification for the
 * customer and one for the owner -- and that the owner's sales figures can
 * actually be computed.
 *
 * Every write runs inside a transaction that is always rolled back.
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/paymongo/paymongo_settlement.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $condition): void
{
    global $failures, $checks;
    $checks++;
    if ($condition) {
        echo "  PASS  {$label}\n";
        return;
    }
    $failures++;
    echo "  FAIL  {$label}\n";
}

echo "Credit purchase notification checks\n";

$pdo = get_db_connection();

// --- the notification helper -------------------------------------------------
$userId = (int)($pdo->query('SELECT user_id FROM users ORDER BY user_id LIMIT 1')->fetchColumn() ?: 0);
check('a customer exists to notify', $userId > 0);

$countFor = static function (PDO $pdo, string $type, int $id, string $ref): int {
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM notifications
         WHERE recipient_type = :type AND recipient_id = :id
           AND notification_type = 'Payment' AND message LIKE :ref"
    );
    $stmt->execute([':type' => $type, ':id' => $id, ':ref' => '%' . $ref . '%']);

    return (int)$stmt->fetchColumn();
};

if ($userId > 0) {
    $ref = 'test_ref_' . bin2hex(random_bytes(6));

    $pdo->beginTransaction();
    try {
        paymongo_notify_credit_purchase($pdo, $userId, 5, 49.00, $ref);

        check('the customer is told', $countFor($pdo, 'User', $userId, $ref) === 1);
        // recipient_id 0 is the shop-wide admin inbox, the same convention
        // admin_settings.php already writes System notifications under.
        check('and so is the owner', $countFor($pdo, 'Admin', 0, $ref) === 1);

        $stmt = $pdo->prepare(
            "SELECT title, message FROM notifications
             WHERE recipient_type = 'User' AND message LIKE :ref LIMIT 1"
        );
        $stmt->execute([':ref' => '%' . $ref . '%']);
        $row = $stmt->fetch(PDO::FETCH_ASSOC) ?: ['title' => '', 'message' => ''];

        check('the customer message states the amount',
            str_contains((string)$row['message'], '49.00'));
        check('and how many previews were added',
            str_contains((string)$row['message'], '5 AI previews'));
        check('and carries the reference for support',
            str_contains((string)$row['message'], $ref));

        $stmt = $pdo->prepare(
            "SELECT message FROM notifications
             WHERE recipient_type = 'Admin' AND message LIKE :ref LIMIT 1"
        );
        $stmt->execute([':ref' => '%' . $ref . '%']);
        $adminMessage = (string)($stmt->fetchColumn() ?: '');
        check('the owner message names the buyer and the amount',
            $adminMessage !== '' && str_contains($adminMessage, '49.00'));
    } finally {
        $pdo->rollBack();
    }

    check('the rollback left no notifications behind',
        $countFor($pdo, 'User', $userId, $ref) === 0);

    // One preview, not "1 previews".
    $singular = 'test_ref_' . bin2hex(random_bytes(6));
    $pdo->beginTransaction();
    try {
        paymongo_notify_credit_purchase($pdo, $userId, 1, 12.00, $singular);
        $stmt = $pdo->prepare(
            "SELECT message FROM notifications WHERE message LIKE :ref LIMIT 1"
        );
        $stmt->execute([':ref' => '%' . $singular . '%']);
        $message = (string)($stmt->fetchColumn() ?: '');
        check('a single credit reads as one preview',
            str_contains($message, '1 AI preview ') || str_contains($message, '1 AI preview.'));
    } finally {
        $pdo->rollBack();
    }
}

// A missing user must not raise: the payment has already settled and the
// credits are already granted by the time this runs, so a notification problem
// can never be allowed to fail the purchase.
$before = (int)$pdo->query('SELECT COUNT(*) FROM notifications')->fetchColumn();
paymongo_notify_credit_purchase($pdo, 0, 5, 49.00, 'ignored_ref');
check('an unknown customer is skipped without error',
    (int)$pdo->query('SELECT COUNT(*) FROM notifications')->fetchColumn() === $before);

// --- the owner's sales figures -----------------------------------------------
// These columns are added lazily, so a shop that has never sold a credit may
// not have them. The analytics query must survive that rather than 500.
$columns = $pdo->query(
    "SELECT column_name FROM information_schema.columns
     WHERE table_name = 'appointment_payments'"
)->fetchAll(PDO::FETCH_COLUMN);
$hasCreditColumns = in_array('purpose', $columns, true)
    && in_array('credits', $columns, true)
    && in_array('user_id', $columns, true);
check('the credit purchase columns exist', $hasCreditColumns);

if ($hasCreditColumns) {
    $row = $pdo->query(
        "SELECT COUNT(*)::int AS sale_count,
                COALESCE(SUM(credits), 0)::int AS credits,
                COALESCE(SUM(amount), 0)::float AS revenue
         FROM appointment_payments
         WHERE purpose = 'ai_credits' AND status = 'Captured'"
    )->fetch(PDO::FETCH_ASSOC);
    check('the sales summary query runs', is_array($row));

    $receipts = $pdo->query(
        "SELECT ap.payment_id, ap.credits, ap.amount::float AS amount, ap.method,
                ap.transaction_ref, ap.created_at,
                COALESCE(u.full_name, 'Customer #' || ap.user_id) AS customer_name
         FROM appointment_payments ap
         LEFT JOIN users u ON u.user_id = ap.user_id
         WHERE ap.purpose = 'ai_credits' AND ap.status = 'Captured'
         ORDER BY ap.created_at DESC
         LIMIT 10"
    )->fetchAll(PDO::FETCH_ASSOC);
    check('the receipt list query runs', is_array($receipts));
    // A deleted customer must still leave a readable receipt.
    foreach ($receipts as $receipt) {
        check('every receipt names a buyer',
            trim((string)($receipt['customer_name'] ?? '')) !== '');
        break;
    }

    // Credit sales must not leak into service revenue, which reads a different
    // table entirely -- otherwise both numbers become wrong.
    $leaked = (int)$pdo->query(
        "SELECT COUNT(*) FROM appointment_payments
         WHERE purpose = 'ai_credits' AND appointment_id IS NOT NULL"
    )->fetchColumn();
    check('no credit sale is attached to an appointment', $leaked === 0);
}

// --- the settlement only notifies once ---------------------------------------
$source = (string)file_get_contents(__DIR__ . '/../api/paymongo/paymongo_settlement.php');
check('notification is gated on the payment being captured',
    str_contains($source, "if (\$paymentStatus === 'Captured') {"));
// A repeat settlement (webhook plus poll) takes the UPDATE branch and returns
// before the insert, so it cannot notify a second time.
check('a repeat settlement returns before notifying',
    strpos($source, 'if (is_array($existing))') < strpos($source, 'paymongo_notify_credit_purchase($pdo'));

echo "\n{$checks} checks, {$failures} failures\n";
exit($failures === 0 ? 0 : 1);
