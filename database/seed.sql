-- Seed core data for the latest schema
-- TEMP TEST ACCOUNTS (password: password)
-- Customers:
--   user1@barberyanitatis.com
--   user2@barberyanitatis.com
-- Staff:
--   admin@barberyanitatis.com
--   reception@barberyanitatis.com
-- Barbers:
--   miguel@barberyanitatis.com
--   leo@barberyanitatis.com
-- NOTE: Replace the password hashes with real bcrypt hashes for production.

-- Users (mobile customers)
INSERT INTO users (email, password_hash, full_name, phone, gender)
VALUES
	('user1@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Juan Dela Cruz', '09171234567', 'Male'),
	('user2@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Maria Santos', '09179876543', 'Female');

-- Staff accounts (admin/receptionist)
INSERT INTO staff_users (email, password_hash, full_name, role)
VALUES
	('admin@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'System Admin', 'Admin'),
	('reception@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Front Desk', 'Receptionist');

-- User profiles (AI attributes)
INSERT INTO user_profiles (user_id, face_shape, hair_texture, hair_density, hair_length, last_scan_date)
SELECT u.user_id, 'Oval', 'Straight', 'Medium', 'Short', CURDATE()
FROM users u
WHERE u.email = 'user1@barberyanitatis.com';

-- Barbers
INSERT INTO barbers (barber_code, full_name, email, password_hash, specialty, years_experience, bio)
VALUES
	('B-001', 'Miguel Cruz', 'miguel@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Fade & Taper', 6, 'Specialist in modern fades.'),
	('B-002', 'Leo Garcia', 'leo@barberyanitatis.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Classic Cut', 8, 'Clean classic styles and beard trims.');

-- Services
INSERT INTO services (service_code, service_name, description, base_duration, base_price, category)
VALUES
	('SV-001', 'Precision Cut', 'Classic precision haircut', 45, 350.00, 'Haircut'),
	('SV-002', 'Skin Fade', 'Modern skin fade', 50, 400.00, 'Haircut'),
	('SV-003', 'Beard Trim', 'Beard shaping and trim', 20, 200.00, 'Beard');

-- Hairstyles
INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance)
VALUES
	('HS-001', 'Textured Crop', 'Short textured crop with tapered sides', 'Male', 'Easy', 'Medium'),
	('HS-002', 'Classic Pompadour', 'Volume on top with clean sides', 'Male', 'Medium', 'High');

-- Hairstyle variants
INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
			'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
			'Use #1 fade on sides, textured scissors on top.', '#1/#2', 'Matte clay', 35, 0.85
FROM hairstyles h
WHERE h.style_code = 'HS-001';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Wavy',
			 '/assets/hairstyles/pompadour_front.jpg', '/assets/hairstyles/pompadour_side.jpg', '/assets/hairstyles/pompadour_back.jpg',
			 'Tapered sides with volume on top.', '#2/#3', 'Pomade', 45, 0.82
FROM hairstyles h
WHERE h.style_code = 'HS-002';
