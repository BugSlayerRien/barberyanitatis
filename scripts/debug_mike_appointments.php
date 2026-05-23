<?php
require_once dirname(__DIR__) . '/api/db.php';
require_once dirname(__DIR__) . '/api/slot_locking.php';

$pdo = get_db_connection();
$stmt = $pdo->query(
    "SELECT a.appointment_id, a.booking_group_id, a.barber_id, a.status, a.appointment_date,
            a.start_time, a.end_time, a.group_sequence, u.full_name
     FROM appointments a
     JOIN users u ON a.user_id = u.user_id
     WHERE u.full_name ILIKE '%Mike%'
       AND a.appointment_date = '2026-05-22'
       AND a.status NOT IN ('Cancelled', 'NoShow')
     ORDER BY a.barber_id, a.start_time"
);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
echo "Raw rows: " . count($rows) . "\n";
echo json_encode($rows, JSON_PRETTY_PRINT) . "\n\n";

foreach ([1, 2, 3] as $barberId) {
    $stmt2 = $pdo->prepare(
        "SELECT a.appointment_id, a.booking_code, a.booking_group_id, a.group_member_name, a.group_sequence,
                a.appointment_date, a.start_time, a.end_time, a.status,
                u.user_id AS customer_id, u.full_name AS customer_name
         FROM appointments a
         JOIN users u ON a.user_id = u.user_id
         WHERE a.barber_id = :barber_id
           AND a.status = 'Scheduled'
           AND a.appointment_date = '2026-05-22'"
    );
    $stmt2->execute([':barber_id' => $barberId]);
    $appts = array_map(static function (array $row): array {
        return [
            'appointmentID' => (int)$row['appointment_id'],
            'bookingGroupID' => $row['booking_group_id'] !== null ? (int)$row['booking_group_id'] : null,
            'groupSequence' => $row['group_sequence'] !== null ? (int)$row['group_sequence'] : null,
            'appointmentDate' => $row['appointment_date'],
            'startTime' => $row['start_time'],
            'endTime' => $row['end_time'],
            'status' => $row['status'],
            'customerID' => (int)$row['customer_id'],
            'customerName' => $row['customer_name'],
        ];
    }, $stmt2->fetchAll(PDO::FETCH_ASSOC));
    $collapsed = collapse_barber_dashboard_appointments($pdo, $appts, $barberId);
    echo "Barber $barberId collapsed count: " . count($collapsed) . "\n";
    echo json_encode($collapsed, JSON_PRETTY_PRINT) . "\n\n";
}
