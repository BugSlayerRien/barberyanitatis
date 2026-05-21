-- Group bookings (up to 5 people, consecutive slots, one payment unit)
-- Run once on Postgres / Supabase SQL editor.

CREATE TABLE IF NOT EXISTS appointment_groups (
    group_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL,
    primary_barber_id BIGINT NOT NULL,
    people_count INT NOT NULL CHECK (people_count >= 1 AND people_count <= 5),
    slot_date DATE NOT NULL,
    first_slot_time TIME NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'PendingPayment',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT fk_appointment_groups_user FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_appointment_groups_barber FOREIGN KEY (primary_barber_id) REFERENCES barbers(barber_id)
);

ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS booking_group_id BIGINT;

ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS group_member_name TEXT;

ALTER TABLE appointments
    ADD COLUMN IF NOT EXISTS group_sequence INT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_appointments_booking_group'
    ) THEN
        ALTER TABLE appointments
            ADD CONSTRAINT fk_appointments_booking_group
            FOREIGN KEY (booking_group_id) REFERENCES appointment_groups(group_id) ON DELETE SET NULL;
    END IF;
END $$;

ALTER TABLE appointment_payment_intents
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE appointment_payment_intents
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE appointment_details
    ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
    ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
    ADD COLUMN IF NOT EXISTS customer_right_url TEXT;
