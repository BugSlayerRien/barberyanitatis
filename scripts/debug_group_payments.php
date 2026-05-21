<?php
require_once dirname(__DIR__) . '/api/db.php';

$pdo = get_db_connection();
$rows = $pdo->query(
    "SELECT a.appointment_id, a.booking_group_id, a.group_member_name, a.status,
            ap.status AS payment_status
     FROM appointments a
     LEFT JOIN LATERAL (
         SELECT status FROM appointment_payments
         WHERE appointment_id = a.appointment_id
         ORDER BY payment_id DESC LIMIT 1
     ) ap ON TRUE
     WHERE a.booking_group_id IS NOT NULL
     ORDER BY a.booking_group_id DESC, a.group_sequence
     LIMIT 30"
)->fetchAll(PDO::FETCH_ASSOC);

echo json_encode($rows, JSON_PRETTY_PRINT) . "\n";
