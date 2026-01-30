/* ====================================================================
   BARBERSHOP MANAGEMENT SYSTEM WITH AI HAIRSTYLE RECOMMENDATION
   Database Schema - SQL Server (T-SQL)
   Normalized to 3NF with proper relationships
   ==================================================================== */

-- =========================
-- 1. USER MANAGEMENT
-- =========================

CREATE TABLE dbo.users (
  user_id INT IDENTITY(1,1) PRIMARY KEY,
  email NVARCHAR(150) NOT NULL UNIQUE,
  password_hash NVARCHAR(255) NOT NULL,
  full_name NVARCHAR(150) NOT NULL,
  phone NVARCHAR(20) NULL,
  gender NVARCHAR(10) NOT NULL DEFAULT 'Male',
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  is_active BIT NOT NULL DEFAULT 1
);

CREATE INDEX idx_email_active ON dbo.users (email, is_active);

CREATE TABLE dbo.user_profiles (
  profile_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT NOT NULL UNIQUE,
  face_shape NVARCHAR(50) NULL,
  hair_texture NVARCHAR(20) NULL,
  hair_density NVARCHAR(20) NULL,
  hair_length NVARCHAR(20) NULL,
  last_scan_date DATE NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_user_profiles_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_user_face_shape ON dbo.user_profiles (user_id, face_shape);

CREATE TABLE dbo.staff_users (
  staff_id INT IDENTITY(1,1) PRIMARY KEY,
  email NVARCHAR(150) NOT NULL UNIQUE,
  password_hash NVARCHAR(255) NOT NULL,
  full_name NVARCHAR(150) NOT NULL,
  role NVARCHAR(20) NOT NULL,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_staff_role_active ON dbo.staff_users (role, is_active);

-- =========================
-- 2. BARBER MANAGEMENT
-- =========================

CREATE TABLE dbo.barbers (
  barber_id INT IDENTITY(1,1) PRIMARY KEY,
  barber_code NVARCHAR(10) NOT NULL UNIQUE,
  full_name NVARCHAR(150) NOT NULL,
  email NVARCHAR(150) NULL UNIQUE,
  password_hash NVARCHAR(255) NULL,
  profile_image NVARCHAR(255) NULL,
  specialty NVARCHAR(100) NULL,
  years_experience INT NULL,
  bio NVARCHAR(MAX) NULL,
  rating DECIMAL(3,2) NOT NULL DEFAULT 5.00,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_code_active ON dbo.barbers (barber_code, is_active);

-- =========================
-- 3. HAIRSTYLE CATALOG (AI DATASET)
-- =========================

CREATE TABLE dbo.hairstyles (
  hairstyle_id INT IDENTITY(1,1) PRIMARY KEY,
  style_code NVARCHAR(20) NOT NULL UNIQUE,
  style_name NVARCHAR(100) NOT NULL,
  description NVARCHAR(MAX) NULL,
  gender NVARCHAR(10) NOT NULL DEFAULT 'Unisex',
  difficulty NVARCHAR(10) NOT NULL DEFAULT 'Medium',
  maintenance NVARCHAR(10) NOT NULL DEFAULT 'Medium',
  popularity_score INT NOT NULL DEFAULT 0,
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_gender_active ON dbo.hairstyles (gender, is_active);

CREATE TABLE dbo.hairstyle_variants (
  variant_id INT IDENTITY(1,1) PRIMARY KEY,
  hairstyle_id INT NOT NULL,
  face_shape NVARCHAR(50) NOT NULL,
  hair_texture NVARCHAR(20) NOT NULL,
  front_view_url NVARCHAR(255) NOT NULL,
  side_view_url NVARCHAR(255) NULL,
  back_view_url NVARCHAR(255) NULL,
  barber_instructions NVARCHAR(MAX) NOT NULL,
  clipper_sizes NVARCHAR(100) NULL,
  styling_products NVARCHAR(MAX) NULL,
  estimated_minutes INT NOT NULL DEFAULT 30,
  confidence_score DECIMAL(4,3) NOT NULL DEFAULT 0.8,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_variants_hairstyles FOREIGN KEY (hairstyle_id) REFERENCES dbo.hairstyles(hairstyle_id) ON DELETE CASCADE,
  CONSTRAINT uq_variant UNIQUE (hairstyle_id, face_shape, hair_texture)
);

CREATE INDEX idx_face_hair ON dbo.hairstyle_variants (face_shape, hair_texture);

-- =========================
-- 4. SERVICES & PRICING
-- =========================

CREATE TABLE dbo.services (
  service_id INT IDENTITY(1,1) PRIMARY KEY,
  service_code NVARCHAR(20) NOT NULL UNIQUE,
  service_name NVARCHAR(100) NOT NULL,
  description NVARCHAR(MAX) NULL,
  base_duration INT NOT NULL,
  base_price DECIMAL(10,2) NOT NULL,
  category NVARCHAR(20) NOT NULL DEFAULT 'Haircut',
  is_active BIT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_category_active ON dbo.services (category, is_active);

-- =========================
-- 5. AI SCAN SESSIONS (KIOSK ONLY)
-- =========================

CREATE TABLE dbo.kiosk_sessions (
  session_id NVARCHAR(50) PRIMARY KEY,
  original_image_url NVARCHAR(255) NULL,
  face_shape NVARCHAR(50) NULL,
  hair_texture NVARCHAR(20) NULL,
  hair_density NVARCHAR(20) NULL,
  scan_timestamp DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  expires_at DATETIME2 NOT NULL,
  is_processed BIT NOT NULL DEFAULT 0
);

CREATE INDEX idx_expiry ON dbo.kiosk_sessions (expires_at, is_processed);

CREATE TABLE dbo.kiosk_recommendations (
  recommendation_id INT IDENTITY(1,1) PRIMARY KEY,
  session_id NVARCHAR(50) NOT NULL,
  variant_id INT NOT NULL,
  rank_position INT NOT NULL,
  match_score DECIMAL(4,3) NOT NULL,
  is_selected BIT NOT NULL DEFAULT 0,
  selected_view NVARCHAR(10) NOT NULL DEFAULT 'Front',
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_reco_session FOREIGN KEY (session_id) REFERENCES dbo.kiosk_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT fk_reco_variant FOREIGN KEY (variant_id) REFERENCES dbo.hairstyle_variants(variant_id),
  CONSTRAINT uq_session_rank UNIQUE (session_id, rank_position)
);

CREATE INDEX idx_session_selected ON dbo.kiosk_recommendations (session_id, is_selected);

-- =========================
-- 6. APPOINTMENTS (MOBILE APP)
-- =========================

CREATE TABLE dbo.appointments (
  appointment_id INT IDENTITY(1,1) PRIMARY KEY,
  booking_code NVARCHAR(20) NOT NULL UNIQUE,
  user_id INT NOT NULL,
  barber_id INT NOT NULL,
  appointment_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status NVARCHAR(20) NOT NULL DEFAULT 'Scheduled',
  checkin_time DATETIME2 NULL,
  completion_time DATETIME2 NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_appt_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id),
  CONSTRAINT fk_appt_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id)
);

CREATE INDEX idx_date_status ON dbo.appointments (appointment_date, status);
CREATE INDEX idx_user_dates ON dbo.appointments (user_id, appointment_date DESC);

CREATE TABLE dbo.appointment_details (
  detail_id INT IDENTITY(1,1) PRIMARY KEY,
  appointment_id INT NOT NULL,
  service_id INT NOT NULL,
  variant_id INT NOT NULL,
  selected_view NVARCHAR(10) NOT NULL DEFAULT 'Front',
  special_instructions NVARCHAR(MAX) NULL,
  final_price DECIMAL(10,2) NOT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_appt_detail_appt FOREIGN KEY (appointment_id) REFERENCES dbo.appointments(appointment_id) ON DELETE CASCADE,
  CONSTRAINT fk_appt_detail_service FOREIGN KEY (service_id) REFERENCES dbo.services(service_id),
  CONSTRAINT fk_appt_detail_variant FOREIGN KEY (variant_id) REFERENCES dbo.hairstyle_variants(variant_id),
  CONSTRAINT uq_appt_service UNIQUE (appointment_id, service_id)
);

-- =========================
-- 7. TIME SLOT MANAGEMENT
-- =========================

CREATE TABLE dbo.time_slots (
  slot_id INT IDENTITY(1,1) PRIMARY KEY,
  barber_id INT NOT NULL,
  slot_date DATE NOT NULL,
  slot_time TIME NOT NULL,
  duration INT NOT NULL DEFAULT 35,
  status NVARCHAR(20) NOT NULL DEFAULT 'Available',
  appointment_id INT NULL,
  expected_start DATETIME2 NULL,
  expected_end DATETIME2 NULL,
  actual_start DATETIME2 NULL,
  actual_end DATETIME2 NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_slots_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id),
  CONSTRAINT fk_slots_appt FOREIGN KEY (appointment_id) REFERENCES dbo.appointments(appointment_id),
  CONSTRAINT uq_barber_slot UNIQUE (barber_id, slot_date, slot_time)
);

CREATE INDEX idx_slot_date_status ON dbo.time_slots (slot_date, status);

-- =========================
-- 8. WALK-IN QUEUE (KIOSK)
-- =========================

CREATE TABLE dbo.walkin_queue (
  queue_id INT IDENTITY(1,1) PRIMARY KEY,
  queue_number NVARCHAR(20) NOT NULL,
  session_id NVARCHAR(50) NOT NULL,
  barber_id INT NULL,
  estimated_start DATETIME2 NULL,
  actual_start DATETIME2 NULL,
  actual_end DATETIME2 NULL,
  status NVARCHAR(20) NOT NULL DEFAULT 'Waiting',
  wait_time_minutes INT NULL,
  people_count INT NOT NULL DEFAULT 1,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_queue_session FOREIGN KEY (session_id) REFERENCES dbo.kiosk_sessions(session_id) ON DELETE CASCADE,
  CONSTRAINT fk_queue_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id)
);

CREATE INDEX idx_status_date ON dbo.walkin_queue (status, created_at);
CREATE INDEX idx_barber_status ON dbo.walkin_queue (barber_id, status);

CREATE TABLE dbo.walkin_service_details (
  detail_id INT IDENTITY(1,1) PRIMARY KEY,
  queue_id INT NOT NULL,
  service_id INT NOT NULL,
  variant_id INT NOT NULL,
  selected_view NVARCHAR(10) NOT NULL DEFAULT 'Front',
  special_instructions NVARCHAR(MAX) NULL,
  final_price DECIMAL(10,2) NOT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_walkin_detail_queue FOREIGN KEY (queue_id) REFERENCES dbo.walkin_queue(queue_id) ON DELETE CASCADE,
  CONSTRAINT fk_walkin_detail_service FOREIGN KEY (service_id) REFERENCES dbo.services(service_id),
  CONSTRAINT fk_walkin_detail_variant FOREIGN KEY (variant_id) REFERENCES dbo.hairstyle_variants(variant_id)
);

-- =========================
-- 9. PAYMENTS
-- =========================

CREATE TABLE dbo.payments (
  payment_id INT IDENTITY(1,1) PRIMARY KEY,
  payment_ref NVARCHAR(50) NOT NULL UNIQUE,
  appointment_id INT NULL,
  queue_id INT NULL,
  amount DECIMAL(10,2) NOT NULL,
  discount_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  tax_amount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  total_amount DECIMAL(10,2) NOT NULL,
  payment_method NVARCHAR(20) NOT NULL DEFAULT 'Cash',
  payment_status NVARCHAR(20) NOT NULL DEFAULT 'Pending',
  paid_at DATETIME2 NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_payment_appt FOREIGN KEY (appointment_id) REFERENCES dbo.appointments(appointment_id),
  CONSTRAINT fk_payment_queue FOREIGN KEY (queue_id) REFERENCES dbo.walkin_queue(queue_id)
);

CREATE INDEX idx_status_date_pay ON dbo.payments (payment_status, created_at);

-- =========================
-- 10. FEEDBACK & RATINGS
-- =========================

CREATE TABLE dbo.feedback (
  feedback_id INT IDENTITY(1,1) PRIMARY KEY,
  appointment_id INT NOT NULL,
  user_id INT NOT NULL,
  barber_id INT NOT NULL,
  overall_rating INT NULL,
  barber_rating INT NULL,
  service_rating INT NULL,
  wait_time_rating INT NULL,
  comment NVARCHAR(MAX) NULL,
  would_recommend BIT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_feedback_appt FOREIGN KEY (appointment_id) REFERENCES dbo.appointments(appointment_id),
  CONSTRAINT fk_feedback_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id),
  CONSTRAINT fk_feedback_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id)
);

