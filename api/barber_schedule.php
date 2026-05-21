<?php
// Barber schedule view + unavailability requests (receptionist approves).

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/slot_locking.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? 'listMonth'));

$allowed = ['listMonth', 'submitUnavailability', 'listRequests', 'reviewRequest'];
if (!in_array($action, $allowed, true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function ensure_unavailability_requests_table(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS barber_unavailability_requests (
            request_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            barber_id BIGINT NOT NULL,
            request_date DATE NOT NULL,
            note TEXT,
            status TEXT NOT NULL DEFAULT 'Pending'
                CHECK (status IN ('Pending', 'Approved', 'Rejected')),
            reviewed_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_unavailability_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id) ON DELETE CASCADE,
            CONSTRAINT uq_unavailability_barber_date UNIQUE (barber_id, request_date)
        )"
    );
}

try {
    $pdo = get_db_connection();
    ensure_unavailability_requests_table($pdo);

    if ($action === 'listMonth') {
        $barberID = (int)($input['barberID'] ?? 0);
        $year = (int)($input['year'] ?? 0);
        $month = (int)($input['month'] ?? 0);

        if ($barberID <= 0 || $year < 2000 || $month < 1 || $month > 12) {
            json_response(['error' => 'Invalid barberID/year/month'], 422);
        }

        $startDate = sprintf('%04d-%02d-01', $year, $month);
        $endDate = date('Y-m-d', strtotime($startDate . ' +1 month'));

        $slotStmt = $pdo->prepare(
            "SELECT slot_date, slot_time, status
             FROM time_slots
             WHERE barber_id = :barber_id
               AND slot_date >= :start_date
               AND slot_date < :end_date
             ORDER BY slot_date, slot_time"
        );
        $slotStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        $slots = $slotStmt->fetchAll();

        $apptStmt = $pdo->prepare(
            "SELECT a.appointment_id, a.booking_group_id, a.group_sequence, a.appointment_date,
                    a.start_time, a.end_time, a.status, a.group_member_name, a.booking_code,
                    u.full_name AS customer_name
             FROM appointments a
             JOIN users u ON a.user_id = u.user_id
             WHERE a.barber_id = :barber_id
               AND a.appointment_date >= :start_date
               AND a.appointment_date < :end_date
               AND a.status NOT IN ('Cancelled', 'NoShow')
             ORDER BY a.appointment_date, a.start_time"
        );
        $apptStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        $rawAppointments = $apptStmt->fetchAll();
        $mapped = array_map(static function (array $row): array {
            return [
                'appointmentID' => (int)$row['appointment_id'],
                'bookingGroupID' => $row['booking_group_id'] !== null ? (int)$row['booking_group_id'] : null,
                'groupSequence' => $row['group_sequence'] !== null ? (int)$row['group_sequence'] : null,
                'appointmentDate' => (string)$row['appointment_date'],
                'startTime' => (string)$row['start_time'],
                'endTime' => (string)$row['end_time'],
                'status' => (string)$row['status'],
                'customerName' => (string)$row['customer_name'],
            ];
        }, $rawAppointments);
        $collapsed = collapse_barber_dashboard_appointments($mapped);
        $appointments = array_map(static function (array $row): array {
            return [
                'appointment_id' => (int)($row['appointmentID'] ?? 0),
                'booking_group_id' => $row['bookingGroupID'] ?? null,
                'is_group' => (bool)($row['isGroup'] ?? false),
                'people_count' => (int)($row['peopleCount'] ?? 1),
                'display_title' => (string)($row['displayTitle'] ?? $row['customerName'] ?? 'Customer'),
                'appointment_date' => (string)($row['appointmentDate'] ?? ''),
                'start_time' => (string)($row['startTime'] ?? ''),
                'end_time' => (string)($row['endTime'] ?? ''),
                'time_range' => (string)($row['timeRange'] ?? ''),
                'status' => (string)($row['status'] ?? ''),
                'group_member_name' => (string)($row['displayTitle'] ?? ''),
                'booking_code' => (string)($row['bookingCode'] ?? ''),
            ];
        }, $collapsed);

        $reqStmt = $pdo->prepare(
            "SELECT request_id, request_date, note, status, created_at
             FROM barber_unavailability_requests
             WHERE barber_id = :barber_id
               AND request_date >= :start_date
               AND request_date < :end_date
             ORDER BY request_date"
        );
        $reqStmt->execute([
            ':barber_id' => $barberID,
            ':start_date' => $startDate,
            ':end_date' => $endDate,
        ]);
        $requests = $reqStmt->fetchAll();

        json_response([
            'slots' => $slots,
            'appointments' => $appointments,
            'requests' => $requests,
        ]);
    }

    if ($action === 'submitUnavailability') {
        $barberID = (int)($input['barberID'] ?? 0);
        $requestDate = trim((string)($input['requestDate'] ?? $input['date'] ?? ''));
        $note = trim((string)($input['note'] ?? ''));

        if ($barberID <= 0 || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $requestDate)) {
            json_response(['error' => 'Invalid barberID or requestDate'], 422);
        }

        $stmt = $pdo->prepare(
            "INSERT INTO barber_unavailability_requests (barber_id, request_date, note, status)
             VALUES (:barber_id, :request_date, :note, 'Pending')
             ON CONFLICT (barber_id, request_date)
             DO UPDATE SET note = EXCLUDED.note, status = 'Pending', reviewed_at = NULL
             RETURNING request_id, request_date, status"
        );
        $stmt->execute([
            ':barber_id' => $barberID,
            ':request_date' => $requestDate,
            ':note' => $note !== '' ? $note : null,
        ]);

        json_response([
            'message' => 'Unavailability request submitted for receptionist review.',
            'request' => $stmt->fetch(),
        ]);
    }

    if ($action === 'listRequests') {
        $status = trim((string)($input['status'] ?? 'Pending'));
        $stmt = $pdo->prepare(
            "SELECT r.request_id, r.barber_id, b.full_name AS barber_name,
                    r.request_date, r.note, r.status, r.created_at
             FROM barber_unavailability_requests r
             JOIN barbers b ON b.barber_id = r.barber_id
             WHERE r.status = :status
             ORDER BY r.created_at ASC"
        );
        $stmt->execute([':status' => $status]);
        json_response(['requests' => $stmt->fetchAll()]);
    }

    if ($action === 'reviewRequest') {
        $requestID = (int)($input['requestID'] ?? 0);
        $decision = trim((string)($input['decision'] ?? ''));
        if ($requestID <= 0 || !in_array($decision, ['Approved', 'Rejected'], true)) {
            json_response(['error' => 'Invalid requestID or decision'], 422);
        }

        $lookup = $pdo->prepare(
            'SELECT request_id, barber_id, request_date FROM barber_unavailability_requests WHERE request_id = :id'
        );
        $lookup->execute([':id' => $requestID]);
        $row = $lookup->fetch();
        if (!$row) {
            json_response(['error' => 'Request not found'], 404);
        }

        $pdo->beginTransaction();
        $update = $pdo->prepare(
            "UPDATE barber_unavailability_requests
             SET status = :status, reviewed_at = NOW()
             WHERE request_id = :id"
        );
        $update->execute([':status' => $decision, ':id' => $requestID]);

        if ($decision === 'Approved') {
            $barberId = (int)$row['barber_id'];
            $date = (string)$row['request_date'];
            foreach (shop_default_slot_times() as $slotTime) {
                $pdo->prepare(
                    "INSERT INTO time_slots (barber_id, slot_date, slot_time, status)
                     VALUES (:barber_id, :slot_date, :slot_time, 'Unavailable')
                     ON CONFLICT (barber_id, slot_date, slot_time)
                     DO UPDATE SET status = 'Unavailable'"
                )->execute([
                    ':barber_id' => $barberId,
                    ':slot_date' => $date,
                    ':slot_time' => $slotTime,
                ]);
            }
        }

        $pdo->commit();
        json_response(['message' => 'Request ' . strtolower($decision)]);
    }
} catch (PDOException $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
