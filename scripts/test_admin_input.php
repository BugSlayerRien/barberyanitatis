<?php

declare(strict_types=1);

/**
 * Admin portal field validation.
 *
 * Covers the QA findings: an SQL-injection payload was accepted as a customer
 * name (stored inert, but still junk data), and the service editor accepted
 * the same kind of value. Prepared statements were never the problem -- the
 * missing piece was refusing the input at all.
 *
 * Each validator ends the request with json_response() on failure, so cases
 * run in a child process and the JSON is read back.
 *
 * Usage: php scripts/test_admin_input.php
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/admin_input.php';

/** @var list<array{0: string, 1: string, 2: bool, 3: string}> label, value, shouldPass, kind */
$cases = [
    ['SQL OR-injection as a name', "' OR '1'='1' --", false, 'name'],
    ['DROP TABLE as a name', "QA'; DROP TABLE services; --", false, 'name'],
    ['script tag as a name', '<script>alert(1)</script>', false, 'name'],
    ['SQL comment marker as a name', 'Robert--Tables', false, 'name'],
    ['semicolon as a name', 'Robert; Tables', false, 'name'],
    ['null byte as a name', "Rien\x00Gappi", false, 'name'],
    ['digits as a name', 'User 1234', false, 'name'],
    ['plain name', 'Rien Gappi', true, 'name'],
    ['name with apostrophe and hyphen', "O'Brien-Smith Jr.", true, 'name'],
    ['accented name', 'José Peña', true, 'name'],

    ['DROP TABLE as a service name', "QA SQLi Test'; DROP TABLE services; --", false, 'service'],
    ['angle brackets in a service name', 'Haircut <b>bold</b>', false, 'service'],
    ['plain service name', 'Classic Haircut', true, 'service'],
    ['service name with an ampersand', 'Cut & Shave', true, 'service'],

    ['valid email', 'qa-sqli-test@example.com', true, 'email'],
    ['missing @', 'not-an-email', false, 'email'],
    ['injection in an email', "a@b.com'; DROP TABLE users; --", false, 'email'],

    ['PH mobile', '09123456789', true, 'phone'],
    ['PH mobile with spaces', '0912 345 6789', true, 'phone'],
    ['injection as a phone', "'; DROP TABLE users; --", false, 'phone'],
    ['letters as a phone', 'call me', false, 'phone'],
];

// Child mode: run one case and print its outcome.
if (($argv[1] ?? '') === '--case') {
    $index = (int)($argv[2] ?? 0);
    [, $value, , $kind] = $cases[$index];
    $result = match ($kind) {
        'name' => admin_input_person_name($value, 'Name'),
        'service' => admin_input_text($value, 'Service name', 80, true),
        'email' => admin_input_email($value),
        'phone' => admin_input_phone($value),
    };
    echo json_encode(['accepted' => true, 'value' => $result]);
    exit(0);
}

$php = PHP_BINARY;
$self = __FILE__;
$failures = 0;

echo "Admin input validation\n";

foreach ($cases as $index => [$label, $value, $shouldPass, $kind]) {
    $cmd = escapeshellarg($php) . ' ' . escapeshellarg($self) . ' --case ' . $index . ' 2>&1';
    $output = (string)shell_exec($cmd);
    $accepted = str_contains($output, '"accepted":true');

    if ($accepted === $shouldPass) {
        echo '  PASS  ' . $label . ' — ' . ($shouldPass ? 'accepted' : 'rejected') . "\n";
        continue;
    }

    $failures++;
    echo '  FAIL  ' . $label . ' — expected ' . ($shouldPass ? 'accept' : 'reject')
        . ', got ' . ($accepted ? 'accept' : 'reject') . "\n";
    echo '        ' . trim(substr($output, 0, 160)) . "\n";
}

echo "\n" . count($cases) . " cases, {$failures} failed\n";
exit($failures === 0 ? 0 : 1);