CREATE INDEX idx_barber_rating ON dbo.feedback (barber_id, created_at DESC);

-- =========================
-- 11. NOTIFICATIONS (ALL IN ONE TABLE)
-- =========================

CREATE TABLE dbo.notifications (
  notification_id INT IDENTITY(1,1) PRIMARY KEY,
  recipient_type NVARCHAR(20) NOT NULL,
  recipient_id INT NOT NULL,
  notification_type NVARCHAR(20) NOT NULL,
  title NVARCHAR(200) NOT NULL,
  message NVARCHAR(MAX) NOT NULL,
  data NVARCHAR(MAX) NULL,
  is_read BIT NOT NULL DEFAULT 0,
  is_sent BIT NOT NULL DEFAULT 0,
  scheduled_send DATETIME2 NULL,
  sent_at DATETIME2 NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_recipient_unread ON dbo.notifications (recipient_type, recipient_id, is_read, created_at DESC);
CREATE INDEX idx_scheduled ON dbo.notifications (scheduled_send, is_sent);

-- =========================
-- 12. FAVORITES & HISTORY
-- =========================

CREATE TABLE dbo.user_favorites (
  favorite_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT NOT NULL,
  variant_id INT NULL,
  barber_id INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_fav_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_fav_variant FOREIGN KEY (variant_id) REFERENCES dbo.hairstyle_variants(variant_id),
  CONSTRAINT fk_fav_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id),
  CONSTRAINT uq_user_favorite UNIQUE (user_id, variant_id, barber_id)
);

