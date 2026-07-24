-- Operating Schedule Management: weekly hours, break windows, closed dates.
-- Safe to run repeatedly (IF NOT EXISTS + ON CONFLICT seeds).
-- Defaults match the previously hardcoded behavior in api/shop_schedule.php:
-- open every day 09:00-20:00, lunch break 12:00-13:00, 60-min slots.

BEGIN;

CREATE TABLE IF NOT EXISTS shop_weekly_hours (
  day_of_week INT PRIMARY KEY CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sunday .. 6=Saturday
  is_closed BOOLEAN NOT NULL DEFAULT FALSE,
  open_time TIME NOT NULL DEFAULT '09:00',
  close_time TIME NOT NULL DEFAULT '20:00',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ck_weekly_hours_order CHECK (is_closed OR close_time > open_time)
);

CREATE TABLE IF NOT EXISTS shop_break_windows (
  break_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  day_of_week INT CHECK (day_of_week BETWEEN 0 AND 6), -- NULL = applies every day
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  label VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ck_break_window_order CHECK (end_time > start_time)
);

CREATE TABLE IF NOT EXISTS shop_closed_dates (
  closed_date DATE PRIMARY KEY,
  reason VARCHAR(160),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed weekly hours (legacy parity: open 7 days, 09:00-20:00)
INSERT INTO shop_weekly_hours (day_of_week, is_closed, open_time, close_time)
SELECT d, FALSE, '09:00'::time, '20:00'::time
FROM generate_series(0, 6) AS d
ON CONFLICT (day_of_week) DO NOTHING;

-- Seed default lunch break (legacy parity: hour 12 excluded daily)
INSERT INTO shop_break_windows (day_of_week, start_time, end_time, label)
SELECT NULL, '12:00'::time, '13:00'::time, 'Lunch break'
WHERE NOT EXISTS (SELECT 1 FROM shop_break_windows);

-- Slot/duration knobs live in system_settings
INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_editable, updated_at)
VALUES
  ('shop_slot_duration_minutes', '60', 'Number', 'operations', 'Calendar slot length in minutes', TRUE, NOW()),
  ('shop_appointment_duration_minutes', '60', 'Number', 'operations', 'Appointment service length in minutes', TRUE, NOW()),
  ('shop_walkin_duration_minutes', '35', 'Number', 'operations', 'Walk-in service length in minutes', TRUE, NOW()),
  ('shop_timezone', 'Asia/Manila', 'String', 'operations', 'Shop timezone identifier', TRUE, NOW())
ON CONFLICT (setting_key) DO NOTHING;

COMMIT;
