-- Track customer self-service reschedules per appointment.

ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS reschedule_count INT NOT NULL DEFAULT 0;
