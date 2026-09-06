-- Hairstyle catalog cleanup.
--
-- Fixes four defects found by auditing the live catalog:
--
--   1. DUPLICATE STYLES. Two seed generations wrote the same haircuts under
--      different style_code prefixes ('STYLE-*' from seed_minimum_pg.php,
--      'HC-*' from seed_all_overlay_hairstyles.php). Both scripts upsert with
--      ON CONFLICT (style_code), which cannot detect a duplicate that differs
--      only by code -- so "Blowout Taper" and "Textured Crop" each exist twice.
--      The HC-* row is the keeper: it is the one wired to overlay assets.
--
--   2. SQUARE FACE SHAPE IS EMPTY. detect_face_shape() in ai-service/api.py can
--      classify a user as Square, and ai_funnel.php accepts it, but the catalog
--      held exactly ONE Square variant and it belonged to an inactive style.
--      Square users therefore got zero recommendations. Mirrors the Oval
--      variants to Square.
--
--   3. MIS-TAGGED TEXTURE. 'Curly Top Fade' was tagged Wavy, so it was offered
--      to wavy-haired users and hidden from the curly users it is meant for.
--
--   4. POMPADOUR INACTIVE. It has complete overlay assets but was deactivated,
--      so it could never be recommended or booked.
--
-- Idempotent: safe to re-run.

BEGIN;

-- 1. Retire the superseded 'STYLE-*' duplicates. Deactivated rather than
--    deleted: appointment_details / user_favorites / user_history may still
--    reference their variants, and history must stay readable.
UPDATE hairstyles
SET is_active = FALSE
WHERE style_code IN ('STYLE-TEXTURED-CROP', 'STYLE-BLOWOUT-TAPER')
  AND EXISTS (
      SELECT 1 FROM hairstyles keeper
      WHERE keeper.style_name = hairstyles.style_name
        AND keeper.style_code LIKE 'HC-%'
  );

-- 3. Correct the texture before mirroring, so Square inherits the fixed value.
UPDATE hairstyle_variants hv
SET hair_texture = 'Curly'
FROM hairstyles hs
WHERE hs.hairstyle_id = hv.hairstyle_id
  AND hs.style_code = 'STYLE-CURLY-TOP-FADE'
  AND hv.hair_texture <> 'Curly';

-- 4. Pompadour has overlay assets; bring it back.
UPDATE hairstyles SET is_active = TRUE WHERE style_code = 'HC-POMPADOUR';

-- 2. Give every active style a Square variant by copying its Oval one.
--    ON CONFLICT keeps this re-runnable and never clobbers a hand-tuned row.
INSERT INTO hairstyle_variants (
    hairstyle_id, face_shape, hair_texture,
    front_view_url, side_view_url, back_view_url,
    barber_instructions, clipper_sizes, styling_products,
    estimated_minutes, confidence_score
)
SELECT
    hv.hairstyle_id, 'Square', hv.hair_texture,
    hv.front_view_url, hv.side_view_url, hv.back_view_url,
    hv.barber_instructions, hv.clipper_sizes, hv.styling_products,
    hv.estimated_minutes,
    -- Slightly below the Oval score: these are mirrored, not individually rated.
    GREATEST(COALESCE(hv.confidence_score, 0.85) - 0.03, 0.50)
FROM hairstyle_variants hv
JOIN hairstyles hs ON hs.hairstyle_id = hv.hairstyle_id
WHERE hv.face_shape = 'Oval'
  AND hs.is_active
ON CONFLICT (hairstyle_id, face_shape, hair_texture) DO NOTHING;

COMMIT;

-- Verify:
--   SELECT face_shape, COUNT(*) FROM hairstyle_variants GROUP BY face_shape;
--   SELECT hv.hair_texture, COUNT(DISTINCT hs.hairstyle_id)
--     FROM hairstyles hs JOIN hairstyle_variants hv USING (hairstyle_id)
--    WHERE hs.is_active GROUP BY hv.hair_texture;
--   SELECT style_name, COUNT(*) FROM hairstyles WHERE is_active
--    GROUP BY style_name HAVING COUNT(*) > 1;
