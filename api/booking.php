<?php
// Booking API (create + list)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/service_channel.php';
require_once __DIR__ . '/appointment_notifications.php';
require_once __DIR__ . '/barber_channel.php';
require_once __DIR__ . '/shop_schedule.php';
require_once __DIR__ . '/group_booking.php';
require_once __DIR__ . '/booking_codes.php';
require_once __DIR__ . '/slot_locking.php';
require_once __DIR__ . '/appointment_expiry.php';
require_once __DIR__ . '/paymongo_reconcile.php';
require_once __DIR__ . '/face_scan_attach.php';
require_once __DIR__ . '/customer_auth.php';

function ensure_financial_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payments (
            payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            status VARCHAR(30) NOT NULL DEFAULT 'Captured',
            transaction_ref VARCHAR(120),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_payments_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
        )"
    );

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_refunds (
            refund_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            payment_id BIGINT,
            amount NUMERIC(10,2) NOT NULL,
            reason VARCHAR(80),
            status VARCHAR(30) NOT NULL DEFAULT 'Completed',
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_refunds_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
            CONSTRAINT fk_appointment_refunds_payment
                FOREIGN KEY (payment_id) REFERENCES appointment_payments(payment_id) ON DELETE SET NULL
        )"
    );

    // Refunds are settled by hand (GCash/cash), so the row has to carry who to
    // pay and who marked it done. The table existed but was never written to --
    // cancelling a paid booking simply lost the money silently.
    $pdo->exec("ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS contact_phone VARCHAR(40)");
    $pdo->exec("ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS user_id BIGINT");
    $pdo->exec("ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ");
    $pdo->exec("ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS completed_by VARCHAR(120)");
    $pdo->exec("ALTER TABLE appointment_refunds ADD COLUMN IF NOT EXISTS note TEXT");

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS appointment_payment_intents (
            intent_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            appointment_id BIGINT NOT NULL,
            amount NUMERIC(10,2) NOT NULL,
            method VARCHAR(40) NOT NULL,
            provider VARCHAR(30) NOT NULL DEFAULT 'mock',
            status VARCHAR(30) NOT NULL DEFAULT 'PendingGateway',
            intent_token VARCHAR(120) NOT NULL UNIQUE,
            provider_ref VARCHAR(120),
            failure_reason TEXT,
            expires_at TIMESTAMPTZ NOT NULL,
            paid_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_appointment_payment_intents_appointment
                FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE
        )"
    );

    $pdo->exec(
        'ALTER TABLE appointment_payment_intents
         ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()'
    );
    $pdo->exec(
        'ALTER TABLE appointment_payment_intents
         ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()'
    );
}

function ensure_appointment_detail_image_columns(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE appointment_details
         ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_right_url TEXT'
    );
}

function ensure_reschedule_count_column(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS reschedule_count INT NOT NULL DEFAULT 0'
    );
}

function ensure_cancel_reason_column(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS cancel_reason TEXT'
    );
}

function derive_payment_state(?string $paymentStatus, ?string $intentStatus): string
{
    $payment = $paymentStatus !== null ? trim((string)$paymentStatus) : '';
    if ($payment !== '' && in_array(strtolower($payment), ['captured', 'paid', 'succeeded'], true)) {
        return 'Paid';
    }
    if ($payment !== '' && strcasecmp($payment, 'Paid') === 0) {
        return 'Paid';
    }

    $intent = $intentStatus !== null ? trim((string)$intentStatus) : '';
    if ($intent !== '') {
        if (in_array($intent, ['PendingGateway', 'Verifying', 'Processing'], true)) {
            return 'Verifying';
        }
        if (in_array($intent, ['Failed', 'Expired', 'Cancelled'], true)) {
            return 'Failed';
        }
        if (in_array(strtolower($intent), ['paid', 'succeeded', 'captured'], true)) {
            return 'Paid';
        }
    }

    return 'Unpaid';
}

function promote_paid_appointment(PDO $pdo, int $appointmentId, string $currentStatus): string
{
    if ($currentStatus !== 'PendingPayment') {
        return $currentStatus;
    }

    return promote_paid_booking_unit($pdo, $appointmentId);
}

function ensure_appointments_status_constraint(PDO $pdo): void
{
    // Older schemas miss PendingPayment in appointments_status_check, causing booking inserts to fail.
    $constraintStmt = $pdo->prepare(
        "SELECT pg_get_constraintdef(c.oid) AS def
         FROM pg_constraint c
         JOIN pg_class t ON c.conrelid = t.oid
         JOIN pg_namespace n ON t.relnamespace = n.oid
         WHERE n.nspname = 'public'
           AND t.relname = 'appointments'
           AND c.conname = 'appointments_status_check'
         LIMIT 1"
    );
    $constraintStmt->execute();
    $row = $constraintStmt->fetch();

    if (!$row) {
        return;
    }

    $definition = (string)($row['def'] ?? '');
    if (stripos($definition, 'PendingPayment') !== false) {
        return;
    }

    $pdo->exec('ALTER TABLE appointments DROP CONSTRAINT IF EXISTS appointments_status_check');
    $pdo->exec(
        "ALTER TABLE appointments
         ADD CONSTRAINT appointments_status_check
         CHECK (
            status = ANY (
                ARRAY[
                    'PendingPayment'::text,
                    'Scheduled'::text,
                    'CheckedIn'::text,
                    'InProgress'::text,
                    'Completed'::text,
                    'Cancelled'::text,
                    'NoShow'::text
                ]
            )
         )"
    );
}

function normalize_time_string(string $value): ?string
{
    $value = trim($value);
    if ($value === '') {
        return null;
    }

    if (!preg_match('/^\d{2}:\d{2}(:\d{2})?$/', $value)) {
        return null;
    }

    $parts = explode(':', $value);
    $hour = (int)$parts[0];
    $minute = (int)$parts[1];
    $second = isset($parts[2]) ? (int)$parts[2] : 0;

    if ($hour < 0 || $hour > 23 || $minute < 0 || $minute > 59 || $second < 0 || $second > 59) {
        return null;
    }

    return sprintf('%02d:%02d:%02d', $hour, $minute, $second);
}

