-- Stable haircut categories + catalog top-up to 10 styles per hair texture.
--
-- PROBLEM 1: CATEGORY WAS DERIVED FROM THE STYLE NAME AT REQUEST TIME.
-- api/ai_scan.php categorize_variant_rule() ran two regexes over style_name:
--     alternative: /mullet|edgar|quiff|burst|messy|curtains|pompadour|curly|wavy|modern/
--     formal:      /crop|taper|fade|buzz|caesar|french|classic|two.?block/
-- The alternative pattern is tested FIRST and matches 'curly' and 'wavy', so
-- every texture-prefixed style was forced into "alternative" no matter what the
-- cut actually is -- "Curly Mid Fade" and "Curly Taper Fade" are clean fades but
-- could never be classified formal. For a curly-haired customer that left the
-- formal section empty and filled by an unrelated fallback pick.
-- A style's category is a property of the cut, so it now lives on the row.
--
-- PROBLEM 2: UNEVEN CATALOG. Curly had 7 styles and Straight 9, against Wavy's
-- 10, so curly customers saw the thinnest choice. Tops both up to 10.
--
-- New styles are created WITHOUT overlay artwork. front_view_url is NOT NULL,
-- so each gets its conventional overlay path; dropping the PNGs into
-- mobile-app/assets/images/overlays/<folder>/ later makes them render with no
-- further SQL. Until then the admin Haircuts page flags them "Missing PNGs".
--
-- Idempotent: safe to re-run.

BEGIN;

-- 1. Category column ------------------------------------------------------
ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS category VARCHAR(20);

ALTER TABLE hairstyles DROP CONSTRAINT IF EXISTS hairstyles_category_check;
ALTER TABLE hairstyles
    ADD CONSTRAINT hairstyles_category_check
    CHECK (category IS NULL OR category IN ('formal', 'alternative'));

-- 2. Backfill every existing style ---------------------------------------
--    formal      = clean, professional, low-drama cuts
--    alternative = bold, textured, statement cuts
UPDATE hairstyles SET category = 'formal' WHERE style_name IN (
    'Buzz Cut', 'Caesar Cut', 'Crew Cut', 'Low Fade', 'French Crop',
    'Two Block', 'Textured Crop', 'Blowout Taper',
    'Curly Taper Fade', 'Curly Mid Fade', 'Curly Crew Cut',
    'Wavy Side Sweep'
);

UPDATE hairstyles SET category = 'alternative' WHERE style_name IN (
    'Edgar Cut', 'Pompadour', 'Modern Mullet', 'Messy Quiff',
    'Modern Curtains', 'Wavy Burst Fade', 'Wavy Fringe', 'Wavy Messy Top',
    'Wavy Mod Cut', 'Curly Burst Fade', 'Curly Drop Fade',
    'Curly Modern Mullet', 'Curly Top Fade', 'Afro Taper'
);

-- Anything still unset (future rows) defaults to alternative, matching the old
-- rule's default so behaviour never regresses to "uncategorised".
UPDATE hairstyles SET category = 'alternative' WHERE category IS NULL;

-- 3. New styles: Straight +1, Curly +3 -> 10 per texture ------------------
INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, is_active, category)
VALUES
    ('HC-MID-FADE',       'Mid Fade',        'Fade starting midway down the sides, clean and versatile.', 'Unisex', 'Medium', 'Medium', TRUE, 'formal'),
    ('HC-CURLY-LOW-FADE', 'Curly Low Fade',  'Low fade with the curl pattern kept full on top.',          'Unisex', 'Medium', 'Medium', TRUE, 'formal'),
    ('HC-CURLY-FRINGE',   'Curly Fringe',    'Curly top worn forward into a soft fringe.',                'Unisex', 'Medium', 'Medium', TRUE, 'alternative'),
    ('HC-CURLY-UNDERCUT', 'Curly Undercut',  'Disconnected short sides with volume left on top.',         'Unisex', 'Medium', 'High',   TRUE, 'alternative')
ON CONFLICT (style_code) DO UPDATE
    SET style_name = EXCLUDED.style_name,
        description = EXCLUDED.description,
        category = EXCLUDED.category,
        is_active = TRUE;

-- 4. Variants for the new styles, all three face shapes -------------------
INSERT INTO hairstyle_variants (
    hairstyle_id, face_shape, hair_texture,
    front_view_url, side_view_url, back_view_url,
    barber_instructions, clipper_sizes, styling_products,
    estimated_minutes, confidence_score
)
SELECT
    hs.hairstyle_id,
    shape.face_shape,
    spec.hair_texture,
    'assets/images/overlays/' || spec.folder || '/' || spec.folder || '_front.png',
    'assets/images/overlays/' || spec.folder || '/' || spec.folder || '_left.png',
    'assets/images/overlays/' || spec.folder || '/' || spec.folder || '_right.png',
    spec.instructions,
    '0.5, 1, 2',
    'Matte clay, light hold spray',
    40,
    -- Below the seeded catalogue's 0.88 so hand-tuned styles with real artwork
    -- outrank these until they are reviewed.
    0.80
FROM (VALUES
    ('HC-MID-FADE',       'Straight', 'mid_fade',       'Fade from mid-height on the sides, blended clean into the top.'),
    ('HC-CURLY-LOW-FADE', 'Curly',    'curly_low_fade', 'Low fade around the ears; keep curl length and definition on top.'),
    ('HC-CURLY-FRINGE',   'Curly',    'curly_fringe',   'Leave curl length at the front, shape it forward into a fringe.'),
    ('HC-CURLY-UNDERCUT', 'Curly',    'curly_undercut', 'Disconnected short sides, full curly volume left on top.')
) AS spec(style_code, hair_texture, folder, instructions)
JOIN hairstyles hs ON hs.style_code = spec.style_code
CROSS JOIN (VALUES ('Oval'), ('Round'), ('Square')) AS shape(face_shape)
ON CONFLICT (hairstyle_id, face_shape, hair_texture) DO NOTHING;

COMMIT;

-- Verify:
--   SELECT category, COUNT(*) FROM hairstyles WHERE is_active GROUP BY category;
--   SELECT hv.hair_texture, COUNT(DISTINCT hs.hairstyle_id)
--     FROM hairstyles hs JOIN hairstyle_variants hv USING (hairstyle_id)
--    WHERE hs.is_active GROUP BY hv.hair_texture;   -- expect 10 / 10 / 10
