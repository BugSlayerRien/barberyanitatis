<?php
// Idempotent PostgreSQL trigger: notify customer + barber when appointment_payments is captured/paid.

declare(strict_types=1);

function ensure_appointment_payment_notify_trigger(PDO $pdo): void
{
    $pdo->exec(
        <<<'SQL'
CREATE OR REPLACE FUNCTION trg_fn_notify_on_appointment_payment()
RETURNS TRIGGER AS $$
DECLARE
  uid BIGINT;
  bid BIGINT;
  bcode TEXT;
  st TEXT;
BEGIN
  st := lower(trim(NEW.status::text));
  IF st NOT IN ('captured', 'paid', 'succeeded') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND lower(trim(OLD.status::text)) IN ('captured', 'paid', 'succeeded') THEN
    RETURN NEW;
  END IF;

  SELECT a.user_id, a.barber_id, a.booking_code
    INTO uid, bid, bcode
    FROM appointments a
   WHERE a.appointment_id = NEW.appointment_id
   LIMIT 1;

  IF uid IS NULL OR bid IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO notifications (recipient_type, recipient_id, notification_type, title, message, is_sent)
  VALUES
    ('User', uid, 'Appointment', 'Payment confirmed',
     'Your payment for booking ' || COALESCE(bcode, '') || ' was received. Your appointment is confirmed.',
     TRUE),
    ('Barber', bid, 'Appointment', 'Payment received',
     'Booking ' || COALESCE(bcode, '') || ' has been paid and is confirmed.',
     TRUE);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SQL
    );

    $pdo->exec('DROP TRIGGER IF EXISTS trg_notify_on_appointment_payment ON appointment_payments');
    $pdo->exec(
        <<<'SQL'
CREATE TRIGGER trg_notify_on_appointment_payment
  AFTER INSERT OR UPDATE OF status ON appointment_payments
  FOR EACH ROW
  EXECUTE PROCEDURE trg_fn_notify_on_appointment_payment()
SQL
    );
}