function is_valid_ymd_date(string $value): bool
{
    $date = DateTimeImmutable::createFromFormat('Y-m-d', $value);
    return $date !== false && $date->format('Y-m-d') === $value;
}

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['create', 'createGroup', 'listByCustomer', 'listByBarber', 'cancel', 'reschedule', 'getQuickBookProfile', 'getCustomerHomeInsights'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();
    $customer = null;
    if ($action !== 'listByBarber') {
        $customer = require_customer($pdo, $input);
    } else {
        $customer = ['user_id' => 0, 'email' => '', 'supabase_sub' => ''];
    }
    // Schema setup runs once per container, not on every request -- see
    // schema_ensure_once() in db.php. This block used to cost several seconds
    // on every booking call, including the read-only list the app fetches
    // before letting a customer book.
    schema_ensure_once('booking.core', static function () use ($pdo): void {
        ensure_service_channel_column($pdo);
        ensure_financial_tables($pdo);
        ensure_appointments_status_constraint($pdo);
        ensure_barber_channel_column($pdo);
        ensure_group_booking_schema($pdo);
        // Must stay in the always-run group: listByCustomer's SELECT references
        // cancel_reason directly, and on a fresh deploy no 'cancel' action may
        // have run yet to create the column.
        ensure_cancel_reason_column($pdo);
    });
    $readOnlyActions = ['listByCustomer', 'listByBarber', 'getQuickBookProfile', 'getCustomerHomeInsights'];
    if (!in_array($action, $readOnlyActions, true)) {
        schema_ensure_once('booking.write', static function () use ($pdo): void {
            ensure_appointment_detail_image_columns($pdo);
            ensure_reschedule_count_column($pdo);
        });
    }
    if (!in_array($action, $readOnlyActions, true)) {
        auto_complete_due_appointments($pdo);
    }
    $trackingAutomation = null;
    if (in_array($action, ['listByCustomer', 'listByBarber'], true)) {
        try {
            $trackingAutomation = run_tracking_automation($pdo, true);
            // Ask the gateway about payments the app never got to confirm (a
            // dropped connection on the way back from GCash), so the two syncs
            // below have something to promote instead of the customer being
            // asked to pay twice.
            reconcile_pending_gateway_payments($pdo);
            sync_paid_groups_from_payments($pdo);
            // Throttled like the rest: this used to be forced on every list
            // load, which made the Bookings page re-run the whole sweep on each
            // open, tab switch and cancel.
            sync_paid_appointments_from_payments($pdo);
            // Strictly after the two syncs above: they promote bookings that
            // did pay but were never flipped off PendingPayment, and expiring
            // first would cancel them.
            expire_unpaid_past_appointments($pdo);
            notify_unpaid_appointments_due_soon($pdo);
        } catch (Throwable $automationError) {
            error_log('Booking list automation skipped: ' . $automationError->getMessage());
        }
    }

    if ($action === 'createGroup') {
        $userID = (int)$customer['user_id'];
        $barberID = (int)($input['barberID'] ?? $input['primaryBarberID'] ?? 0);
        $slotDate = trim((string)($input['appointmentDate'] ?? $input['slotDate'] ?? ''));
        $slots = $input['slots'] ?? [];
        $memberNames = $input['memberNames'] ?? $input['peopleNames'] ?? [];
        $items = $input['items'] ?? null;
        $allowPartial = (bool)($input['allowPartial'] ?? $input['confirmPartial'] ?? false);
        $requestedCount = (int)($input['requestedCount'] ?? $input['peopleCount'] ?? count($slots));

        if ($userID <= 0 || $barberID <= 0 || $slotDate === '' || !is_array($slots) || count($slots) === 0) {
            json_response(['error' => 'Missing group booking details'], 422);
        }

        if (!is_array($memberNames)) {
            $memberNames = [];
        }

        if (!is_array($items)) {
            $variantID = resolve_group_booking_variant_id(
                $pdo,
                $userID,
                (int)($input['variantID'] ?? 0)
            );
            $serviceIDs = $input['serviceIDs'] ?? [];
            if ($variantID <= 0) {
                json_response(['error' => 'No hairstyle is available for group booking'], 422);
            }
            if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
                $defaultServiceId = (int)$pdo->query(
                    "SELECT service_id FROM services
                     WHERE category = 'Haircut' AND is_active = TRUE AND service_channel = 'appointment'
                     ORDER BY service_id LIMIT 1"
                )->fetchColumn();
                if ($defaultServiceId <= 0) {
                    json_response(['error' => 'No haircut service configured'], 422);
                }
                $serviceIDs = [$defaultServiceId];
            }
            $items = array_map(static fn($id) => ['serviceID' => (int)$id, 'variantID' => $variantID], $serviceIDs);
        }

        $GLOBALS['group_booking_requested_count'] = $requestedCount;
        $result = create_group_booking(
            $pdo,
            $userID,
            $barberID,
            $slotDate,
            $slots,
            array_values($memberNames),
            $items,
            $allowPartial
        );
        unset($GLOBALS['group_booking_requested_count']);

        json_response([
            'message' => 'Group booking created',
            'group' => $result,
            'appointmentID' => $result['appointmentIDs'][0] ?? null,
            'totalAmount' => $result['totalAmount'],
        ]);
    }

    if ($action === 'create') {
        $userID = (int)$customer['user_id'];
        $barberID = (int)($input['barberID'] ?? 0);
        $appointmentDate = trim((string)($input['appointmentDate'] ?? ''));
        $startTimeRaw = trim((string)($input['startTime'] ?? ''));
        $endTimeRaw = trim((string)($input['endTime'] ?? ''));
        $items = $input['items'] ?? null;
        $serviceIDs = $input['serviceIDs'] ?? [];
        $variantID = (int)($input['variantID'] ?? 0);

        $startTime = normalize_time_string($startTimeRaw);
        $endTime = normalize_time_string($endTimeRaw);

        if ($userID <= 0 || $barberID <= 0 || $appointmentDate === '' || $startTime === null || $endTime === null) {
            json_response(['error' => 'Missing or invalid booking details'], 422);
        }

        if (!is_valid_ymd_date($appointmentDate)) {
            json_response(['error' => 'Invalid appointmentDate format (expected YYYY-MM-DD).'], 422);
        }

        $shopTz = new DateTimeZone(shop_timezone());
        $appointmentDateTimeStart = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $appointmentDate . ' ' . $startTime, $shopTz);
        $appointmentDateTimeEnd = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $appointmentDate . ' ' . $endTime, $shopTz);
        if ($appointmentDateTimeStart === false || $appointmentDateTimeEnd === false) {
            json_response(['error' => 'Invalid appointment date/time value.'], 422);
        }

        if (shop_is_closed_date($appointmentDate)) {
            json_response(['error' => 'The shop is closed on the selected date.'], 422);
        }

        if (shop_is_break_slot_time($startTime, $appointmentDate)) {
            json_response(['error' => format_time_12h($startTime) . ' falls on a barber break and cannot be booked.'], 422);
        }

        if (!shop_is_time_within_hours($startTime, $appointmentDate) || !shop_is_allowed_slot_time($startTime, $appointmentDate)) {
            json_response([
                'error' => 'Selected time is outside shop hours ('
                    . format_time_range_12h(shop_open_time($appointmentDate), shop_close_time($appointmentDate)) . ').',
            ], 422);
        }

        $durationMinutes = shop_appointment_duration_minutes();
        $endTime = shop_add_minutes_to_time($startTime, $durationMinutes);
        $appointmentDateTimeEnd = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $appointmentDate . ' ' . $endTime, $shopTz);
        if ($appointmentDateTimeEnd === false || $appointmentDateTimeEnd <= $appointmentDateTimeStart) {
            json_response(['error' => 'Invalid appointment time range.'], 422);
        }

        if (!shop_is_future_slot($appointmentDate, $startTime)) {
            json_response([
                'error' => 'This time is no longer available. Choose a slot at least 1 hour from now.',
            ], 422);
        }

        $userCheck = $pdo->prepare('SELECT COUNT(*) FROM users WHERE user_id = :user_id AND is_active = TRUE');
        $userCheck->execute([':user_id' => $userID]);
        if ((int)$userCheck->fetchColumn() === 0) {
            json_response(['error' => 'Invalid or inactive customer account.'], 422);
        }

        $barberCheck = $pdo->prepare(
            // Uses the shared filter so the queue-merge toggle reaches this
            // check too; hardcoded, it kept rejecting walk-in barbers even
            // when the two queues were merged.
            "SELECT COUNT(*) FROM barbers
             WHERE barber_id = :barber_id
               AND is_active = TRUE" . barber_channel_filter_sql('appointment')
        );
        $barberCheck->execute([':barber_id' => $barberID]);
        if ((int)$barberCheck->fetchColumn() === 0) {
            json_response(['error' => 'This barber is not available for appointments. Please choose another barber.'], 422);
        }

        if (!is_array($items)) {
            if ($variantID <= 0) {
                json_response(['error' => 'Missing variantID'], 422);
            }

            if (!is_array($serviceIDs) || count($serviceIDs) === 0) {
                $defaultServiceId = (int)$pdo->query(
                    "SELECT service_id FROM services
                     WHERE category = 'Haircut' AND is_active = TRUE AND service_channel = 'appointment'
                     ORDER BY service_id LIMIT 1"
                )->fetchColumn();
                if ($defaultServiceId <= 0) {
                    json_response(['error' => 'No haircut service configured'], 422);
                }
                $serviceIDs = [$defaultServiceId];
            }

            $items = array_map(fn($id) => ['serviceID' => (int)$id, 'variantID' => $variantID], $serviceIDs);
        }

        $serviceInfoStmt = $pdo->prepare(
            'SELECT service_id, base_price
             FROM services
             WHERE service_id = :service_id AND is_active = TRUE'
        );
        $variantExistsStmt = $pdo->prepare(
            'SELECT COUNT(*)
             FROM hairstyle_variants hv
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE hv.variant_id = :variant_id
               AND hs.is_active = TRUE'
        );

        $validatedItems = [];
        foreach ($items as $index => $item) {
            $serviceID = (int)($item['serviceID'] ?? 0);
            $variantIDItem = (int)($item['variantID'] ?? 0);

            if ($serviceID <= 0 || $variantIDItem <= 0) {
                continue;
            }

            $serviceInfoStmt->execute([':service_id' => $serviceID]);
            $serviceInfo = $serviceInfoStmt->fetch();
            if (!$serviceInfo) {
                json_response(['error' => 'Selected service is unavailable. Please refresh and try again.'], 422);
            }

            $variantExistsStmt->execute([':variant_id' => $variantIDItem]);
            if ((int)$variantExistsStmt->fetchColumn() === 0) {
                json_response(['error' => 'Selected haircut is unavailable. Please select another style and try again.'], 422);
            }

            $finalPrice = $item['finalPrice'] ?? null;
            if ($finalPrice === null || $finalPrice === '') {
                $finalPrice = $serviceInfo['base_price'];
            }

            $validatedItems[] = [
                'serviceID' => $serviceID,
                'variantID' => $variantIDItem,
                'selectedView' => $item['selectedView'] ?? 'Front',
                'specialInstructions' => $item['specialInstructions'] ?? '',
                'finalPrice' => $finalPrice,
            ];
        }

        if (count($validatedItems) === 0) {
            json_response(['error' => 'No valid booking items were provided.'], 422);
        }

        $activeStmt = $pdo->prepare(
            "SELECT COUNT(DISTINCT COALESCE(booking_group_id::text, 'single-' || appointment_id::text))
             FROM appointments
             WHERE user_id = :user_id
             AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')"
        );
        $activeStmt->execute([':user_id' => $userID]);
        if ((int)$activeStmt->fetchColumn() > 0) {
            json_response(['error' => 'You already have an active appointment.'], 409);
        }

        $barberOverlapStmt = $pdo->prepare(
            "SELECT COUNT(*) FROM appointments
             WHERE barber_id = :barber_id
               AND appointment_date = :appointment_date
               AND status IN ('Scheduled', 'CheckedIn', 'InProgress')
               AND (
                    (start_time < :end_time AND end_time > :start_time)
               )"
        );
        $barberOverlapStmt->execute([
            ':barber_id' => $barberID,
            ':appointment_date' => $appointmentDate,
            ':start_time' => $startTime,
            ':end_time' => $endTime,
        ]);
        if ((int)$barberOverlapStmt->fetchColumn() > 0) {
            json_response(['error' => 'Selected time overlaps with another appointment for this barber.'], 409);
        }

        if (paid_slot_conflict_exists($pdo, $barberID, $appointmentDate, $startTime, [])) {
            json_response(['error' => 'Selected time slot is already booked (paid). Choose another time.'], 409);
        }

        $pdo->beginTransaction();

        $stmt = $pdo->prepare(
              'INSERT INTO appointments (booking_code, user_id, barber_id, appointment_date, start_time, end_time, status)
               VALUES (:booking_code, :user_id, :barber_id, :appointment_date, :start_time, :end_time, :status)
             RETURNING appointment_id'
        );
        $inserted = insert_appointment_with_unique_code(
            $pdo,
            $appointmentDate,
            static function (string $bookingCode) use (
                $stmt,
                $userID,
                $barberID,
                $appointmentDate,
                $startTime,
                $endTime
            ): array {
                $stmt->execute([
                    ':booking_code' => $bookingCode,
                    ':user_id' => $userID,
                    ':barber_id' => $barberID,
                    ':appointment_date' => $appointmentDate,
                    ':start_time' => $startTime,
                    ':end_time' => $endTime,
                    ':status' => 'PendingPayment',
                ]);

                return [
                    'id' => (int)$stmt->fetchColumn(),
                    'code' => $bookingCode,
                ];
            }
        );
        $appointmentID = (int)$inserted['id'];
        $bookingCode = (string)$inserted['code'];

        // Single bookings send one note for the whole appointment (the flat
        // serviceIDs path builds items without a per-item key), while group
        // bookings can still carry per-item instructions. Per-item wins.
        $bookingNote = trim((string)($input['specialInstructions'] ?? ''));

        $detailStmt = $pdo->prepare(
            'INSERT INTO appointment_details (appointment_id, service_id, variant_id, selected_view, special_instructions, final_price)
             VALUES (:appointment_id, :service_id, :variant_id, :selected_view, :special_instructions, :final_price)'
        );

        foreach ($validatedItems as $item) {
            $serviceID = (int)($item['serviceID'] ?? 0);
            $variantIDItem = (int)($item['variantID'] ?? 0);
            $selectedView = trim((string)($item['selectedView'] ?? 'Front'));
            $specialInstructions = trim((string)($item['specialInstructions'] ?? ''));
            if ($specialInstructions === '') {
                $specialInstructions = $bookingNote;
            }
            $finalPrice = $item['finalPrice'] ?? null;

            if ($serviceID <= 0 || $variantIDItem <= 0) {
                continue;
            }

            // $specialInstructions was previously extracted here and then never
            // bound, so anything the customer sent was silently discarded.
            $detailStmt->execute([
                ':appointment_id' => $appointmentID,
                ':service_id' => $serviceID,
                ':variant_id' => $variantIDItem,
                ':selected_view' => $selectedView !== '' ? $selectedView : 'Front',
                ':special_instructions' => $specialInstructions !== '' ? $specialInstructions : null,
                ':final_price' => $finalPrice,
            ]);
        }

        $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
        $previewVariantId = $variantID > 0 ? $variantID : (int)($validatedItems[0]['variantID'] ?? 0);
        $previewAttach = null;
        if ($scanSessionId !== '' && $previewVariantId > 0) {
            $previewAttach = attach_scan_previews_to_appointment(
                $pdo,
                $appointmentID,
                $scanSessionId,
                $previewVariantId,
                [
                    'frontViewUrl' => (string)($input['frontViewUrl'] ?? ''),
                    'sideViewUrl' => (string)($input['sideViewUrl'] ?? ''),
                    'backViewUrl' => (string)($input['backViewUrl'] ?? ''),
                ]
            );
        }

        notify_appointment_created($pdo, [
            'user_id' => $userID,
            'barber_id' => $barberID,
            'booking_code' => $bookingCode,
            'appointment_date' => $appointmentDate,
            'start_time' => $startTime,
        ]);

        // Log appointment creation to audit trail
        audit_log($pdo, 'CREATE', 'appointments', (string)$appointmentID, null, [
            'booking_code' => $bookingCode,
            'user_id' => $userID,
            'barber_id' => $barberID,
            'appointment_date' => $appointmentDate,
            'start_time' => $startTime,
            'status' => 'PendingPayment',
        ], $userID);

        $pdo->commit();

        $responsePayload = [
            'message' => 'Appointment created',
            'appointmentID' => $appointmentID,
            'bookingCode' => $bookingCode,
            'status' => 'PendingPayment',
        ];
        if (is_array($previewAttach) && ($previewAttach['attached'] ?? false)) {
            $responsePayload['frontViewUrl'] = $previewAttach['front'];
            $responsePayload['sideViewUrl'] = $previewAttach['left'];
            $responsePayload['backViewUrl'] = $previewAttach['right'];
            $responsePayload['previewsAttached'] = true;
        }

        json_response($responsePayload, 201);
    }

    if ($action === 'getCustomerHomeInsights') {
        $userID = (int)$customer['user_id'];

        $favoriteBarber = null;
        // Avoid information_schema on every home load (slow on some hosts).
        try {
            $favStmt = $pdo->prepare(
                "SELECT b.barber_id, b.full_name, b.specialty, b.profile_image,
                        ROUND(AVG(bf.rating)::numeric, 1) AS avg_rating,
                        COUNT(*)::int AS rating_count
                 FROM barber_feedback bf
                 JOIN barbers b ON b.barber_id = bf.barber_id
                 WHERE bf.user_id = :user_id
                   AND b.is_active = TRUE
                 GROUP BY b.barber_id, b.full_name, b.specialty, b.profile_image
                 ORDER BY AVG(bf.rating) DESC, COUNT(*) DESC
                 LIMIT 1"
            );
            $favStmt->execute([':user_id' => $userID]);
            $favRow = $favStmt->fetch(PDO::FETCH_ASSOC);
            if ($favRow) {
                $favoriteBarber = [
                    'barberId' => (int)$favRow['barber_id'],
                    'fullName' => (string)$favRow['full_name'],
                    'specialty' => (string)($favRow['specialty'] ?? ''),
                    'profileImage' => (string)($favRow['profile_image'] ?? ''),
                    'avgRating' => (float)$favRow['avg_rating'],
                    'ratingCount' => (int)$favRow['rating_count'],
                    'source' => 'customer_ratings',
                ];
            }
        } catch (Throwable $e) {
            // barber_feedback may not exist yet — fall through to most-booked.
            $favoriteBarber = null;
        }

        if ($favoriteBarber === null) {
            $mostBookedStmt = $pdo->prepare(
                "SELECT b.barber_id, b.full_name, b.specialty, b.profile_image, b.rating,
                        COUNT(*)::int AS booking_count
                 FROM appointments a
                 JOIN barbers b ON b.barber_id = a.barber_id
                 WHERE a.user_id = :user_id
                   AND a.status IN ('Completed', 'Scheduled', 'CheckedIn', 'InProgress')
                   AND b.is_active = TRUE
                 GROUP BY b.barber_id, b.full_name, b.specialty, b.profile_image, b.rating
                 ORDER BY COUNT(*) DESC, b.rating DESC
                 LIMIT 1"
            );
            $mostBookedStmt->execute([':user_id' => $userID]);
            $bookedRow = $mostBookedStmt->fetch(PDO::FETCH_ASSOC);
            if ($bookedRow) {
                $favoriteBarber = [
                    'barberId' => (int)$bookedRow['barber_id'],
                    'fullName' => (string)$bookedRow['full_name'],
                    'specialty' => (string)($bookedRow['specialty'] ?? ''),
                    'profileImage' => (string)($bookedRow['profile_image'] ?? ''),
                    'avgRating' => (float)$bookedRow['rating'],
                    'ratingCount' => (int)$bookedRow['booking_count'],
                    'source' => 'most_booked',
                ];
            }
        }

        $recentHaircut = null;
        $recentStmt = $pdo->prepare(
            "SELECT a.appointment_id, a.appointment_date, a.barber_id, b.full_name AS barber_name,
                    ad.variant_id, ad.service_id,
                    COALESCE(hs.style_name, s.service_name) AS style_name
             FROM appointments a
             JOIN appointment_details ad ON ad.appointment_id = a.appointment_id
             JOIN services s ON s.service_id = ad.service_id
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = ad.variant_id
             LEFT JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
             LEFT JOIN barbers b ON b.barber_id = a.barber_id
             WHERE a.user_id = :user_id
               AND a.status = 'Completed'
             ORDER BY a.appointment_date DESC, a.start_time DESC
             LIMIT 1"
        );
        $recentStmt->execute([':user_id' => $userID]);
        $recentRow = $recentStmt->fetch(PDO::FETCH_ASSOC);
        if ($recentRow) {
            $recentHaircut = [
                'appointmentId' => (int)$recentRow['appointment_id'],
                'styleName' => (string)($recentRow['style_name'] ?? 'Haircut'),
                'variantId' => (int)($recentRow['variant_id'] ?? 0),
                'serviceId' => (int)($recentRow['service_id'] ?? 0),
                'barberId' => (int)($recentRow['barber_id'] ?? 0),
                'barberName' => (string)($recentRow['barber_name'] ?? 'Barber'),
                'appointmentDate' => (string)($recentRow['appointment_date'] ?? ''),
            ];
        }

        $trendingHaircut = null;
        // Must match the admin dashboard's "Most booked haircuts" for its
        // "Last 3 months" period (api/admin_analytics.php $mostBookedStyles):
        // same 90 days ending today, same active statuses, ranked per haircut.
        // Previously this had no upper bound (future bookings counted) and
        // ranked per variant+service, so the two screens disagreed.
        $trendStmt = $pdo->query(
            "WITH booked AS (
                 SELECT hs.hairstyle_id, hs.style_name, ad.variant_id, ad.service_id,
                        COUNT(*)::int AS n
                 FROM appointment_details ad
                 JOIN appointments a ON a.appointment_id = ad.appointment_id
                 JOIN hairstyle_variants hv ON hv.variant_id = ad.variant_id
                 JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
                 WHERE ad.variant_id IS NOT NULL
                   AND ad.variant_id > 0
                   AND a.status IN ('Completed', 'Scheduled', 'CheckedIn', 'InProgress')
                   AND a.appointment_date >= (CURRENT_DATE - INTERVAL '89 days')::date
                   AND a.appointment_date < (CURRENT_DATE + INTERVAL '1 day')::date
                 GROUP BY hs.hairstyle_id, hs.style_name, ad.variant_id, ad.service_id
             )
             SELECT style_name,
                    (ARRAY_AGG(variant_id ORDER BY n DESC, variant_id))[1] AS variant_id,
                    (ARRAY_AGG(service_id ORDER BY n DESC, variant_id))[1] AS service_id,
                    SUM(n)::int AS booking_count
             FROM booked
             GROUP BY hairstyle_id, style_name
             ORDER BY booking_count DESC, style_name ASC
             LIMIT 1"
        );
        $trendRow = $trendStmt ? $trendStmt->fetch(PDO::FETCH_ASSOC) : false;
        if ($trendRow) {
            $trendingHaircut = [
                'variantId' => (int)$trendRow['variant_id'],
                'styleName' => (string)($trendRow['style_name'] ?? 'Haircut'),
                'serviceId' => (int)($trendRow['service_id'] ?? 0),
                'bookingCount' => (int)$trendRow['booking_count'],
            ];
        }

        json_response([
            'favoriteBarber' => $favoriteBarber,
            'recentHaircut' => $recentHaircut,
            'trendingHaircut' => $trendingHaircut,
        ]);
    }

    if ($action === 'getQuickBookProfile') {
        require_once __DIR__ . '/ai_funnel.php';
        ensure_ai_funnel_tables($pdo);

        $userID = (int)$customer['user_id'];

        $completedStmt = $pdo->prepare(
            "SELECT ad.variant_id, ad.service_id,
                    COALESCE(hs.style_name, s.service_name) AS style_name
             FROM appointments a
             JOIN appointment_details ad ON ad.appointment_id = a.appointment_id
             JOIN services s ON s.service_id = ad.service_id
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = ad.variant_id
             LEFT JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
             WHERE a.user_id = :user_id
               AND a.status = 'Completed'
               AND ad.variant_id IS NOT NULL
               AND ad.variant_id > 0
             ORDER BY a.appointment_date DESC, a.start_time DESC
             LIMIT 1"
        );
        $completedStmt->execute([':user_id' => $userID]);
        $completed = $completedStmt->fetch(PDO::FETCH_ASSOC);

        if ($completed) {
            json_response([
                'profile' => [
                    'eligible' => true,
                    'variantId' => (int)$completed['variant_id'],
                    'styleName' => (string)($completed['style_name'] ?? 'Haircut'),
                    'serviceId' => (int)$completed['service_id'],
                    'source' => 'completed_appointment',
                ],
            ]);
        }

        $prefStmt = $pdo->prepare(
            'SELECT preferred_variant_id, preferred_style_name
             FROM user_style_preferences
             WHERE user_id = :user_id
               AND preferred_variant_id IS NOT NULL
               AND preferred_variant_id > 0
             LIMIT 1'
        );
        $prefStmt->execute([':user_id' => $userID]);
        $pref = $prefStmt->fetch(PDO::FETCH_ASSOC);

        if ($pref) {
            $variantId = (int)$pref['preferred_variant_id'];
            $serviceStmt = $pdo->prepare(
                "SELECT service_id FROM services
                 WHERE is_active = TRUE AND LOWER(category) = 'haircut'
                 ORDER BY service_id ASC LIMIT 1"
            );
            $serviceStmt->execute();
            $serviceId = (int)($serviceStmt->fetchColumn() ?: 0);

            json_response([
                'profile' => [
                    'eligible' => true,
                    'variantId' => $variantId,
                    'styleName' => (string)($pref['preferred_style_name'] ?? 'Haircut'),
                    'serviceId' => $serviceId > 0 ? $serviceId : null,
                    'source' => 'style_preference',
                ],
            ]);
        }

        json_response([
            'profile' => [
                'eligible' => false,
                'variantId' => null,
                'styleName' => null,
                'serviceId' => null,
                'source' => null,
            ],
        ]);
    }

    if ($action === 'listByCustomer') {
        $userID = (int)$customer['user_id'];

        $paymentsTableExists = (int)$pdo->query(
            "SELECT COUNT(*) FROM information_schema.tables
             WHERE table_schema = current_schema() AND table_name = 'payments'"
        )->fetchColumn() > 0;

        $legacyPayJoin = $paymentsTableExists
            ? "LEFT JOIN LATERAL (
                 SELECT payment_id, payment_status AS status, payment_ref AS transaction_ref, paid_at AS created_at
                 FROM payments
                 WHERE appointment_id = a.appointment_id
                   AND payment_status = 'Paid'
                 ORDER BY payment_id DESC
                 LIMIT 1
             ) legacy_pay ON TRUE"
            : '';

        $paymentStatusExpr = $paymentsTableExists
            ? 'COALESCE(ap.status, legacy_pay.status)'
            : 'ap.status';
        $transactionRefExpr = $paymentsTableExists
            ? 'COALESCE(ap.transaction_ref, legacy_pay.transaction_ref)'
            : 'ap.transaction_ref';
        $paidAtExpr = $paymentsTableExists
            ? 'COALESCE(ap.created_at, legacy_pay.created_at)'
            : 'ap.created_at';

        $stmt = $pdo->prepare(
            "SELECT a.appointment_id, a.booking_code, a.booking_group_id, a.group_member_name, a.group_sequence,
                    a.appointment_date, a.start_time, a.end_time, a.status, a.cancel_reason,
                    COALESCE(a.reschedule_count, 0) AS reschedule_count,
                    b.barber_id, b.full_name AS barber_name,
                    u.full_name AS customer_name,
                    {$paymentStatusExpr} AS payment_status,
                    {$transactionRefExpr} AS transaction_ref,
                    {$paidAtExpr} AS paid_at,
                    pi.intent_id, pi.status AS intent_status, pi.method AS intent_method, pi.expires_at AS intent_expires_at,
                    pi.created_at AS intent_created_at,
                    pi.failure_reason, pi.updated_at AS intent_updated_at
             FROM appointments a
             JOIN barbers b ON a.barber_id = b.barber_id
             JOIN users u ON a.user_id = u.user_id
             LEFT JOIN LATERAL (
                 SELECT payment_id, status, transaction_ref, created_at
                 FROM appointment_payments
                 WHERE appointment_id = a.appointment_id
                 ORDER BY payment_id DESC
                 LIMIT 1
             ) ap ON TRUE
             {$legacyPayJoin}
             LEFT JOIN LATERAL (
                 SELECT intent_id, status, method, expires_at, created_at, failure_reason, updated_at
                 FROM appointment_payment_intents
                 WHERE appointment_id = a.appointment_id
                 ORDER BY intent_id DESC
                 LIMIT 1
             ) pi ON TRUE
             WHERE a.user_id = :user_id
             ORDER BY a.appointment_date DESC, a.start_time DESC"
        );
           $stmt->execute([':user_id' => $userID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            $emptyResponse = ['appointments' => []];
            if ($trackingAutomation !== null) {
                $emptyResponse['trackingAutomation'] = $trackingAutomation;
            }
            json_response($emptyResponse);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointment_id'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $serviceStmt = $pdo->prepare(
            "SELECT ad.appointment_id, ad.service_id, ad.variant_id, ad.final_price,
                    s.service_name, s.base_duration,
                    hs.style_name AS hairstyle_name,
                    COALESCE(ad.customer_front_url, hv.front_view_url) AS front_view_url,
                    COALESCE(ad.customer_left_url, hv.side_view_url) AS side_view_url,
                    COALESCE(ad.customer_right_url, hv.back_view_url) AS back_view_url
             FROM appointment_details ad
             JOIN services s ON ad.service_id = s.service_id
             LEFT JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
             LEFT JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE ad.appointment_id IN ($inClause)"
        );
        $serviceStmt->execute($appointmentIds);
        $serviceRows = $serviceStmt->fetchAll();

        $serviceMap = [];
        $imageMap = [];
        foreach ($serviceRows as $row) {
            $aid = (int)$row['appointment_id'];
            if (!isset($serviceMap[$aid])) {
                $serviceMap[$aid] = [];
                // Store the first variant's image URLs for this appointment
                $imageMap[$aid] = [
                    'frontViewUrl' => $row['front_view_url'],
                    'sideViewUrl' => $row['side_view_url'],
                    'backViewUrl' => $row['back_view_url'],
                ];
            }
            $serviceMap[$aid][] = [
                'serviceID' => (int)$row['service_id'],
                'serviceName' => $row['service_name'],
                'hairstyleName' => $row['hairstyle_name'],
                'variantID' => (int)($row['variant_id'] ?? 0),
                'durationMinutes' => (int)$row['base_duration'],
                'price' => (string)($row['final_price'] ?? '0'),
            ];
        }

        $appointments = array_map(function ($row) use ($serviceMap, $imageMap, $pdo) {
            $aid = (int)$row['appointment_id'];
            $intentStatus = $row['intent_status'] !== null ? (string)$row['intent_status'] : null;
            $paymentStatus = $row['payment_status'] !== null ? (string)$row['payment_status'] : null;
            $paymentState = derive_payment_state($paymentStatus, $intentStatus);
            $appointmentStatus = (string)$row['status'];
            if ($paymentState === 'Paid' && $appointmentStatus === 'PendingPayment') {
                try {
                    $appointmentStatus = promote_paid_appointment($pdo, $aid, $appointmentStatus);
                } catch (Throwable $promoteError) {
                    // Listing must not fail if slot lock races; payment row still shows Paid.
                }
            }
            $canRetryPayment = in_array($paymentState, ['Unpaid', 'Failed'], true);
            if ($intentStatus === 'PendingGateway' && $row['intent_expires_at'] !== null) {
                $canRetryPayment = strtotime((string)$row['intent_expires_at']) < time();
            }
            $rowForPolicy = $row;
            $rowForPolicy['status'] = $appointmentStatus;
            $reschedulePolicy = can_customer_reschedule_appointment($rowForPolicy, $paymentState);
            $rescheduleCount = (int)($row['reschedule_count'] ?? 0);
            return [
                'appointmentID' => $aid,
                'bookingCode' => $row['booking_code'],
                'bookingGroupID' => $row['booking_group_id'] !== null ? (int)$row['booking_group_id'] : null,
                'groupMemberName' => $row['group_member_name'] !== null ? (string)$row['group_member_name'] : null,
                'customerName' => trim((string)($row['customer_name'] ?? '')),
                'groupSequence' => $row['group_sequence'] !== null ? (int)$row['group_sequence'] : null,
                'appointmentDate' => $row['appointment_date'],
                'startTime' => $row['start_time'],
                'endTime' => $row['end_time'],
                'status' => $appointmentStatus,
                'cancelReason' => $row['cancel_reason'] !== null ? (string)$row['cancel_reason'] : null,
                'barberID' => (int)$row['barber_id'],
                'barberName' => $row['barber_name'],
                'paymentState' => $paymentState,
                'paymentStatus' => $paymentStatus,
                'receiptRef' => $row['transaction_ref'] !== null ? (string)$row['transaction_ref'] : null,
                'paidAt' => $row['paid_at'] !== null ? (string)$row['paid_at'] : null,
                'intentID' => $row['intent_id'] !== null ? (int)$row['intent_id'] : null,
                'intentStatus' => $intentStatus,
                'intentMethod' => $row['intent_method'] !== null ? (string)$row['intent_method'] : null,
                'intentExpiresAt' => $row['intent_expires_at'] !== null ? (string)$row['intent_expires_at'] : null,
                'intentCreatedAt' => $row['intent_created_at'] !== null ? (string)$row['intent_created_at'] : null,
                'holdExpiresAt' => ($row['intent_created_at'] !== null && (string)$row['status'] === 'PendingPayment')
                    ? date('Y-m-d H:i:s', strtotime((string)$row['intent_created_at']) + (shop_reservation_hold_minutes() * 60))
                    : null,
                'intentFailureReason' => $row['failure_reason'] !== null ? (string)$row['failure_reason'] : null,
                'intentUpdatedAt' => $row['intent_updated_at'] !== null ? (string)$row['intent_updated_at'] : null,
                'canRetryPayment' => $canRetryPayment,
                'canReschedule' => $reschedulePolicy['allowed'],
                'rescheduleCount' => $rescheduleCount,
                'reschedulesRemaining' => $reschedulePolicy['remaining'],
                'rescheduleBlockedReason' => $reschedulePolicy['reason'] !== ''
                    ? $reschedulePolicy['reason']
                    : null,
                'services' => $serviceMap[$aid] ?? [],
                'frontViewUrl' => ($imageMap[$aid]['frontViewUrl'] ?? null),
                'sideViewUrl' => ($imageMap[$aid]['sideViewUrl'] ?? null),
                'backViewUrl' => ($imageMap[$aid]['backViewUrl'] ?? null),
            ];
        }, $appointments);

        $listResponse = [
            'appointments' => collapse_customer_appointments(
                $pdo,
                propagate_group_payment_states($appointments)
            ),
        ];
        if ($trackingAutomation !== null) {
            $listResponse['trackingAutomation'] = $trackingAutomation;
        }
        json_response($listResponse);
    }

    if ($action === 'cancel') {
        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $userID = (int)$customer['user_id'];
        // The app has always sent this (see mobile-app appointments_page.dart's
        // cancel-reason dropdown), but it was never read here — collected from
        // the customer and then silently discarded on every cancellation.
        $cancelReason = trim((string)($input['reason'] ?? ''));
        if ($appointmentID <= 0) {
            json_response(['error' => 'Invalid appointmentID'], 422);
        }

        ensure_group_booking_schema($pdo);
        ensure_cancel_reason_column($pdo);

        $apptStmt = $pdo->prepare(
            'SELECT appointment_id, user_id, barber_id, appointment_date, start_time, status, booking_group_id
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }

        if ((int)$appt['user_id'] !== $userID) {
            json_response(['error' => 'You can only cancel your own appointments'], 403);
        }

        if ((string)$appt['status'] === 'Cancelled') {
            json_response(['message' => 'Appointment already cancelled']);
        }

        $groupId = (int)($appt['booking_group_id'] ?? 0);
        $pdo->beginTransaction();

        if ($groupId > 0) {
            $cancelStmt = $pdo->prepare(
                "UPDATE appointments
                 SET status = 'Cancelled', cancel_reason = :cancel_reason, updated_at = CURRENT_TIMESTAMP
                 WHERE booking_group_id = :group_id
                   AND status NOT IN ('Cancelled', 'NoShow', 'Completed')"
            );
            $cancelStmt->execute([
                ':group_id' => $groupId,
                ':cancel_reason' => $cancelReason !== '' ? $cancelReason : null,
            ]);

            $membersStmt = $pdo->prepare(
                "SELECT appointment_id FROM appointments WHERE booking_group_id = :group_id"
            );
            $membersStmt->execute([':group_id' => $groupId]);
            $memberIds = [];
            foreach ($membersStmt->fetchAll(PDO::FETCH_ASSOC) as $member) {
                $memberIds[] = (int)$member['appointment_id'];
                release_slots_for_appointment($pdo, (int)$member['appointment_id']);
            }
            if ($memberIds !== []) {
                $placeholders = implode(',', array_fill(0, count($memberIds), '?'));
                $expireIntents = $pdo->prepare(
                    "UPDATE appointment_payment_intents
                     SET status = 'Expired', updated_at = NOW()
                     WHERE appointment_id IN ($placeholders)
                       AND status IN ('PendingGateway', 'Verifying')"
                );
                $expireIntents->execute($memberIds);
            }
        } else {
            $stmt = $pdo->prepare(
                "UPDATE appointments
                 SET status = 'Cancelled', cancel_reason = :cancel_reason, updated_at = CURRENT_TIMESTAMP
                 WHERE appointment_id = :appointment_id"
            );
            $stmt->execute([
                ':appointment_id' => $appointmentID,
                ':cancel_reason' => $cancelReason !== '' ? $cancelReason : null,
            ]);
            release_slots_for_appointment($pdo, $appointmentID);

            $expireIntent = $pdo->prepare(
                "UPDATE appointment_payment_intents
                 SET status = 'Expired', updated_at = NOW()
                 WHERE appointment_id = :appointment_id
                   AND status IN ('PendingGateway', 'Verifying')"
            );
            $expireIntent->execute([':appointment_id' => $appointmentID]);
        }

        // Money already taken must not vanish when the booking is cancelled.
        // Raise a Pending refund the receptionist settles by hand (GCash/cash);
        // there is no gateway auto-refund in this system.
        //
        // The app records booking payments in appointment_payments with status
        // 'Captured'. An earlier version of this looked in `payments` for
        // status 'Paid' -- that is the walk-in/analytics ledger, so no app
        // booking ever matched and cancelling a paid booking silently raised no
        // refund at all. Check appointment_payments first, then fall back to
        // `payments` for anything booked through the desk.
        $refundRow = null;
        $paidStmt = $pdo->prepare(
            "SELECT payment_id, amount AS total_amount
             FROM appointment_payments
             WHERE appointment_id = :appointment_id
               AND status IN ('Captured', 'Paid')
             ORDER BY payment_id DESC
             LIMIT 1"
        );
        $paidStmt->execute([':appointment_id' => $appointmentID]);
        $paidRow = $paidStmt->fetch(PDO::FETCH_ASSOC);

        if (!$paidRow) {
            $legacyStmt = $pdo->prepare(
                "SELECT NULL::bigint AS payment_id, total_amount
                 FROM payments
                 WHERE appointment_id = :appointment_id
                   AND payment_status = 'Paid'
                 ORDER BY payment_id DESC
                 LIMIT 1"
            );
            $legacyStmt->execute([':appointment_id' => $appointmentID]);
            $paidRow = $legacyStmt->fetch(PDO::FETCH_ASSOC);
        }

        // A group booking has one payment against the lead appointment, so
        // check the whole group rather than only the row being cancelled --
        // otherwise cancelling from a member raises no refund for the group.
        if (!$paidRow && $groupId > 0) {
            $groupPay = $pdo->prepare(
                "SELECT ap.payment_id, ap.amount AS total_amount, ap.appointment_id
                 FROM appointment_payments ap
                 JOIN appointments a ON a.appointment_id = ap.appointment_id
                 WHERE a.booking_group_id = :group_id
                   AND ap.status IN ('Captured', 'Paid')
                 ORDER BY ap.payment_id DESC
                 LIMIT 1"
            );
            $groupPay->execute([':group_id' => $groupId]);
            $paidRow = $groupPay->fetch(PDO::FETCH_ASSOC);
            if ($paidRow && !empty($paidRow['appointment_id'])) {
                $appointmentID = (int)$paidRow['appointment_id'];
            }
        }

        if ($paidRow && (float)$paidRow['total_amount'] > 0) {
            $existing = $pdo->prepare(
                'SELECT refund_id FROM appointment_refunds WHERE appointment_id = :appointment_id LIMIT 1'
            );
            $existing->execute([':appointment_id' => $appointmentID]);

            if (!$existing->fetchColumn()) {
                // Phone comes from the profile; the app prompts for one at cancel
                // time when the account has none, because a refund cannot be sent
                // without a contact number.
                $phone = trim((string)($input['contactPhone'] ?? ''));
                // Mirror the app's PH rule server-side: a refund number that
                // cannot be dialled is worse than none, because the desk would
                // treat it as actionable.
                if ($phone !== '') {
                    $digits = preg_replace('/\D/', '', $phone) ?? '';
                    if (str_starts_with($digits, '63') && strlen($digits) >= 12) {
                        $digits = '0' . substr($digits, 2);
                    }
                    $validMobile = str_starts_with($digits, '09') && strlen($digits) === 11;
                    $validLandline = preg_match('/^0[2-8]/', $digits) === 1
                        && strlen($digits) >= 8 && strlen($digits) <= 10;
                    $phone = ($validMobile || $validLandline) ? $digits : '';
                }
                if ($phone === '') {
                    $phoneStmt = $pdo->prepare('SELECT phone FROM users WHERE user_id = :id LIMIT 1');
                    $phoneStmt->execute([':id' => $userID]);
                    $phone = trim((string)($phoneStmt->fetchColumn() ?: ''));
                }

                $insertRefund = $pdo->prepare(
                    "INSERT INTO appointment_refunds
                        (appointment_id, payment_id, user_id, amount, reason, status, contact_phone)
                     VALUES (:appointment_id, :payment_id, :user_id, :amount, :reason, 'Pending', :contact_phone)
                     RETURNING refund_id"
                );
                $insertRefund->execute([
                    ':appointment_id' => $appointmentID,
                    ':payment_id' => $paidRow['payment_id'] ?? null,
                    ':user_id' => $userID,
                    ':amount' => (float)$paidRow['total_amount'],
                    ':reason' => $cancelReason !== '' ? substr($cancelReason, 0, 80) : 'Customer cancelled',
                    ':contact_phone' => $phone !== '' ? $phone : null,
                ]);

                $refundRow = [
                    'refundId' => (int)$insertRefund->fetchColumn(),
                    'amount' => (float)$paidRow['total_amount'],
                    'status' => 'Pending',
                    'contactPhone' => $phone,
                ];

                // The cancellation is audited; the refund it creates was not,
                // so money owed to a customer appeared from nowhere.
                audit_log($pdo, 'REFUND_REQUESTED', 'appointment_refunds', (string)$refundRow['refundId'], null, [
                    'appointment_id' => $appointmentID,
                    'payment_id' => $paidRow['payment_id'] ?? null,
                    'amount' => round((float)$paidRow['total_amount'], 2),
                    'status' => 'Pending',
                    'reason' => $cancelReason !== '' ? substr($cancelReason, 0, 80) : 'Customer cancelled',
                ], $userID, audit_actor_customer($userID));

                // Receptionists need to see this without polling the DB.
                //
                // 'Admin'/'System', not 'Staff'/'Refund': the notifications table
                // constrains recipient_type to (User|Barber|Admin) and
                // notification_type to (Appointment|Reminder|Queue|Promotion|
                // System). This insert runs inside the cancel transaction, so
                // invalid values fail the whole cancellation, not just the notice.
                $pdo->prepare(
                    "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
                     VALUES ('Admin', 0, 'System', 'Refund requested', :message, TRUE)"
                )->execute([
                    ':message' => 'Cancelled appointment #' . $appointmentID . ' needs a refund of P'
                        . number_format((float)$paidRow['total_amount'], 2)
                        . ($phone !== '' ? ' to ' . $phone : ' (no contact number on file)') . '.',
                ]);
            }
        }

        $notifyCancelStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', 'Appointment cancelled', :message, TRUE)"
        );

        $notifyCancelStmt->execute([
            ':recipient_id' => (int)$appt['user_id'],
            ':message' => 'Your appointment on ' . (string)$appt['appointment_date'] . ' at ' . (string)$appt['start_time'] . ' was cancelled.',
        ]);

        // Reason is stored on the appointment (cancel_reason) for any screen to
        // read later, and also pushed to receptionist/admin immediately here so
        // it's visible right away without needing a UI change to surface it.
        $staffLabel = $cancelReason !== '' ? " Reason: {$cancelReason}" : ' No reason given.';
        notify_receptionist_staff(
            $pdo,
            'Appointment cancelled',
            'Customer cancelled ' . (string)$appt['appointment_date'] . ' ' . (string)$appt['start_time'] . '.' . $staffLabel
        );

        // Log appointment cancellation to audit trail
        audit_log($pdo, 'CANCEL', 'appointments', (string)$appointmentID, [
            'status' => $appt['status'],
        ], [
            'status' => 'Cancelled',
            'cancel_reason' => $cancelReason !== '' ? $cancelReason : null,
        ], (int)$appt['user_id']);

        $pdo->commit();

        json_response([
            'message' => 'Appointment cancelled',
            // Present only when money was actually taken. The app uses this to
            // tell the customer a refund is on the way, and to ask for a phone
            // number when the account has none on file.
            'refund' => $refundRow,
        ]);
    }

    if ($action === 'reschedule') {
        ensure_reschedule_count_column($pdo);

        $appointmentID = (int)($input['appointmentID'] ?? 0);
        $userID = (int)$customer['user_id'];
        $newDate = trim((string)($input['appointmentDate'] ?? ''));
        $newStartTimeRaw = trim((string)($input['startTime'] ?? ''));

        $newStartTime = normalize_time_string($newStartTimeRaw);

        if ($appointmentID <= 0 || $newDate === '' || $newStartTime === null) {
            json_response(['error' => 'Missing or invalid reschedule details'], 422);
        }

        if (!is_valid_ymd_date($newDate)) {
            json_response(['error' => 'Invalid appointmentDate format (expected YYYY-MM-DD).'], 422);
        }

        if (shop_is_closed_date($newDate)) {
            json_response(['error' => 'The shop is closed on the selected date.'], 422);
        }

        if (shop_is_break_slot_time($newStartTime, $newDate)) {
            json_response(['error' => format_time_12h($newStartTime) . ' falls on a barber break and cannot be booked.'], 422);
        }

        if (!shop_is_allowed_slot_time($newStartTime, $newDate)) {
            json_response([
                'error' => 'Selected time is outside shop hours ('
                    . format_time_range_12h(shop_open_time($newDate), shop_close_time($newDate)) . ').',
            ], 422);
        }

        if (!shop_is_future_slot($newDate, $newStartTime)) {
            json_response(['error' => 'Selected time must be at least 1 hour from now.'], 422);
        }

        if ($newDate > shop_window_end_date()) {
            json_response([
                'error' => 'Selected date is outside the booking window ('
                    . shop_booking_window_days() . ' days).',
            ], 422);
        }

        $durationMinutes = shop_appointment_duration_minutes();
        $newEndTime = shop_add_minutes_to_time($newStartTime, $durationMinutes);

        $apptStmt = $pdo->prepare(
            'SELECT appointment_id, booking_code, user_id, barber_id, appointment_date, start_time, end_time,
                    status, booking_group_id, COALESCE(reschedule_count, 0) AS reschedule_count
             FROM appointments
             WHERE appointment_id = :appointment_id
             LIMIT 1'
        );
        $apptStmt->execute([':appointment_id' => $appointmentID]);
        $appt = $apptStmt->fetch();
        if (!$appt) {
            json_response(['error' => 'Appointment not found'], 404);
        }

        if ((int)$appt['user_id'] !== $userID) {
            json_response(['error' => 'You can only reschedule your own appointments'], 403);
        }

        $paidCheckStmt = $pdo->prepare(
            "SELECT COUNT(*)
             FROM appointment_payments
             WHERE appointment_id = :appointment_id
               AND status = 'Captured'"
        );
        $paidCheckStmt->execute([':appointment_id' => $appointmentID]);
        $paymentState = (int)$paidCheckStmt->fetchColumn() > 0 ? 'Paid' : 'Unpaid';

        $reschedulePolicy = can_customer_reschedule_appointment($appt, $paymentState);
        if (!$reschedulePolicy['allowed']) {
            json_response(['error' => $reschedulePolicy['reason']], 409);
        }

        $oldDate = (string)$appt['appointment_date'];
        $oldStart = (string)$appt['start_time'];
        if ($oldDate === $newDate && $oldStart === $newStartTime) {
            json_response(['error' => 'Please choose a different date or time.'], 422);
        }

        if (paid_slot_conflict_exists($pdo, (int)$appt['barber_id'], $newDate, $newStartTime, [$appointmentID])) {
            json_response(['error' => 'Selected time slot is already booked. Choose another time.'], 409);
        }

        $overlapStmt = $pdo->prepare(
            "SELECT COUNT(*)
             FROM appointments
             WHERE barber_id = :barber_id
               AND appointment_date = :appointment_date
               AND appointment_id <> :appointment_id
               AND status IN ('PendingPayment', 'Scheduled', 'CheckedIn', 'InProgress')
               AND (start_time < :end_time AND end_time > :start_time)"
        );
        $overlapStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':appointment_date' => $newDate,
            ':appointment_id' => $appointmentID,
            ':start_time' => $newStartTime,
            ':end_time' => $newEndTime,
        ]);
        if ((int)$overlapStmt->fetchColumn() > 0) {
            json_response(['error' => 'Selected time overlaps with another appointment for this barber.'], 409);
        }

        $slotCheckStmt = $pdo->prepare(
            "SELECT slot_id
             FROM time_slots
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time
               AND status = 'Available'
             LIMIT 1"
        );
        $slotCheckStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => $newDate,
            ':slot_time' => $newStartTime,
        ]);
        if (!$slotCheckStmt->fetch()) {
            json_response(['error' => 'Target slot is not available anymore.'], 409);
        }

        $pdo->beginTransaction();

        $releaseOldSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Available'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $releaseOldSlotStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => $oldDate,
            ':slot_time' => $oldStart,
        ]);

        $bookNewSlotStmt = $pdo->prepare(
            "UPDATE time_slots
             SET status = 'Booked'
             WHERE barber_id = :barber_id
               AND slot_date = :slot_date
               AND slot_time = :slot_time"
        );
        $bookNewSlotStmt->execute([
            ':barber_id' => (int)$appt['barber_id'],
            ':slot_date' => $newDate,
            ':slot_time' => $newStartTime,
        ]);

        $updateApptStmt = $pdo->prepare(
            "UPDATE appointments
             SET appointment_date = :appointment_date,
                 start_time = :start_time,
                 end_time = :end_time,
                 status = 'Scheduled',
                 reschedule_count = COALESCE(reschedule_count, 0) + 1,
                 updated_at = CURRENT_TIMESTAMP
             WHERE appointment_id = :appointment_id"
        );

        // A group booking is N back-to-back appointments sharing one
        // booking_group_id. Updating only the row the customer tapped left the
        // other members at the old time, splitting the group across the day --
        // which is why a 4-person booking rendered as "7:00 PM - 2:00 PM".
        // Move the whole group, keeping members consecutive from the new start.
        $rescheduleGroupId = (int)($appt['booking_group_id'] ?? 0);
        if ($rescheduleGroupId > 0) {
            $membersStmt = $pdo->prepare(
                "SELECT appointment_id, start_time, end_time
                 FROM appointments
                 WHERE booking_group_id = :group_id
                   AND status NOT IN ('Cancelled', 'NoShow', 'Completed')
                 ORDER BY start_time, appointment_id"
            );
            $membersStmt->execute([':group_id' => $rescheduleGroupId]);
            $members = $membersStmt->fetchAll(PDO::FETCH_ASSOC);

            // Validate the FULL block before moving anything: every member's
            // slot must be a real bookable time and still free, or the group
            // ends up half-moved and running past closing.
            $cursor = $newStartTime;
            $planned = [];
            foreach ($members as $member) {
                // Each member keeps its own length; fall back to the requested
                // duration if the stored range is unusable.
                $memberStart = strtotime('1970-01-01 ' . (string)$member['start_time'] . ' UTC');
                $memberFinish = strtotime('1970-01-01 ' . (string)$member['end_time'] . ' UTC');
                $memberMinutes = ($memberStart !== false && $memberFinish !== false
                    && $memberFinish > $memberStart)
                    ? (int)round(($memberFinish - $memberStart) / 60)
                    : $durationMinutes;
                $memberEnd = shop_add_minutes_to_time($cursor, $memberMinutes);

                if (!shop_is_allowed_slot_time($cursor, $newDate)
                    || shop_is_break_slot_time($cursor, $newDate)) {
                    $pdo->rollBack();
                    json_response([
                        'error' => 'The group needs ' . count($members)
                            . ' back-to-back slots. ' . format_time_12h($newStartTime)
                            . ' does not leave enough open time that day.',
                    ], 422);
                }

                if (paid_slot_conflict_exists(
                    $pdo,
                    (int)$appt['barber_id'],
                    $newDate,
                    $cursor,
                    array_column($members, 'appointment_id')
                )) {
                    $pdo->rollBack();
                    json_response([
                        'error' => format_time_12h($cursor)
                            . ' is already booked, so the group cannot start at '
                            . format_time_12h($newStartTime) . '.',
                    ], 409);
                }

                $planned[] = [
                    'appointment_id' => (int)$member['appointment_id'],
                    'start' => $cursor,
                    'end' => $memberEnd,
                ];
                $cursor = $memberEnd;
            }

            foreach ($planned as $slot) {
                release_slots_for_appointment($pdo, $slot['appointment_id']);
                $updateApptStmt->execute([
                    ':appointment_date' => $newDate,
                    ':start_time' => $slot['start'],
                    ':end_time' => $slot['end'],
                    ':appointment_id' => $slot['appointment_id'],
                ]);
            }
        } else {
            $updateApptStmt->execute([
                ':appointment_date' => $newDate,
                ':start_time' => $newStartTime,
                ':end_time' => $newEndTime,
                ':appointment_id' => $appointmentID,
            ]);
        }

        $notifyStmt = $pdo->prepare(
            "INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
             VALUES ('User', :recipient_id, 'Appointment', :title, :message, TRUE)"
        );
        $notifyStmt->execute([
            ':recipient_id' => (int)$appt['user_id'],
            ':title' => 'Appointment rescheduled',
            ':message' => 'Booking ' . (string)$appt['booking_code'] . ' was moved to ' . $newDate . ' at ' . $newStartTime . '.',
        ]);

        // Moving a paid slot was unaudited, so there was no record of who
        // moved a booking, from when, or how many moves it had used.
        audit_log($pdo, 'RESCHEDULE_APPOINTMENT', 'appointments', (string)$appointmentID, [
            'appointment_date' => (string)$appt['appointment_date'],
            'start_time' => (string)$appt['start_time'],
            'end_time' => (string)$appt['end_time'],
            'reschedule_count' => (int)$appt['reschedule_count'],
        ], [
            'appointment_date' => $newDate,
            'start_time' => $newStartTime,
            'end_time' => $newEndTime,
            'reschedule_count' => (int)$appt['reschedule_count'] + 1,
        ], (int)$appt['user_id'], audit_actor_customer((int)$appt['user_id']));

        $pdo->commit();

        $remaining = max(0, shop_max_reschedules_per_appointment() - ((int)$appt['reschedule_count'] + 1));

        json_response([
            'message' => 'Appointment rescheduled successfully.',
            'appointmentID' => $appointmentID,
            'appointmentDate' => $newDate,
            'startTime' => $newStartTime,
            'endTime' => $newEndTime,
            'status' => 'Scheduled',
            'rescheduleCount' => (int)$appt['reschedule_count'] + 1,
            'reschedulesRemaining' => $remaining,
        ]);
    }

    if ($action === 'listByBarber') {
        $barberID = (int)($input['barberID'] ?? 0);
        if ($barberID <= 0) {
            json_response(['error' => 'Invalid barberID'], 422);
        }

        $stmt = $pdo->prepare(
            'SELECT a.appointment_id, a.booking_code, a.booking_group_id, a.group_member_name, a.group_sequence,
                    a.appointment_date, a.start_time, a.end_time, a.status,
                    u.user_id AS customer_id, u.full_name AS customer_name
             FROM appointments a
             JOIN users u ON a.user_id = u.user_id
             WHERE a.barber_id = :barber_id
             ORDER BY a.appointment_date DESC, a.start_time DESC'
        );
        $stmt->execute([':barber_id' => $barberID]);
        $appointments = $stmt->fetchAll();

        if (count($appointments) === 0) {
            json_response(['appointments' => []]);
        }

        $appointmentIds = array_map(fn($row) => (int)$row['appointment_id'], $appointments);
        $inClause = implode(',', array_fill(0, count($appointmentIds), '?'));

        $detailStmt = $pdo->prepare(
            "SELECT ad.appointment_id, ad.special_instructions,
                    hs.style_name AS hairstyle_name,
                    s.service_name,
                    COALESCE(ad.customer_front_url, hv.front_view_url) AS front_view_url,
                    COALESCE(ad.customer_left_url, hv.side_view_url) AS side_view_url,
                    COALESCE(ad.customer_right_url, hv.back_view_url) AS back_view_url,
                    hv.clipper_sizes, hv.barber_instructions, hv.styling_products, hv.estimated_minutes
             FROM appointment_details ad
             JOIN services s ON ad.service_id = s.service_id
             LEFT JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
             LEFT JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE ad.appointment_id IN ($inClause)"
        );
        $detailStmt->execute($appointmentIds);
        $detailRows = $detailStmt->fetchAll();

        // Customers can attach special instructions per service at booking time
        // (booking.php 'create'/'createGroup'), but no barber-facing endpoint ever
        // read them back — the barber performing the service never saw what the
        // customer asked for. A single appointment can have more than one service
        // row; concatenate any non-empty instructions across all of them.
        $detailMap = [];
        foreach ($detailRows as $row) {
            $aid = (int)$row['appointment_id'];
            if (!isset($detailMap[$aid])) {
                $detailMap[$aid] = [
                    'serviceName' => $row['service_name'],
                    'hairstyleName' => $row['hairstyle_name'],
                    'frontViewUrl' => $row['front_view_url'],
                    'sideViewUrl' => $row['side_view_url'],
                    'backViewUrl' => $row['back_view_url'],
                    'clipperSizes' => $row['clipper_sizes'],
                    'barberInstructions' => $row['barber_instructions'],
                    'stylingProducts' => $row['styling_products'],
                    'estimatedMinutes' => $row['estimated_minutes'] !== null ? (int)$row['estimated_minutes'] : null,
                    'specialInstructions' => [],
                ];
            }
            $instruction = trim((string)($row['special_instructions'] ?? ''));
            if ($instruction !== '') {
                $detailMap[$aid]['specialInstructions'][] = $instruction;
            }
        }

        $appointments = array_map(function ($row) use ($detailMap) {
            $aid = (int)$row['appointment_id'];
            $details = $detailMap[$aid] ?? [];
            return [
                'appointmentID' => $aid,
                'bookingCode' => $row['booking_code'],
                'bookingGroupID' => $row['booking_group_id'] !== null ? (int)$row['booking_group_id'] : null,
                'groupMemberName' => $row['group_member_name'] !== null ? (string)$row['group_member_name'] : null,
                'groupSequence' => $row['group_sequence'] !== null ? (int)$row['group_sequence'] : null,
                'appointmentDate' => $row['appointment_date'],
                'startTime' => $row['start_time'],
                'endTime' => $row['end_time'],
                'status' => $row['status'],
                'customerID' => (int)$row['customer_id'],
                'customerName' => $row['customer_name'],
                'serviceName' => $details['serviceName'] ?? null,
                'hairstyleName' => $details['hairstyleName'] ?? null,
                'frontViewUrl' => $details['frontViewUrl'] ?? null,
                'sideViewUrl' => $details['sideViewUrl'] ?? null,
                'backViewUrl' => $details['backViewUrl'] ?? null,
                'clipperSizes' => $details['clipperSizes'] ?? null,
                'barberInstructions' => $details['barberInstructions'] ?? null,
                'stylingProducts' => $details['stylingProducts'] ?? null,
                'estimatedMinutes' => $details['estimatedMinutes'] ?? null,
                'specialInstructions' => !empty($details['specialInstructions'])
                    ? implode(' / ', $details['specialInstructions'])
                    : null,
            ];
        }, $appointments);

        json_response(['appointments' => collapse_barber_dashboard_appointments($pdo, $appointments, $barberID)]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response([
        'error' => 'Server error',
        'details' => $e->getMessage(),
        'line' => $e->getLine(),
        'file' => basename((string)$e->getFile()),
    ], 500);
}
