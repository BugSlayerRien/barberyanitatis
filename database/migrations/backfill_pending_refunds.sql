-- Backfill refund rows for bookings cancelled while the refund code was looking
-- in the wrong table.
--
-- booking.php 'cancel' queried `payments` for payment_status = 'Paid'. The app
-- records booking payments in `appointment_payments` with status 'Captured', so
-- no app booking ever matched and every paid cancellation raised no refund.
-- Fixed forward in booking.php; this recovers the ones already missed.
--
-- SCOPED TO THE LAST 14 DAYS on purpose. ~40 historical rows match, most of them
-- old test bookings; loading all of them into the receptionist's Pending queue
-- would bury the real ones. Widen the interval to settle older cancellations.
--
-- One row per booking group: a group booking carries a single payment against
-- its lead appointment, so DISTINCT ON stops four members raising four refunds
-- for one payment.
--
-- Idempotent: skips anything that already has a refund row.

BEGIN;

INSERT INTO appointment_refunds
    (appointment_id, payment_id, user_id, amount, reason, status, contact_phone)
SELECT DISTINCT ON (COALESCE(a.booking_group_id::text, a.appointment_id::text))
       a.appointment_id,
       ap.payment_id,
       a.user_id,
       ap.amount,
       COALESCE(NULLIF(TRIM(a.cancel_reason), ''), 'Customer cancelled'),
       'Pending',
       NULLIF(TRIM(u.phone), '')
  FROM appointments a
  JOIN appointment_payments ap ON ap.appointment_id = a.appointment_id
  LEFT JOIN users u ON u.user_id = a.user_id
 WHERE a.status = 'Cancelled'
   AND ap.status IN ('Captured', 'Paid')
   AND a.updated_at >= NOW() - INTERVAL '14 days'
   AND NOT EXISTS (
       SELECT 1 FROM appointment_refunds r WHERE r.appointment_id = a.appointment_id
   )
 ORDER BY COALESCE(a.booking_group_id::text, a.appointment_id::text), ap.payment_id DESC;

COMMIT;

-- Verify:
--   SELECT status, COUNT(*), SUM(amount) FROM appointment_refunds GROUP BY status;
