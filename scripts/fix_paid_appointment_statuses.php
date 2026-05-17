<?php
// One-off repair: normalize PayMongo rows that stored gateway "Paid" instead of "Captured".
declare(strict_types=1);

require __DIR__ . '/../api/db.php';
load_repository_env();
$pdo = get_db_connection();

$pdo->beginTransaction();
try {
    $payments = $pdo->exec(
        "UPDATE appointment_payments
         SET status = 'Captured'
         WHERE LOWER(status) IN ('paid', 'succeeded')"
    );

    $appointments = $pdo->exec(
        "UPDATE appointments a
         SET status = 'Scheduled', updated_at = CURRENT_TIMESTAMP
         WHERE a.status = 'PendingPayment'
           AND EXISTS (
             SELECT 1
             FROM appointment_payments ap
             WHERE ap.appointment_id = a.appointment_id
               AND LOWER(ap.status) IN ('captured', 'paid', 'succeeded')
           )"
    );

    $pdo->commit();
    echo "Updated payment rows: {$payments}\n";
    echo "Promoted appointments: {$appointments}\n";
} catch (Throwable $e) {
    $pdo->rollBack();
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}
