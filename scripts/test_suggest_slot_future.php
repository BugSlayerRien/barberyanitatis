<?php
// Guards for suggestion date parsing and past-slot rejection.

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/shop_schedule.php';

$failures = 0;
function expect(bool $ok, string $name): void
{
    global $failures;
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}\n";
    if (!$ok) {
        $failures++;
    }
}

expect(shop_pdo_date_ymd('2026-09-05 00:00:00+08') === '2026-09-05', 'Timestamp date normalizes to Y-m-d');
expect(shop_pdo_date_ymd('2026-09-05') === '2026-09-05', 'Plain date stays Y-m-d');
expect(shop_pdo_time_hms('18:00:00') === '18:00:00', 'Time stays H:i:s');

$now = shop_now();
$pastHour = (int)$now->modify('-4 hours')->format('H');
$pastDate = $now->modify('-4 hours')->format('Y-m-d');
$pastTime = sprintf('%02d:00:00', $pastHour);
expect(!shop_is_suggestable_slot($pastDate, $pastTime), 'Slot 4 hours ago is not suggestable');

$todayMidnight = shop_now()->setTime(0, 0);
$yesterday = $todayMidnight->modify('-1 day')->format('Y-m-d');
expect(!shop_is_suggestable_slot($yesterday, '18:00:00'), 'Yesterday evening is not suggestable');

$windowEnd = shop_window_end_date(30);
$today = shop_today();
expect($windowEnd >= $today, '30-day window end is not before today');
$days = (new DateTimeImmutable($today))->diff(new DateTimeImmutable($windowEnd))->days;
expect($days === 29, '30-day window is today through today+29 (got ' . $days . ' days after today)');

echo $failures === 0 ? "\nAll checks passed\n" : "\n{$failures} failed\n";
exit($failures === 0 ? 0 : 1);
