<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/api/shop_schedule.php';

$failures = 0;

function t_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures;
    if (!$ok) {
        $failures++;
    }
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

$today = shop_today();
$future = (new DateTimeImmutable($today, new DateTimeZone(shop_timezone())))
    ->modify('+3 days')
    ->format('Y-m-d');
$past = (new DateTimeImmutable($today, new DateTimeZone(shop_timezone())))
    ->modify('-1 day')
    ->format('Y-m-d');

t_ok('today Scheduled can complete', shop_appointment_may_complete_now($today, 'Scheduled'));
t_ok('past Scheduled can complete', shop_appointment_may_complete_now($past, 'Scheduled'));
t_ok('future Scheduled cannot complete', !shop_appointment_may_complete_now($future, 'Scheduled'));
t_ok('future InProgress can complete', shop_appointment_may_complete_now($future, 'InProgress'));
t_ok('future CheckedIn can complete', shop_appointment_may_complete_now($future, 'CheckedIn'));
t_ok('timestamp payload still reads the written day', shop_pdo_date_ymd($future . ' 00:00:00+00') === $future);

if ($failures > 0) {
    fwrite(STDERR, "{$failures} failure(s)\n");
    exit(1);
}

echo "OK\n";
