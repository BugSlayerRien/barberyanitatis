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
