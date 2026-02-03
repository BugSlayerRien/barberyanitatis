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
	('HS-002', 'Classic Pompadour', 'Volume on top with clean sides', 'Male', 'Medium', 'High'),
	('HS-003', 'Low Taper', 'Clean taper with natural top', 'Male', 'Easy', 'Low'),
	('HS-004', 'Buzz Cut', 'Short uniform cut with clean edges', 'Male', 'Easy', 'Low'),
	('HS-005', 'Side Part', 'Classic side part with neat finish', 'Male', 'Medium', 'Medium'),
	('HS-006', 'Quiff', 'Textured quiff with volume', 'Male', 'Medium', 'High'),
	('HS-007', 'French Crop', 'Short fringe with textured top and clean sides', 'Male', 'Easy', 'Low'),
	('HS-008', 'Crew Cut', 'Short, tapered cut with slightly longer top', 'Male', 'Easy', 'Low'),
	('HS-009', 'High Fade', 'High fade with defined contrast and clean finish', 'Male', 'Medium', 'Medium'),
	('HS-010', 'Mid Fade', 'Balanced mid fade with versatile top length', 'Male', 'Medium', 'Medium'),
	('HS-011', 'Low Fade', 'Low fade with soft blend and natural top', 'Male', 'Easy', 'Medium'),
	('HS-012', 'Taper Fade', 'Classic taper fade with gradual blend', 'Male', 'Easy', 'Low'),
	('HS-013', 'Drop Fade', 'Fade that drops behind the ear for contour', 'Male', 'Medium', 'Medium'),
	('HS-014', 'Burst Fade', 'Circular fade around the ear with textured top', 'Male', 'Medium', 'Medium'),
	('HS-015', 'Temple Fade', 'Clean temple fade with crisp edges', 'Male', 'Easy', 'Medium'),
	('HS-016', 'Skin Fade', 'Zero fade with sharp contrast and clean lines', 'Male', 'Medium', 'High'),
	('HS-017', 'Undercut', 'Disconnected sides with longer top', 'Male', 'Medium', 'Medium'),
	('HS-018', 'Disconnected Undercut', 'Bold separation between long top and short sides', 'Male', 'Medium', 'High'),
	('HS-019', 'Slick Back', 'Combed back with shine and controlled shape', 'Male', 'Medium', 'High'),
	('HS-020', 'Comb Over', 'Side-swept top with neat fade or taper', 'Male', 'Medium', 'Medium'),
	('HS-021', 'Ivy League', 'Short, refined cut with tidy side part', 'Male', 'Easy', 'Low'),
	('HS-022', 'Caesar Cut', 'Short fringe with uniform length on top', 'Male', 'Easy', 'Low'),
	('HS-023', 'Faux Hawk', 'Raised center with tapered sides', 'Male', 'Medium', 'Medium'),
	('HS-024', 'Modern Mullet', 'Short sides with length at the back', 'Male', 'Medium', 'Medium'),
	('HS-025', 'Wolf Cut', 'Layered, textured cut with volume and movement', 'Unisex', 'Medium', 'High'),
	('HS-026', 'Curtains', 'Middle part with longer, soft layers', 'Unisex', 'Medium', 'Medium'),
	('HS-027', 'Textured Fringe', 'Forward fringe with choppy texture', 'Unisex', 'Medium', 'Medium'),
	('HS-028', 'Messy Crop', 'Short crop with tousled texture', 'Male', 'Easy', 'Low'),
	('HS-029', 'Curly Top Fade', 'Curly top with clean faded sides', 'Male', 'Medium', 'High'),
	('HS-030', 'Afro Taper', 'Tapered sides with shaped afro top', 'Male', 'Medium', 'Medium'),
	('HS-031', 'High Top Fade', 'Tall top with sharp high fade', 'Male', 'Medium', 'Medium'),
	('HS-032', 'Flat Top', 'Level top with crisp edges and fade', 'Male', 'Medium', 'Low'),
	('HS-033', 'Two Block', 'K-style short sides with longer top', 'Male', 'Medium', 'High'),
	('HS-034', 'Edgar Cut', 'Straight fringe with short faded sides', 'Male', 'Easy', 'Medium'),
	('HS-035', 'Blowout Taper', 'Voluminous top with clean taper', 'Male', 'Medium', 'High'),
	('HS-036', 'Man Bun', 'Long hair tied back with clean edges', 'Male', 'Medium', 'High'),
	('HS-037', 'Bro Flow', 'Medium length with natural flow and layers', 'Male', 'Easy', 'Medium'),
	('HS-038', 'Side Swept', 'Side-swept top with soft taper', 'Unisex', 'Easy', 'Medium'),
	('HS-039', 'Short Shag', 'Layered shaggy cut with texture', 'Unisex', 'Medium', 'High'),
	('HS-040', 'Long Layers', 'Long layered cut for movement and shape', 'Unisex', 'Medium', 'Medium');

