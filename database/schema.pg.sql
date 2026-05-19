-- ====================================================================
-- BARBERSHOP MANAGEMENT SYSTEM WITH AI HAIRSTYLE RECOMMENDATION
-- PostgreSQL / Supabase-ready schema
-- ====================================================================

BEGIN;

-- =========================
-- 1. USER MANAGEMENT
-- =========================

CREATE TABLE IF NOT EXISTS users (
  user_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email VARCHAR(150) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(150) NOT NULL,
  phone VARCHAR(20),
  profile_image VARCHAR(255),
  gender TEXT NOT NULL DEFAULT 'Male' CHECK (gender IN ('Male', 'Female', 'Other')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_users_email_active ON users (email, is_active);

CREATE TABLE IF NOT EXISTS user_profiles (
  profile_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL UNIQUE,
  face_shape VARCHAR(50),
  hair_texture TEXT CHECK (hair_texture IN ('Straight', 'Wavy', 'Curly', 'Coily')),
  hair_density TEXT CHECK (hair_density IN ('Thin', 'Medium', 'Thick')),
  hair_length TEXT CHECK (hair_length IN ('Short', 'Medium', 'Long')),
  last_scan_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_user_profiles_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_profiles_user_face_shape ON user_profiles (user_id, face_shape);

CREATE TABLE IF NOT EXISTS staff_users (
  staff_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email VARCHAR(150) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name VARCHAR(150) NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('Admin', 'Receptionist')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_staff_users_role_active ON staff_users (role, is_active);

-- =========================
-- 2. BARBER MANAGEMENT
-- =========================

CREATE TABLE IF NOT EXISTS barbers (
  barber_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barber_code VARCHAR(10) UNIQUE NOT NULL,
  full_name VARCHAR(150) NOT NULL,
  email VARCHAR(150) UNIQUE,
  password_hash VARCHAR(255),
  profile_image VARCHAR(255),
  specialty VARCHAR(100),
  years_experience INT,
  bio TEXT,
  rating NUMERIC(3,2) NOT NULL DEFAULT 5.00,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_barbers_code_active ON barbers (barber_code, is_active);

-- =========================
-- 3. HAIRSTYLE CATALOG (AI DATASET)
-- =========================

CREATE TABLE IF NOT EXISTS hairstyles (
  hairstyle_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  style_code VARCHAR(20) UNIQUE NOT NULL,
  style_name VARCHAR(100) NOT NULL,
  description TEXT,
  gender TEXT NOT NULL DEFAULT 'Unisex' CHECK (gender IN ('Male', 'Female', 'Unisex')),
  difficulty TEXT NOT NULL DEFAULT 'Medium' CHECK (difficulty IN ('Easy', 'Medium', 'Hard')),
  maintenance TEXT NOT NULL DEFAULT 'Medium' CHECK (maintenance IN ('Low', 'Medium', 'High')),
  popularity_score INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hairstyles_gender_active ON hairstyles (gender, is_active);

CREATE TABLE IF NOT EXISTS hairstyle_variants (
  variant_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hairstyle_id BIGINT NOT NULL,
  face_shape VARCHAR(50) NOT NULL,
  hair_texture TEXT NOT NULL CHECK (hair_texture IN ('Straight', 'Wavy', 'Curly', 'Coily')),
  front_view_url VARCHAR(255) NOT NULL,
  side_view_url VARCHAR(255),
  back_view_url VARCHAR(255),
  barber_instructions TEXT NOT NULL,
  clipper_sizes VARCHAR(100),
  styling_products TEXT,
  estimated_minutes INT NOT NULL DEFAULT 30,
  confidence_score NUMERIC(4,3) NOT NULL DEFAULT 0.800,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_hairstyle_variants_hairstyle FOREIGN KEY (hairstyle_id) REFERENCES hairstyles(hairstyle_id) ON DELETE CASCADE,
  CONSTRAINT uq_hairstyle_variants UNIQUE (hairstyle_id, face_shape, hair_texture)
);

CREATE INDEX IF NOT EXISTS idx_hairstyle_variants_face_hair ON hairstyle_variants (face_shape, hair_texture);

-- =========================
-- 4. SERVICES & PRICING
-- =========================

CREATE TABLE IF NOT EXISTS services (
  service_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  service_code VARCHAR(20) UNIQUE NOT NULL,
  service_name VARCHAR(100) NOT NULL,
  description TEXT,
  base_duration INT NOT NULL,
  base_price NUMERIC(10,2) NOT NULL,
  category TEXT NOT NULL DEFAULT 'Haircut' CHECK (category IN ('Haircut', 'Styling', 'Beard', 'Treatment')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_category_active ON services (category, is_active);

-- =========================
-- 5. APPOINTMENTS (MOBILE APP)
-- =========================

CREATE TABLE IF NOT EXISTS appointments (
  appointment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_code VARCHAR(20) UNIQUE NOT NULL,
  user_id BIGINT NOT NULL,
  barber_id BIGINT NOT NULL,
  appointment_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status TEXT NOT NULL DEFAULT 'Scheduled' CHECK (status IN ('Scheduled', 'CheckedIn', 'InProgress', 'Completed', 'Cancelled', 'NoShow')),
  checkin_time TIMESTAMPTZ,
  completion_time TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_appointments_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT fk_appointments_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id)
);

CREATE INDEX IF NOT EXISTS idx_appointments_date_status ON appointments (appointment_date, status);
CREATE INDEX IF NOT EXISTS idx_appointments_user_dates ON appointments (user_id, appointment_date DESC);

CREATE TABLE IF NOT EXISTS appointment_details (
  detail_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  appointment_id BIGINT NOT NULL,
  service_id BIGINT NOT NULL,
  variant_id BIGINT NOT NULL,
  selected_view TEXT NOT NULL DEFAULT 'Front' CHECK (selected_view IN ('Front', 'Side', 'Back')),
  special_instructions TEXT,
  final_price NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_appointment_details_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE CASCADE,
  CONSTRAINT fk_appointment_details_service FOREIGN KEY (service_id) REFERENCES services(service_id),
  CONSTRAINT fk_appointment_details_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id),
  CONSTRAINT uq_appointment_service UNIQUE (appointment_id, service_id)
);

-- =========================
-- 6. TIME SLOT MANAGEMENT
-- =========================

CREATE TABLE IF NOT EXISTS time_slots (
  slot_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barber_id BIGINT NOT NULL,
  slot_date DATE NOT NULL,
  slot_time TIME NOT NULL,
  duration INT NOT NULL DEFAULT 35,
  status TEXT NOT NULL DEFAULT 'Available' CHECK (status IN ('Available', 'Booked', 'InProgress', 'Completed', 'Cancelled')),
  appointment_id BIGINT,
  expected_start TIMESTAMPTZ,
  expected_end TIMESTAMPTZ,
  actual_start TIMESTAMPTZ,
  actual_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_time_slots_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id),
  CONSTRAINT fk_time_slots_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
  CONSTRAINT uq_barber_slot UNIQUE (barber_id, slot_date, slot_time)
);

CREATE INDEX IF NOT EXISTS idx_time_slots_date_status ON time_slots (slot_date, status);

-- =========================
-- 7. WALK-IN QUEUE
-- =========================

CREATE TABLE IF NOT EXISTS walkin_queue (
  queue_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  queue_number VARCHAR(20) NOT NULL,
  barber_id BIGINT,
  estimated_start TIMESTAMPTZ,
  actual_start TIMESTAMPTZ,
  actual_end TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'Waiting' CHECK (status IN ('Waiting', 'Assigned', 'InProgress', 'Completed', 'Cancelled')),
  wait_time_minutes INT,
  people_count INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_walkin_queue_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id)
);

CREATE INDEX IF NOT EXISTS idx_walkin_queue_status_date ON walkin_queue (status, created_at);
CREATE INDEX IF NOT EXISTS idx_walkin_queue_barber_status ON walkin_queue (barber_id, status);

CREATE TABLE IF NOT EXISTS walkin_service_details (
  detail_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  queue_id BIGINT NOT NULL,
  service_id BIGINT NOT NULL,
  variant_id BIGINT NOT NULL,
  selected_view TEXT NOT NULL DEFAULT 'Front' CHECK (selected_view IN ('Front', 'Side', 'Back')),
  special_instructions TEXT,
  final_price NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_walkin_service_queue FOREIGN KEY (queue_id) REFERENCES walkin_queue(queue_id) ON DELETE CASCADE,
  CONSTRAINT fk_walkin_service_service FOREIGN KEY (service_id) REFERENCES services(service_id),
  CONSTRAINT fk_walkin_service_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id)
);

-- =========================
-- 8. PAYMENTS
-- =========================

CREATE TABLE IF NOT EXISTS payments (
  payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_ref VARCHAR(50) UNIQUE NOT NULL,
  appointment_id BIGINT,
  queue_id BIGINT,
  amount NUMERIC(10,2) NOT NULL,
  discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  tax_amount NUMERIC(10,2) NOT NULL DEFAULT 0.00,
  total_amount NUMERIC(10,2) NOT NULL,
  payment_method TEXT NOT NULL DEFAULT 'Cash' CHECK (payment_method IN ('Cash', 'Card', 'Digital')),
  payment_status TEXT NOT NULL DEFAULT 'Pending' CHECK (payment_status IN ('Pending', 'Paid', 'Refunded', 'Failed')),
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_payments_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
  CONSTRAINT fk_payments_queue FOREIGN KEY (queue_id) REFERENCES walkin_queue(queue_id),
  CONSTRAINT ck_payment_target CHECK (appointment_id IS NOT NULL OR queue_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_payments_status_date ON payments (payment_status, created_at);

-- =========================
-- 9. FEEDBACK & RATINGS
-- =========================

CREATE TABLE IF NOT EXISTS feedback (
  feedback_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  appointment_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  barber_id BIGINT NOT NULL,
  overall_rating INT,
  barber_rating INT,
  service_rating INT,
  wait_time_rating INT,
  comment TEXT,
  would_recommend BOOLEAN,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_feedback_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
  CONSTRAINT fk_feedback_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT fk_feedback_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id)
);

CREATE INDEX IF NOT EXISTS idx_feedback_barber_rating ON feedback (barber_id, created_at DESC);

-- =========================
-- 10. NOTIFICATIONS
-- =========================

CREATE TABLE IF NOT EXISTS notifications (
  notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  recipient_type TEXT NOT NULL CHECK (recipient_type IN ('User', 'Barber', 'Admin')),
  recipient_id BIGINT NOT NULL,
  notification_type TEXT NOT NULL CHECK (notification_type IN ('Appointment', 'Reminder', 'Queue', 'Promotion', 'System')),
  title VARCHAR(200) NOT NULL,
  message TEXT NOT NULL,
  data TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  is_sent BOOLEAN NOT NULL DEFAULT FALSE,
  scheduled_send TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread ON notifications (recipient_type, recipient_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_scheduled ON notifications (scheduled_send, is_sent);

-- =========================
-- 11. SYSTEM SETTINGS
-- =========================

CREATE TABLE IF NOT EXISTS system_settings (
  setting_key VARCHAR(100) PRIMARY KEY,
  setting_value TEXT,
  setting_type TEXT NOT NULL DEFAULT 'String' CHECK (setting_type IN ('String', 'Number', 'Boolean', 'JSON', 'Array')),
  category VARCHAR(50),
  description TEXT,
  is_editable BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================
-- 12. FAVORITES & HISTORY
-- =========================

CREATE TABLE IF NOT EXISTS user_favorites (
  favorite_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  variant_id BIGINT,
  barber_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_user_favorites_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_favorites_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id),
  CONSTRAINT fk_user_favorites_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id),
  CONSTRAINT uq_user_favorite UNIQUE (user_id, variant_id, barber_id)
);

CREATE TABLE IF NOT EXISTS user_history (
  history_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT NOT NULL,
  appointment_id BIGINT NOT NULL,
  variant_id BIGINT NOT NULL,
  service_date DATE NOT NULL,
  notes TEXT,
  after_photo_url VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_user_history_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_history_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id),
  CONSTRAINT fk_user_history_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id)
);

CREATE INDEX IF NOT EXISTS idx_user_history_user_date ON user_history (user_id, service_date DESC);

CREATE TABLE IF NOT EXISTS user_style_preferences (
  user_id BIGINT PRIMARY KEY,
  preferred_variant_id BIGINT,
  preferred_style_name VARCHAR(120),
  last_face_shape VARCHAR(50),
  last_hair_texture TEXT,
  last_hair_density TEXT,
  last_hair_length TEXT,
  selection_count INT NOT NULL DEFAULT 0,
  last_selected_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_user_style_preferences_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_style_preferences_variant FOREIGN KEY (preferred_variant_id) REFERENCES hairstyle_variants(variant_id)
);

CREATE TABLE IF NOT EXISTS ai_recommendation_events (
  event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id BIGINT,
  scan_session_id VARCHAR(80),
  event_type VARCHAR(40) NOT NULL,
  variant_id BIGINT,
  style_name VARCHAR(120),
  service_id BIGINT,
  estimated_minutes INT,
  appointment_id BIGINT,
  face_shape VARCHAR(50),
  hair_texture TEXT,
  hair_density TEXT,
  hair_length TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_ai_event_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_event_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_event_service FOREIGN KEY (service_id) REFERENCES services(service_id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_event_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_events_type_date ON ai_recommendation_events (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_events_scan_session ON ai_recommendation_events (scan_session_id);
CREATE INDEX IF NOT EXISTS idx_ai_events_user_variant ON ai_recommendation_events (user_id, variant_id);

-- =========================
-- 13. ANALYTICS & REPORTS
-- =========================

CREATE TABLE IF NOT EXISTS daily_analytics (
  analytics_date DATE PRIMARY KEY,
  total_appointments INT NOT NULL DEFAULT 0,
  completed_appointments INT NOT NULL DEFAULT 0,
  total_walkins INT NOT NULL DEFAULT 0,
  completed_walkins INT NOT NULL DEFAULT 0,
  total_revenue NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  avg_service_time INT NOT NULL DEFAULT 0,
  peak_hour VARCHAR(5),
  most_popular_service_id BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_daily_analytics_service FOREIGN KEY (most_popular_service_id) REFERENCES services(service_id)
);

CREATE TABLE IF NOT EXISTS barber_performance (
  performance_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  barber_id BIGINT NOT NULL,
  period_date DATE NOT NULL,
  period_type TEXT NOT NULL DEFAULT 'Monthly' CHECK (period_type IN ('Daily', 'Weekly', 'Monthly')),
  total_services INT NOT NULL DEFAULT 0,
  total_revenue NUMERIC(12,2) NOT NULL DEFAULT 0.00,
  avg_rating NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  client_retention_rate NUMERIC(5,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_barber_performance_barber FOREIGN KEY (barber_id) REFERENCES barbers(barber_id),
  CONSTRAINT uq_barber_period UNIQUE (barber_id, period_date, period_type)
);

-- =========================
-- 14. AUDIT LOGS
-- =========================

CREATE TABLE IF NOT EXISTS audit_logs (
  log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  action_type VARCHAR(50) NOT NULL,
  table_name VARCHAR(50),
  record_id VARCHAR(100),
  old_values TEXT,
  new_values TEXT,
  user_id BIGINT,
  ip_address VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_action_date ON audit_logs (action_type, created_at DESC);

-- =========================
-- 15. QUEUE DISPLAY VIEW
-- =========================

CREATE OR REPLACE VIEW queue_display AS
SELECT
  'Appointment'::TEXT AS service_type,
  a.booking_code AS display_code,
  (u.full_name || ' (' || to_char(a.start_time, 'HH12:MI AM') || ')') AS display_text,
  b.full_name AS barber_name,
  hs.style_name AS hairstyle_name,
  hv.front_view_url AS preview_image,
  a.status,
  a.appointment_date AS service_date,
  a.start_time,
  a.end_time
FROM appointments a
JOIN users u ON a.user_id = u.user_id
JOIN barbers b ON a.barber_id = b.barber_id
JOIN appointment_details ad ON a.appointment_id = ad.appointment_id
JOIN hairstyle_variants hv ON ad.variant_id = hv.variant_id
JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE a.status IN ('Scheduled', 'CheckedIn', 'InProgress')
  AND a.appointment_date = CURRENT_DATE

UNION ALL

SELECT
  'Walk-in'::TEXT AS service_type,
  wq.queue_number AS display_code,
  ('Walk-in #' || RIGHT(wq.queue_number, 3) || ' (' || to_char(wq.created_at, 'HH12:MI AM') || ')') AS display_text,
  b.full_name AS barber_name,
  hs.style_name AS hairstyle_name,
  hv.front_view_url AS preview_image,
  wq.status,
  wq.created_at::DATE AS service_date,
  (wq.estimated_start::TIME) AS start_time,
  NULL::TIME AS end_time
FROM walkin_queue wq
JOIN barbers b ON wq.barber_id = b.barber_id
JOIN walkin_service_details wsd ON wq.queue_id = wsd.queue_id
JOIN hairstyle_variants hv ON wsd.variant_id = hv.variant_id
JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE wq.status IN ('Waiting', 'Assigned', 'InProgress')
  AND wq.created_at::DATE = CURRENT_DATE;

COMMIT;