CREATE TABLE dbo.user_history (
  history_id INT IDENTITY(1,1) PRIMARY KEY,
  user_id INT NOT NULL,
  appointment_id INT NOT NULL,
  variant_id INT NOT NULL,
  service_date DATE NOT NULL,
  notes NVARCHAR(MAX) NULL,
  after_photo_url NVARCHAR(255) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_history_user FOREIGN KEY (user_id) REFERENCES dbo.users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_history_appt FOREIGN KEY (appointment_id) REFERENCES dbo.appointments(appointment_id),
  CONSTRAINT fk_history_variant FOREIGN KEY (variant_id) REFERENCES dbo.hairstyle_variants(variant_id)
);

CREATE INDEX idx_user_history ON dbo.user_history (user_id, service_date DESC);

-- =========================
-- 13. ANALYTICS & REPORTS
-- =========================

CREATE TABLE dbo.daily_analytics (
  analytics_date DATE PRIMARY KEY,
  total_appointments INT NOT NULL DEFAULT 0,
  completed_appointments INT NOT NULL DEFAULT 0,
  total_walkins INT NOT NULL DEFAULT 0,
  completed_walkins INT NOT NULL DEFAULT 0,
  total_revenue DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  avg_service_time INT NOT NULL DEFAULT 0,
  peak_hour NVARCHAR(5) NULL,
  most_popular_service_id INT NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_daily_service FOREIGN KEY (most_popular_service_id) REFERENCES dbo.services(service_id)
);

