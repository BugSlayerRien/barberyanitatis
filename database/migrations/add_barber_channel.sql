-- Split barbers between walk-in kiosk and appointment booking.
-- Run once on Supabase / local Postgres, then assign each barber to ONE channel.

ALTER TABLE barbers
  ADD COLUMN IF NOT EXISTS barber_channel TEXT NOT NULL DEFAULT 'appointment';

UPDATE barbers
SET barber_channel = 'appointment'
WHERE barber_channel IS NULL OR TRIM(barber_channel) = '';

ALTER TABLE barbers DROP CONSTRAINT IF EXISTS barbers_barber_channel_check;
ALTER TABLE barbers ADD CONSTRAINT barbers_barber_channel_check
  CHECK (barber_channel IN ('walk_in', 'appointment'));

-- Example: mark walk-in-only barbers (adjust IDs for your shop)
-- UPDATE barbers SET barber_channel = 'walk_in' WHERE barber_id IN (2, 3);
