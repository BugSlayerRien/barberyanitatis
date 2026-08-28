<?php
// Group-booking variant fallback + booking-code allocation tests.
// Rolls back any inserts. Does not call payments, JWT, kiosk, or ranking.

declare(strict_types=1);

require_once dirname(__DIR__) . '/api/db.php';
require_once dirname(__DIR__) . '/api/booking_codes.php';

$failures = 0;

function t_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures;
    if (!$ok) {
        $failures++;
    }
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

$pdo = get_db_connection();
$date = '2026-08-31';
$prefix = appointment_booking_code_prefix($date);
t_ok('prefix uses slot date', $prefix === 'APP-20260831', $prefix);

$next = next_appointment_booking_code($pdo, $date);
t_ok(
    'duplicate booking-code: next skips existing suffixes including cancelled/rescheduled',
    $next === 'APP-20260831-004',
    $next
);

$countBased = 'APP-20260831-' . str_pad(
    (string)((int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE appointment_date = '2026-08-31'")->fetchColumn() + 1),
    3,
    '0',
    STR_PAD_LEFT
);
t_ok(
    'old COUNT+1 would collide (APP-20260831-002)',
    $countBased === 'APP-20260831-002',
    $countBased
);

$exists = (int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE booking_code = 'APP-20260831-004'")->fetchColumn();
t_ok('allocated next code is unused', $exists === 0);

$mikeId = (int)$pdo->query("SELECT user_id FROM users WHERE full_name ILIKE '%Mike Toledo%' LIMIT 1")->fetchColumn();
$lastVariant = (int)$pdo->query(
    "SELECT ad.variant_id
     FROM appointment_details ad
     JOIN appointments a ON a.appointment_id = ad.appointment_id
     WHERE a.user_id = {$mikeId}
     ORDER BY a.appointment_id DESC
     LIMIT 1"
)->fetchColumn();

$resolvedMissing = resolve_group_booking_variant_id($pdo, $mikeId, 0);
t_ok(
    'Quick Action / missing variantID uses last existing variant',
    $resolvedMissing === $lastVariant && $resolvedMissing > 0,
    "got {$resolvedMissing}, last {$lastVariant}"
);

$resolvedKeep = resolve_group_booking_variant_id($pdo, $mikeId, $lastVariant);
t_ok(
    'normal group booking preserves selected hairstyle',
    $resolvedKeep === $lastVariant,
    (string)$resolvedKeep
);

$resolvedBad = resolve_group_booking_variant_id($pdo, $mikeId, 999999);
t_ok(
    'invalid variantID falls back instead of inserting a dead FK',
    $resolvedBad === $lastVariant,
    (string)$resolvedBad
);

$catalog = resolve_group_booking_variant_id($pdo, 0, 0);
t_ok('catalog fallback when no user history', $catalog > 0, (string)$catalog);

$timeSlot = file_get_contents(dirname(__DIR__) . '/mobile-app/lib/user/time_slot_page.dart') ?: '';
t_ok(
    'single-person booking still requires a hairstyle',
    str_contains($timeSlot, "if (UserSession.selectedVariantId == null)")
    && str_contains($timeSlot, 'Select a hairstyle before booking.'),
    ''
);

$groupPage = file_get_contents(dirname(__DIR__) . '/mobile-app/lib/user/group_booking_page.dart') ?: '';
t_ok(
    'group confirm no longer blocks on selectedVariantId',
    !str_contains($groupPage, 'Please log in and select a hairstyle first.')
    && str_contains($groupPage, 'UserSession.userId == null')
    && str_contains($groupPage, "'variantID': UserSession.selectedVariantId"),
    ''
);

$groupPhp = file_get_contents(dirname(__DIR__) . '/api/group_booking.php') ?: '';
$bookingPhp = file_get_contents(dirname(__DIR__) . '/api/booking.php') ?: '';
t_ok(
    'group and single create no longer use COUNT(*) + 1 for booking codes',
    !str_contains($groupPhp, 'SELECT COUNT(*) FROM appointments WHERE appointment_date')
    && !str_contains($bookingPhp, 'SELECT COUNT(*) FROM appointments WHERE appointment_date = :appointment_date')
    && str_contains($groupPhp, 'insert_appointment_with_unique_code')
    && str_contains($bookingPhp, 'insert_appointment_with_unique_code'),
    ''
);

$barberId = (int)$pdo->query("SELECT barber_id FROM barbers WHERE is_active = TRUE ORDER BY barber_id LIMIT 1")->fetchColumn();
$attempts = 0;
$retryCode = insert_appointment_with_unique_code(
    $pdo,
    $date,
    static function (string $code) use (&$attempts): string {
        $attempts++;
        if ($attempts === 1) {
            throw new PDOException(
                'SQLSTATE[23505]: Unique violation: 7 ERROR: duplicate key value violates unique constraint "appointments_booking_code_key"',
                23505
            );
        }

        return $code;
    }
);
t_ok(
    'collision/retry protection retries then succeeds',
    $attempts === 2 && $retryCode === 'APP-20260831-004',
    "attempts={$attempts} code={$retryCode}"
);

$pdo->beginTransaction();
try {
    $stmt = $pdo->prepare(
        "INSERT INTO appointments (booking_code, user_id, barber_id, appointment_date, start_time, end_time, status)
         VALUES (:code, :user_id, :barber_id, :date, '09:00:00', '10:00:00', 'PendingPayment')
         RETURNING appointment_id"
    );
    $first = insert_appointment_with_unique_code(
        $pdo,
        $date,
        static function (string $code) use ($stmt, $mikeId, $barberId, $date): array {
            $stmt->execute([
                ':code' => $code,
                ':user_id' => $mikeId,
                ':barber_id' => $barberId,
                ':date' => $date,
            ]);

            return ['id' => (int)$stmt->fetchColumn(), 'code' => $code];
        }
    );
    t_ok(
        'single booking insert uses next free suffix',
        ($first['code'] ?? '') === 'APP-20260831-004',
        (string)($first['code'] ?? '')
    );

    $second = insert_appointment_with_unique_code(
        $pdo,
        $date,
        static function (string $code) use ($stmt, $mikeId, $barberId, $date): array {
            $stmt->execute([
                ':code' => $code,
                ':user_id' => $mikeId,
                ':barber_id' => $barberId,
                ':date' => $date,
            ]);

            return ['id' => (int)$stmt->fetchColumn(), 'code' => $code];
        }
    );
    t_ok(
        'group-style consecutive inserts increment suffix (004 then 005)',
        ($second['code'] ?? '') === 'APP-20260831-005',
        (string)($second['code'] ?? '')
    );

    $pdo->exec('SAVEPOINT dup_code');
    $dupFailed = false;
    try {
        $stmt->execute([
            ':code' => 'APP-20260831-004',
            ':user_id' => $mikeId,
            ':barber_id' => $barberId,
            ':date' => $date,
        ]);
    } catch (PDOException $e) {
        $dupFailed = appointment_booking_code_conflict($e);
        $pdo->exec('ROLLBACK TO SAVEPOINT dup_code');
    }
    t_ok('never reuse existing booking codes (unique still enforced)', $dupFailed);
} catch (Throwable $e) {
    t_ok('rolled-back live inserts', false, $e->getMessage());
}

if ($pdo->inTransaction()) {
    $pdo->rollBack();
}

$stillUnused = (int)$pdo->query("SELECT COUNT(*) FROM appointments WHERE booking_code IN ('APP-20260831-004','APP-20260831-005')")->fetchColumn();
t_ok('test inserts were rolled back', $stillUnused === 0, (string)$stillUnused);

echo "\n" . ($failures === 0 ? 'ALL PASSED' : "{$failures} FAILED") . "\n";
exit($failures === 0 ? 0 : 1);
