<?php
require_once dirname(__DIR__) . '/api/db.php';
$pdo = get_db_connection();
$stmt = $pdo->query(
    "SELECT column_name, data_type FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'appointment_payment_intents'
     ORDER BY ordinal_position"
);
foreach ($stmt->fetchAll() as $row) {
    echo $row['column_name'] . ' (' . $row['data_type'] . ")\n";
}
