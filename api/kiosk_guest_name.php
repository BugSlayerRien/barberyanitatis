<?php
declare(strict_types=1);

function kiosk_guest_name_error(): string
{
    return 'Enter at least 2 letters. Letters and spaces only.';
}

function kiosk_guest_name_is_valid(string $name): bool
{
    $name = trim($name);
    if ($name === '') {
        return false;
    }

    if (preg_match('/^[\p{L} ]+$/u', $name) !== 1) {
        return false;
    }

    preg_match_all('/\p{L}/u', $name, $letters);
    $count = isset($letters[0]) && is_array($letters[0]) ? count($letters[0]) : 0;
    return $count >= 2;
}
