<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/api/kiosk_guest_name.php';

$failures = 0;

function t_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures;
    if (!$ok) {
        $failures++;
    }
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

t_ok('Jo is valid', kiosk_guest_name_is_valid('Jo'));
t_ok('two words valid', kiosk_guest_name_is_valid('Mike Toledo'));
t_ok('unicode letters valid', kiosk_guest_name_is_valid('José'));
t_ok('single letter invalid', !kiosk_guest_name_is_valid('A'));
t_ok('dots invalid', !kiosk_guest_name_is_valid('....'));
t_ok('repeated p invalid if only one letter? pppp is letters', kiosk_guest_name_is_valid('pppp'));
t_ok('digits invalid', !kiosk_guest_name_is_valid('Jo1'));
t_ok('empty invalid', !kiosk_guest_name_is_valid('   '));
t_ok('spaces only invalid', !kiosk_guest_name_is_valid('  '));

if ($failures > 0) {
    fwrite(STDERR, "{$failures} failure(s)\n");
    exit(1);
}

echo "OK  {$failures} failures\n";