-- Hairstyle variants
INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/textured crop front.png', '/assets/hairstyles/textured crop - left side.png', '/assets/hairstyles/textured crop - right side).png',
			'Use #1 fade on sides, textured scissors on top.', '#1/#2', 'Matte clay', 35, 0.85
FROM hairstyles h
WHERE h.style_code = 'HS-001';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Wavy',
			 '/assets/hairstyles/classic_pompadour_front.png', '/assets/hairstyles/classic pompadour- left.png', '/assets/hairstyles/classic pompadour- right.png',
			 'Tapered sides with volume on top.', '#2/#3', 'Pomade', 45, 0.82
FROM hairstyles h
WHERE h.style_code = 'HS-002';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		 '/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		 'Low taper on sides, natural top.', '#1/#2', 'Light wax', 30, 0.81
FROM hairstyles h
WHERE h.style_code = 'HS-003';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Straight',
		 '/assets/hairstyles/buzz_front.jpg', '/assets/hairstyles/buzz_side.jpg', '/assets/hairstyles/buzz_back.jpg',
		 'Uniform #2 buzz with clean edges.', '#2', 'None', 20, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-004';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Side part with tapered sides.', '#2/#3', 'Pomade', 35, 0.80
FROM hairstyles h
WHERE h.style_code = 'HS-005';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Textured quiff with volume.', '#2', 'Volumizing spray', 40, 0.79
FROM hairstyles h
WHERE h.style_code = 'HS-006';

-- Placeholder variants for newly added styles
INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
		'French crop with short fringe and textured top.', '#1/#2', 'Matte clay', 30, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-007';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Crew cut with tapered sides and clean neckline.', '#2/#3', 'Light wax', 25, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-008';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Diamond', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'High fade with crisp edges and clean blend.', '0/#1', 'Matte clay', 35, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-009';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Mid fade with soft blend and tidy top.', '#0.5/#1', 'Light wax', 35, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-010';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Low fade with natural top and clean edges.', '#1/#2', 'Light wax', 30, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-011';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Classic taper fade with gradual blend.', '#1/#2', 'Light wax', 30, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-012';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Heart', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Drop fade behind the ear with defined contour.', '#0.5/#1', 'Matte clay', 35, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-013';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Wavy',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Burst fade around the ear with textured top.', '#1/#2', 'Sea salt spray', 35, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-014';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Temple fade with sharp line-up and clean edges.', '#0.5/#1', 'Matte clay', 30, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-015';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Straight',
		'/assets/hairstyles/low_taper_front.jpg', '/assets/hairstyles/low_taper_side.jpg', '/assets/hairstyles/low_taper_back.jpg',
		'Skin fade with sharp contrast and clean finish.', '0/#0.5', 'Matte clay', 35, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-016';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Undercut with disconnected sides and longer top.', '#1/#2', 'Pomade', 35, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-017';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Diamond', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Bold disconnected undercut with long top.', '#0.5/#1', 'Pomade', 40, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-018';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Straight',
		'/assets/hairstyles/pompadour_front.jpg', '/assets/hairstyles/pompadour_side.jpg', '/assets/hairstyles/pompadour_back.jpg',
		'Slick back with controlled shine and clean sides.', '#2/#3', 'Pomade', 40, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-019';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Comb over with neat side part and taper.', '#2/#3', 'Pomade', 35, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-020';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Ivy League with tidy side part and taper.', '#2/#3', 'Light wax', 30, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-021';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Straight',
		'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
		'Caesar cut with short fringe and even top.', '#2', 'Matte clay', 25, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-022';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Heart', 'Straight',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Faux hawk with tapered sides and textured top.', '#1/#2', 'Matte clay', 35, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-023';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Modern mullet with short sides and longer back.', '#1/#2', 'Sea salt spray', 40, 0.75
