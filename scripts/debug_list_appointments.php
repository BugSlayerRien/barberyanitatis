<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/api/db.php';
require_once dirname(__DIR__) . '/api/service_channel.php';
require_once dirname(__DIR__) . '/api/barber_channel.php';
require_once dirname(__DIR__) . '/api/shop_schedule.php';
require_once dirname(__DIR__) . '/api/group_booking.php';
require_once dirname(__DIR__) . '/api/slot_locking.php';
require_once dirname(__DIR__) . '/api/appointment_notifications.php';
require_once dirname(__DIR__) . '/api/payment_recording.php';

// Minimal copies of booking helpers (avoid booking.php require_method)
function dbg_ensure_financial_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payments (
            payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'Captured',
            transaction_ref VARCHAR(120),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payment_intents (
            intent_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            provider VARCHAR(30) NOT NULL DEFAULT 'mock',
            status VARCHAR(30) NOT NULL DEFAULT 'PendingGateway',
            intent_token VARCHAR(120) NOT NULL UNIQUE,
            provider_ref VARCHAR(120),
            failure_reason TEXT,
            expires_at TIMESTAMPTZ NOT NULL,
            paid_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );
    $pdo->exec('ALTER TABLE appointment_payment_intents ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()');
    $pdo->exec('ALTER TABLE appointment_payment_intents ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()');
}

function dbg_derive_payment_state(?string $paymentStatus, ?string $intentStatus): string
{
    $payment = $paymentStatus !== null ? trim((string)$paymentStatus) : '';
    if ($payment !== '' && in_array(strtolower($payment), ['captured', 'paid', 'succeeded'], true)) {
        return 'Paid';
    }
    $intent = $intentStatus !== null ? trim((string)$intentStatus) : '';
    if ($intent !== '') {
        if (in_array($intent, ['PendingGateway', 'Verifying', 'Processing'], true)) {
            return 'Verifying';
        }
        if (in_array($intent, ['Failed', 'Expired', 'Cancelled'], true)) {
            return 'Failed';
        }
        if (in_array(strtolower($intent), ['paid', 'succeeded', 'captured'], true)) {
            return 'Paid';
        }
    }
    return 'Unpaid';
}

$pdo = get_db_connection();
$userId = (int)($argv[1] ?? 0);
if ($userId <= 0) {
    $userId = (int)$pdo->query('SELECT user_id FROM users WHERE is_active = TRUE ORDER BY user_id LIMIT 1')->fetchColumn();
}

echo "DB connected. user_id={$userId}\n";

try {
    ensure_group_booking_schema($pdo);
    dbg_ensure_financial_tables($pdo);
    $pdo->exec(
        'ALTER TABLE appointment_details
         ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_right_url TEXT'
    );
    echo "Schema OK\n";
} catch (Throwable $e) {
    echo "SCHEMA ERROR: " . $e->getMessage() . "\n";
    exit(1);
}

try {
    $stmt = $pdo->prepare(
        "SELECT a.appointment_id, a.booking_code, a.booking_group_id, a.group_member_name, a.group_sequence,
                a.appointment_date, a.start_time, a.end_time, a.status,
                b.barber_id, b.full_name AS barber_name,
                ap.status AS payment_status, ap.transaction_ref, ap.created_at AS paid_at,
                pi.intent_id, pi.status AS intent_status, pi.method AS intent_method, pi.expires_at AS intent_expires_at,
                pi.created_at AS intent_created_at,
                pi.failure_reason, pi.updated_at AS intent_updated_at
         FROM appointments a
         JOIN barbers b ON a.barber_id = b.barber_id
         LEFT JOIN LATERAL (
             SELECT payment_id, status, transaction_ref, created_at
             FROM appointment_payments
             WHERE appointment_id = a.appointment_id
             ORDER BY payment_id DESC
             LIMIT 1
         ) ap ON TRUE
         LEFT JOIN LATERAL (
             SELECT intent_id, status, method, expires_at, created_at, failure_reason, updated_at
             FROM appointment_payment_intents
             WHERE appointment_id = a.appointment_id
             ORDER BY intent_id DESC
             LIMIT 1
         ) pi ON TRUE
         WHERE a.user_id = :user_id
         ORDER BY a.appointment_date DESC, a.start_time DESC"
    );
    $stmt->execute([':user_id' => $userId]);
    $appointments = $stmt->fetchAll();
    echo 'Query rows: ' . count($appointments) . "\n";

    if ($appointments === []) {
        echo "OK (empty list)\n";
        exit(0);
    }

    $appointmentIds = array_map(fn($row) => (int)$row['appointment_id'], $appointments);
    $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

    $serviceStmt = $pdo->prepare(
        "SELECT ad.appointment_id, ad.service_id, ad.variant_id, ad.final_price,
                s.service_name, s.base_duration,
                hs.style_name AS hairstyle_name,
                COALESCE(ad.customer_front_url, hv.front_view_url) AS front_view_url,
                COALESCE(ad.customer_left_url, hv.side_view_url) AS side_view_url,
                COALESCE(ad.customer_right_url, hv.back_view_url) AS back_view_url
         FROM appointment_details ad
         JOIN services s ON ad.service_id = s.service_id
         LEFT JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
         LEFT JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
         WHERE ad.appointment_id IN ($inClause)"
    );
    $serviceStmt->execute($appointmentIds);
    echo 'Services rows: ' . count($serviceStmt->fetchAll()) . "\n";

    $collapsed = collapse_customer_appointments(array_map(static function (array $row) {
        return [
            'appointmentID' => (int)$row['appointment_id'],
            'bookingGroupID' => $row['booking_group_id'] !== null ? (int)$row['booking_group_id'] : null,
            'groupMemberName' => $row['group_member_name'],
            'groupSequence' => $row['group_sequence'],
            'status' => (string)$row['status'],
            'paymentState' => 'Unpaid',
            'startTime' => (string)$row['start_time'],
            'endTime' => (string)$row['end_time'],
            'appointmentDate' => (string)$row['appointment_date'],
            'services' => [['durationMinutes' => 60, 'price' => '100']],
        ];
    }, $appointments));

    echo 'Collapsed: ' . count($collapsed) . "\n";
    echo "SUCCESS\n";
} catch (Throwable $e) {
    echo "LIST ERROR: " . $e->getMessage() . "\n";
    echo $e->getFile() . ':' . $e->getLine() . "\n";
    echo $e->getTraceAsString() . "\n";
    exit(1);
}
