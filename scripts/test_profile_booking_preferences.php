<?php
declare(strict_types=1);

require_once dirname(__DIR__) . '/api/slot_recommendation.php';

$failures = 0;

function t_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures;
    if (!$ok) {
        $failures++;
    }
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

$twoMorning = [
    ['barber_id' => 1, 'barber_name' => 'Francis Vasallo', 'appointment_date' => '2026-08-03', 'start_time' => '09:00:00'],
    ['barber_id' => 1, 'barber_name' => 'Francis Vasallo', 'appointment_date' => '2026-08-10', 'start_time' => '09:00:00'],
];
$built = slot_recommendation_build_profile($twoMorning);
$display = slot_recommendation_profile_display($built);
t_ok('two same-slot visits mark usual time', $display['usualBookingTime'] === 'Morning', (string)$display['usualBookingTime']);
t_ok('two same-slot visits mark usual barber', $display['usualBarber'] === 'Francis Vasallo', (string)$display['usualBarber']);
t_ok('two same-slot visits mark usual day', $display['usualBookingDay'] === 'Monday', (string)$display['usualBookingDay']);

$oneVisit = slot_recommendation_profile_display(slot_recommendation_build_profile([
    ['barber_id' => 1, 'barber_name' => 'Francis Vasallo', 'appointment_date' => '2026-08-03', 'start_time' => '09:00:00'],
]));
t_ok('one visit does not guess time', $oneVisit['usualBookingTime'] === null);
t_ok('one visit does not guess barber', $oneVisit['usualBarber'] === null);
t_ok('one visit does not guess day', $oneVisit['usualBookingDay'] === null);

$empty = slot_recommendation_profile_display(slot_recommendation_build_profile([]));
t_ok('empty history is not enough', $empty['usualBookingTime'] === null && $empty['visitCount'] === 0);

if ($failures > 0) {
    fwrite(STDERR, "{$failures} failure(s)\n");
    exit(1);
}
echo "OK\n";
