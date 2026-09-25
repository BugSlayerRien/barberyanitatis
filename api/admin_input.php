<?php

declare(strict_types=1);

/**
 * Field validation for admin-portal writes.
 *
 * Injection itself was never the risk here: every query in this codebase uses
 * prepared statements, so a payload like `' OR '1'='1' --` is stored as inert
 * text rather than executed. The defect QA found is that it was *accepted* --
 * a customer row whose name is an SQL fragment is junk data, it re-renders in
 * the portal and the mobile app, and it teaches whoever reads the list that
 * the field has no rules.
 *
 * These helpers reject the value at the boundary and say why. They are
 * deliberately conservative: they normalise whitespace, cap length and refuse
 * characters that have no business in a name, an email or a price.
 */

/** Characters no human field should contain: control chars, and tags/quotes. */
function admin_input_has_suspicious_chars(string $value): bool
{
    if (preg_match('/[\x00-\x1F\x7F]/', $value) === 1) {
        return true;
    }

    // <, > and the SQL comment/terminator markers. A legitimate name, service
    // or description in this app needs none of them.
    return preg_match('/[<>]|--|;|\/\*|\*\//', $value) === 1;
}

/**
 * Collapses runs of whitespace and trims. Keeps the value printable so an
 * error message can quote it back safely.
 */
function admin_input_clean(string $value): string
{
    // Only real whitespace is normalised. Other control characters are left in
    // place on purpose so admin_input_has_suspicious_chars() can reject them:
    // stripping them silently turned "Rien\0Gappi" into an accepted
    // "RienGappi", which quietly changes what the admin typed.
    $value = preg_replace('/[\r\n\t\x0B\x0C]+/', ' ', $value) ?? '';
    $value = preg_replace('/ {2,}/', ' ', $value) ?? '';

    return trim($value);
}

/**
 * A person's name. Letters (any script), spaces, and the punctuation real
 * names use: apostrophe, hyphen, period. Mirrors the mobile app's own rule
 * (mobile-app/lib/user/person_name.dart) so the two portals agree.
 *
 * @return string The cleaned name.
 */
function admin_input_person_name(?string $raw, string $label = 'Name', int $max = 80): string
{
    $value = admin_input_clean((string)$raw);
    if ($value === '') {
        json_response(['error' => $label . ' is required.'], 422);
    }
    if (mb_strlen($value) > $max) {
        json_response(['error' => $label . ' must be ' . $max . ' characters or fewer.'], 422);
    }
    if (admin_input_has_suspicious_chars($value)) {
        json_response(['error' => $label . ' contains characters that are not allowed.'], 422);
    }
    if (preg_match("/^[\p{L}][\p{L}\p{M}'\-. ]*$/u", $value) !== 1) {
        json_response(
            ['error' => $label . ' may only contain letters, spaces, apostrophes, hyphens and periods.'],
            422
        );
    }

    return $value;
}

/** A free-text field (service name, description, note). */
function admin_input_text(?string $raw, string $label, int $max, bool $required = false): string
{
    $value = admin_input_clean((string)$raw);
    if ($value === '') {
        if ($required) {
            json_response(['error' => $label . ' is required.'], 422);
        }

        return '';
    }
    if (mb_strlen($value) > $max) {
        json_response(['error' => $label . ' must be ' . $max . ' characters or fewer.'], 422);
    }
    if (admin_input_has_suspicious_chars($value)) {
        json_response(['error' => $label . ' contains characters that are not allowed.'], 422);
    }

    return $value;
}

function admin_input_email(?string $raw, string $label = 'Email'): string
{
    $value = strtolower(admin_input_clean((string)$raw));
    if ($value === '') {
        json_response(['error' => $label . ' is required.'], 422);
    }
    if (mb_strlen($value) > 120) {
        json_response(['error' => $label . ' must be 120 characters or fewer.'], 422);
    }
    if (filter_var($value, FILTER_VALIDATE_EMAIL) === false) {
        json_response(['error' => 'Enter a valid ' . strtolower($label) . ' address.'], 422);
    }

    return $value;
}

/**
 * Philippine mobile or landline, stored as digits. Empty is allowed: phone is
 * optional on an account.
 */
function admin_input_phone(?string $raw, string $label = 'Phone'): string
{
    $value = admin_input_clean((string)$raw);
    if ($value === '') {
        return '';
    }

    $digits = preg_replace('/\D+/', '', $value) ?? '';
    if ($digits === '') {
        json_response(['error' => $label . ' must be a number.'], 422);
    }
    // 09XXXXXXXXX, 639XXXXXXXXX, or an 8-10 digit landline.
    $ok = preg_match('/^09\d{9}$/', $digits) === 1
        || preg_match('/^639\d{9}$/', $digits) === 1
        || (strlen($digits) >= 8 && strlen($digits) <= 10);
    if (!$ok) {
        json_response(['error' => 'Enter a valid ' . strtolower($label) . ' number (e.g. 09123456789).'], 422);
    }

    return $digits;
}

/** @param list<string> $allowed */
function admin_input_choice(?string $raw, array $allowed, string $label, ?string $default = null): string
{
    $value = admin_input_clean((string)$raw);
    if ($value === '' && $default !== null) {
        return $default;
    }
    foreach ($allowed as $option) {
        if (strcasecmp($option, $value) === 0) {
            return $option;
        }
    }

    json_response(['error' => $label . ' must be one of: ' . implode(', ', $allowed) . '.'], 422);
}

function admin_input_int(mixed $raw, string $label, int $min, int $max, ?int $default = null): int
{
    if (($raw === null || $raw === '') && $default !== null) {
        return $default;
    }
    if (!is_numeric($raw)) {
        json_response(['error' => $label . ' must be a number.'], 422);
    }
    $value = (int)$raw;
    if ($value < $min || $value > $max) {
        json_response(['error' => $label . ' must be between ' . $min . ' and ' . $max . '.'], 422);
    }

    return $value;
}

function admin_input_money(mixed $raw, string $label, float $min, float $max, ?float $default = null): float
{
    if (($raw === null || $raw === '') && $default !== null) {
        return $default;
    }
    if (!is_numeric($raw)) {
        json_response(['error' => $label . ' must be a number.'], 422);
    }
    $value = round((float)$raw, 2);
    if ($value < $min || $value > $max) {
        json_response(
            ['error' => $label . ' must be between ' . number_format($min, 2) . ' and ' . number_format($max, 2) . '.'],
            422
        );
    }

    return $value;
}
