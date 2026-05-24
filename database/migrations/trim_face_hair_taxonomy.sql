-- Trim face shapes to Oval/Round/Square and hair textures to Straight/Wavy/Curly.
-- Merges duplicate variants when Oblong/Heart/Diamond -> Oval or Coily -> Curly.

BEGIN;

CREATE TEMP TABLE _variant_taxonomy_map ON COMMIT DROP AS
WITH mapped AS (
    SELECT
        variant_id,
        hairstyle_id,
        CASE
            WHEN LOWER(TRIM(face_shape)) IN ('oblong', 'heart', 'diamond') THEN 'Oval'
            WHEN LOWER(TRIM(face_shape)) = 'round' THEN 'Round'
            WHEN LOWER(TRIM(face_shape)) = 'square' THEN 'Square'
            WHEN LOWER(TRIM(face_shape)) = 'oval' THEN 'Oval'
            ELSE INITCAP(LOWER(TRIM(face_shape)))
        END AS new_face_shape,
        CASE
            WHEN hair_texture = 'Coily' THEN 'Curly'
            ELSE hair_texture
        END AS new_hair_texture,
        confidence_score
    FROM hairstyle_variants
),
ranked AS (
    SELECT
        variant_id,
        hairstyle_id,
        new_face_shape,
        new_hair_texture,
        ROW_NUMBER() OVER (
            PARTITION BY hairstyle_id, new_face_shape, new_hair_texture
            ORDER BY confidence_score DESC NULLS LAST, variant_id ASC
        ) AS rn
    FROM mapped
)
SELECT
    r.variant_id,
    r.hairstyle_id,
    r.new_face_shape,
    r.new_hair_texture,
    r.rn,
    k.variant_id AS keeper_id
FROM ranked r
JOIN ranked k
    ON k.hairstyle_id = r.hairstyle_id
   AND k.new_face_shape = r.new_face_shape
   AND k.new_hair_texture = r.new_hair_texture
   AND k.rn = 1;

-- Repoint FKs from duplicate variants to the keeper row
UPDATE appointment_details ad
SET variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE ad.variant_id = m.variant_id AND m.rn > 1;

UPDATE walkin_service_details wsd
SET variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE wsd.variant_id = m.variant_id AND m.rn > 1;

UPDATE user_favorites uf
SET variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE uf.variant_id = m.variant_id AND m.rn > 1;

UPDATE user_history uh
SET variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE uh.variant_id = m.variant_id AND m.rn > 1;

UPDATE user_style_preferences usp
SET preferred_variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE usp.preferred_variant_id = m.variant_id AND m.rn > 1;

UPDATE ai_recommendation_events e
SET variant_id = m.keeper_id
FROM _variant_taxonomy_map m
WHERE e.variant_id = m.variant_id AND m.rn > 1;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = current_schema() AND table_name = 'face_scan_previews'
    ) THEN
        UPDATE face_scan_previews fsp
        SET variant_id = m.keeper_id
        FROM _variant_taxonomy_map m
        WHERE fsp.variant_id = m.variant_id AND m.rn > 1;
    END IF;
END $$;

DELETE FROM hairstyle_variants hv
USING _variant_taxonomy_map m
WHERE hv.variant_id = m.variant_id AND m.rn > 1;

UPDATE hairstyle_variants hv
SET
    face_shape = m.new_face_shape,
    hair_texture = m.new_hair_texture
FROM _variant_taxonomy_map m
WHERE hv.variant_id = m.variant_id AND m.rn = 1;

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

COMMIT;
