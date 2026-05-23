<?php
require_once dirname(__DIR__) . '/api/db.php';

$barberId = (int)($argv[1] ?? 1);
$pdo = get_db_connection();
$stmt = $pdo->prepare(
    "SELECT a.appointment_id, a.booking_group_id, a.group_sequence, a.appointment_date,
            a.start_time, a.end_time, a.status, u.full_name
     FROM appointments a
     JOIN users u ON a.user_id = u.user_id
     WHERE a.barber_id = :barber_id
       AND a.status = 'Scheduled'
       AND a.appointment_date >= '2026-05-20'
     ORDER BY a.appointment_date, a.start_time"
);
$stmt->execute([':barber_id' => $barberId]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo json_encode($rows, JSON_PRETTY_PRINT) . "\n";
echo 'Count: ' . count($rows) . "\n";
$groups = [];
foreach ($rows as $r) {
    $gid = $r['booking_group_id'] ?? 'null';
    $groups[$gid] = ($groups[$gid] ?? 0) + 1;
}
echo 'By group_id: ' . json_encode($groups) . "\n";
