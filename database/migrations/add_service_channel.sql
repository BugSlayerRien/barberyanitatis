-- Regular (kiosk) vs exclusive (appointment) service pricing channels.
ALTER TABLE services
  ADD COLUMN IF NOT EXISTS service_channel TEXT NOT NULL DEFAULT 'appointment';

UPDATE services
SET service_channel = CASE
    WHEN LOWER(category) = 'haircut' AND base_price <= 150 THEN 'walk_in'
    ELSE COALESCE(NULLIF(TRIM(service_channel), ''), 'appointment')
END
WHERE service_channel IS NULL OR TRIM(service_channel) = '';

ALTER TABLE services DROP CONSTRAINT IF EXISTS services_service_channel_check;
ALTER TABLE services ADD CONSTRAINT services_service_channel_check
  CHECK (service_channel IN ('walk_in', 'appointment'));

-- Default exclusive haircut price (admin can edit in portal).
UPDATE services
SET base_price = 500, service_channel = 'appointment'
WHERE LOWER(category) = 'haircut'
  AND service_channel = 'appointment'
  AND base_price < 200;

UPDATE services
SET base_price = 100, service_channel = 'walk_in'
WHERE LOWER(category) = 'haircut'
  AND service_channel = 'walk_in';