FROM hairstyles h
WHERE h.style_code = 'HS-024';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Wolf cut with layered texture and movement.', '#2', 'Texturizing spray', 45, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-025';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Curtains with soft layers and middle part.', '#2/#3', 'Light wax', 40, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-026';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
		'Textured fringe with forward movement.', '#1/#2', 'Matte clay', 30, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-027';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Straight',
		'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
		'Messy crop with light texture on top.', '#2', 'Matte clay', 25, 0.75
FROM hairstyles h
WHERE h.style_code = 'HS-028';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Curly',
		'/assets/hairstyles/curly top fade - front.png', '/assets/hairstyles/curly top fade - left.png', '/assets/hairstyles/curly top fade right.png',
		'Curly top with clean faded sides.', '#1/#2', 'Curl cream', 40, 0.79
FROM hairstyles h
WHERE h.style_code = 'HS-029';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Coily',
		'/assets/hairstyles/afro_taper_front.png', '/assets/hairstyles/afro_taper_left.png', '/assets/hairstyles/afro_taper_right.png',
		'Afro taper with shaped top and clean edges.', '#1/#2', 'Curl sponge', 40, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-030';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Coily',
		'/assets/hairstyles/high_top_fade_front.png', '/assets/hairstyles/high_top_fade_left.png', '/assets/hairstyles/high_top_fade_right.png',
		'High top fade with sharp edges and clean blend.', '#1/#2', 'Curl sponge', 40, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-031';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Square', 'Straight',
		'/assets/hairstyles/flat_top_front.png', '/assets/hairstyles/flat_top_front.png', '/assets/hairstyles/flat_top_front.png',
		'Flat top with crisp edges and tight fade.', '#1/#2', 'Matte clay', 35, 0.76
FROM hairstyles h
WHERE h.style_code = 'HS-032';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Two block with short sides and longer top.', '#2/#3', 'Light wax', 40, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-033';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Round', 'Straight',
		'/assets/hairstyles/texture_crop_front.jpg', '/assets/hairstyles/texture_crop_side.jpg', '/assets/hairstyles/texture_crop_back.jpg',
		'Edgar cut with straight fringe and tight sides.', '#1/#2', 'Matte clay', 30, 0.77
FROM hairstyles h
WHERE h.style_code = 'HS-034';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Wavy',
		'/assets/hairstyles/blowout_taper_front.png', '/assets/hairstyles/blowout_taper_left.png', '/assets/hairstyles/blowout_taper_right.png',
		'Blowout taper with volume and clean edges.', '#1/#2', 'Volumizing spray', 40, 0.78
FROM hairstyles h
WHERE h.style_code = 'HS-035';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Man bun with clean edges and tied back length.', '#2', 'Light wax', 45, 0.74
FROM hairstyles h
WHERE h.style_code = 'HS-036';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Bro flow with medium length and natural movement.', '#2/#3', 'Sea salt spray', 40, 0.74
FROM hairstyles h
WHERE h.style_code = 'HS-037';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Diamond', 'Straight',
		'/assets/hairstyles/sidepart_front.jpg', '/assets/hairstyles/sidepart_side.jpg', '/assets/hairstyles/sidepart_back.jpg',
		'Side swept top with soft taper.', '#2/#3', 'Light wax', 35, 0.75
FROM hairstyles h
WHERE h.style_code = 'HS-038';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oval', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Short shag with layered texture.', '#2', 'Texturizing spray', 40, 0.75
FROM hairstyles h
WHERE h.style_code = 'HS-039';

INSERT INTO hairstyle_variants (
	hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
	barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
)
SELECT h.hairstyle_id, 'Oblong', 'Wavy',
		'/assets/hairstyles/quiff_front.jpg', '/assets/hairstyles/quiff_side.jpg', '/assets/hairstyles/quiff_back.jpg',
		'Long layers with movement and soft shape.', '#3', 'Light cream', 45, 0.74
FROM hairstyles h
WHERE h.style_code = 'HS-040';
