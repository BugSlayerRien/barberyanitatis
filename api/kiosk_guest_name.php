<?php
declare(strict_types=1);

/**
 * Upper bound on a walk-in guest name.
 *
 * Mirrored client-side in mobile-app/lib/kiosk/kiosk_session.dart. The column
 * `walkin_queue.guest_name` is VARCHAR(120); capping below that means an
 * over-long name is rejected with a readable 422 instead of failing on insert.
 */
const KIOSK_GUEST_NAME_MAX_LENGTH = 70;

function kiosk_guest_name_error(): string
{
    return 'Enter at least 2 letters. Letters and spaces only.';
}

function kiosk_guest_name_too_long_error(): string
{
    return 'Name must be ' . KIOSK_GUEST_NAME_MAX_LENGTH . ' characters or fewer.';
}

/** Which rule the name breaks, or null when it is acceptable. */
function kiosk_guest_name_validation_error(string $name): ?string
{
    $name = trim($name);
    if ($name === '') {
        return kiosk_guest_name_error();
    }

    // Count characters, not bytes — accented and non-Latin names would
    // otherwise be cut short by a byte-length check.
    if (mb_strlen($name, 'UTF-8') > KIOSK_GUEST_NAME_MAX_LENGTH) {
        return kiosk_guest_name_too_long_error();
    }

    if (preg_match('/^[\p{L} ]+$/u', $name) !== 1) {
        return kiosk_guest_name_error();
    }

    preg_match_all('/\p{L}/u', $name, $letters);
    $count = isset($letters[0]) && is_array($letters[0]) ? count($letters[0]) : 0;
    if ($count < 2) {
        return kiosk_guest_name_error();
    }

    return null;
}

function kiosk_guest_name_is_valid(string $name): bool
{
    return kiosk_guest_name_validation_error($name) === null;
}

/** Walk-ins still in the queue today, i.e. the ones a name could collide with. */
const KIOSK_OPEN_WALKIN_STATUSES = ['Waiting', 'Assigned', 'InProgress'];

/**
 * How many people are already waiting under this name today.
 *
 * Three Marks in one afternoon is ordinary, and a queue number alone is easy to
 * overhear, so the kiosk asks the second Mark for a surname while he is still
 * standing there. That is the only moment the customer can be asked anything.
 */
function kiosk_count_open_walkins_named(PDO $pdo, string $name): int
{
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM walkin_queue
         WHERE DATE(created_at) = CURRENT_DATE
           AND status IN ('Waiting', 'Assigned', 'InProgress')
           AND LOWER(TRIM(guest_name)) = LOWER(TRIM(:name))"
    );
    $stmt->execute([':name' => $name]);

    return (int)$stmt->fetchColumn();
}

/**
 * A 4-digit code that is unique among the walk-ins still in today's queue.
 *
 * Only ever needed to settle a dispute between two otherwise identical rows, so
 * uniqueness across the open queue is enough -- it does not have to be
 * unguessable, and it is never the thing that grants service.
 */
function kiosk_generate_claim_code(PDO $pdo): string
{
    $stmt = $pdo->prepare(
        "SELECT COUNT(*) FROM walkin_queue
         WHERE DATE(created_at) = CURRENT_DATE
           AND status IN ('Waiting', 'Assigned', 'InProgress')
           AND claim_code = :code"
    );

    for ($attempt = 0; $attempt < 40; $attempt++) {
        $code = str_pad((string)random_int(0, 9999), 4, '0', STR_PAD_LEFT);
        $stmt->execute([':code' => $code]);
        if ((int)$stmt->fetchColumn() === 0) {
            return $code;
        }
    }

    // 10,000 codes against one day's queue: unreachable in practice, and a
    // duplicate code is still better than refusing to queue the customer.
    return str_pad((string)random_int(0, 9999), 4, '0', STR_PAD_LEFT);
}