CREATE TABLE dbo.barber_performance (
  performance_id INT IDENTITY(1,1) PRIMARY KEY,
  barber_id INT NOT NULL,
  period_date DATE NOT NULL,
  period_type NVARCHAR(10) NOT NULL DEFAULT 'Monthly',
  total_services INT NOT NULL DEFAULT 0,
  total_revenue DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  avg_rating DECIMAL(3,2) NOT NULL DEFAULT 0.00,
  client_retention_rate DECIMAL(5,2) NOT NULL DEFAULT 0.00,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT fk_perf_barber FOREIGN KEY (barber_id) REFERENCES dbo.barbers(barber_id),
  CONSTRAINT uq_barber_period UNIQUE (barber_id, period_date, period_type)
);

-- =========================
-- 14. SYSTEM MANAGEMENT
-- =========================

CREATE TABLE dbo.system_settings (
  setting_key NVARCHAR(100) PRIMARY KEY,
  setting_value NVARCHAR(MAX) NULL,
  setting_type NVARCHAR(10) NOT NULL DEFAULT 'String',
  category NVARCHAR(50) NULL,
  description NVARCHAR(MAX) NULL,
  is_editable BIT NOT NULL DEFAULT 1,
  updated_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.audit_logs (
  log_id INT IDENTITY(1,1) PRIMARY KEY,
  action_type NVARCHAR(50) NOT NULL,
  table_name NVARCHAR(50) NULL,
  record_id NVARCHAR(100) NULL,
  old_values NVARCHAR(MAX) NULL,
  new_values NVARCHAR(MAX) NULL,
  user_id INT NULL,
  ip_address NVARCHAR(45) NULL,
  user_agent NVARCHAR(MAX) NULL,
  created_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);

CREATE INDEX idx_action_date ON dbo.audit_logs (action_type, created_at DESC);

-- =========================
-- 15. QUEUE DISPLAY VIEW
-- =========================

CREATE OR ALTER VIEW dbo.queue_display AS
SELECT 
  'Appointment' AS service_type,
  a.booking_code AS display_code,
  CONCAT(u.full_name, ' (', FORMAT(CAST(a.start_time AS datetime), 'hh:mm tt'), ')') AS display_text,
  b.full_name AS barber_name,
  hs.style_name AS hairstyle_name,
  hv.front_view_url AS preview_image,
  a.status,
  a.appointment_date AS service_date,
  a.start_time,
  a.end_time
FROM dbo.appointments a
JOIN dbo.users u ON a.user_id = u.user_id
JOIN dbo.barbers b ON a.barber_id = b.barber_id
JOIN dbo.appointment_details ad ON a.appointment_id = ad.appointment_id
JOIN dbo.hairstyle_variants hv ON ad.variant_id = hv.variant_id
JOIN dbo.hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE a.status IN ('Scheduled', 'CheckedIn', 'InProgress')
  AND a.appointment_date = CAST(GETDATE() AS date)

UNION ALL

SELECT 
  'Walk-in' AS service_type,
  wq.queue_number AS display_code,
  CONCAT('Walk-in #', RIGHT(wq.queue_number, 3), ' (', FORMAT(wq.created_at, 'hh:mm tt'), ')') AS display_text,
  b.full_name AS barber_name,
  hs.style_name AS hairstyle_name,
  hv.front_view_url AS preview_image,
  wq.status,
  CAST(wq.created_at AS date) AS service_date,
  wq.estimated_start,
  NULL AS end_time
FROM dbo.walkin_queue wq
JOIN dbo.barbers b ON wq.barber_id = b.barber_id
JOIN dbo.walkin_service_details wsd ON wq.queue_id = wsd.queue_id
JOIN dbo.hairstyle_variants hv ON wsd.variant_id = hv.variant_id
JOIN dbo.hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE wq.status IN ('Waiting', 'Assigned', 'InProgress')
  AND CAST(wq.created_at AS date) = CAST(GETDATE() AS date);
