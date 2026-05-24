-- Trim face shapes to Oval/Round/Square and hair textures to Straight/Wavy/Curly.

UPDATE hairstyle_variants
SET face_shape = 'Oval'
WHERE LOWER(TRIM(face_shape)) IN ('oblong', 'heart', 'diamond');

UPDATE hairstyle_variants
SET hair_texture = 'Curly'
WHERE hair_texture = 'Coily';

UPDATE user_profiles
SET face_shape = 'Oval'
WHERE LOWER(TRIM(face_shape)) IN ('oblong', 'heart', 'diamond');

UPDATE user_profiles
SET hair_texture = 'Curly'
WHERE hair_texture = 'Coily';

UPDATE face_scan_sessions
SET face_shape = 'oval'
WHERE LOWER(TRIM(face_shape)) IN ('oblong', 'heart', 'diamond');

UPDATE face_scan_sessions
SET hair_texture = 'Curly'
WHERE hair_texture = 'Coily';

ALTER TABLE user_profiles DROP CONSTRAINT IF EXISTS user_profiles_hair_texture_check;
ALTER TABLE user_profiles
    ADD CONSTRAINT user_profiles_hair_texture_check
    CHECK (hair_texture IS NULL OR hair_texture IN ('Straight', 'Wavy', 'Curly'));

ALTER TABLE hairstyle_variants DROP CONSTRAINT IF EXISTS hairstyle_variants_hair_texture_check;
ALTER TABLE hairstyle_variants
    ADD CONSTRAINT hairstyle_variants_hair_texture_check
    CHECK (hair_texture IN ('Straight', 'Wavy', 'Curly'));
