<?php
declare(strict_types=1);

$t0 = microtime(true);
require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/shop_schedule.php';

$pdo = get_db_connection();
echo json_encode(['step' => 'connected', 'ms' => round((microtime(true) - $t0) * 1000)]) . "\n";

auto_complete_due_appointments($pdo);
echo json_encode(['step' => 'auto_complete', 'ms' => round((microtime(true) - $t0) * 1000)]) . "\n";

$activeBarbersStmt = $pdo->prepare('SELECT barber_id FROM barbers WHERE is_active = TRUE');
$activeBarbersStmt->execute();
$activeBarbers = $activeBarbersStmt->fetchAll();
echo json_encode(['step' => 'barbers', 'count' => count($activeBarbers), 'ms' => round((microtime(true) - $t0) * 1000)]) . "\n";

if (!$activeBarbers) {
    echo json_encode(['error' => 'no barbers']) . "\n";
    exit(0);
}

foreach ($activeBarbers as $barberRow) {
    $barberID = (int)($barberRow['barber_id'] ?? 0);
    if ($barberID > 0) {
        seed_week_for_barber($pdo, $barberID, 7);
    }
}
echo json_encode(['step' => 'seeded', 'ms' => round((microtime(true) - $t0) * 1000)]) . "\n";
