<?php
declare(strict_types=1);

/**
 * Shared hairstyle variant ranking (single source for ai_scan.php and haircuts.php).
 */

/**
 * The hair-length level this style normally needs, attached to every ranked
 * row so the client can warn without a second round trip.
 */
function attach_style_min_length(array $row): array
{
    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    $row['min_length_level'] = $key === null
        ? 1
        : (replicate_style_min_length()[$key] ?? 1);

    return $row;
}

require_once __DIR__ . '/hairstyle_overlay_paths.php';
// For replicate_style_min_length(): the app needs to know, per style, whether
// it usually needs more length than the customer has -- so it can warn before
// spending a generation rather than after.
require_once __DIR__ . '/replicate_helper.php';
require_once __DIR__ . '/hairstyle_authoring.php';

function variant_matches_customer_texture(array $row, string $hairTexture): bool
{
    $user = strtolower(trim($hairTexture));
    if ($user === '') {
        return true;
    }

    // Wavy and curly used to be treated as interchangeable here, which put
    // curly styles in front of wavy customers and the reverse. They are
    // different cuts with different maintenance, and the catalog now carries
    // ten distinct styles for each texture, so the pair is matched as strictly
    // as any other.
    $variantTex = strtolower(trim((string)($row['hair_texture'] ?? '')));
    if ($variantTex !== '' && $variantTex !== $user) {
        return false;
    }

    $name = strtolower((string)($row['style_name'] ?? ''));
    $code = strtolower((string)($row['style_code'] ?? ''));

    $hasCurlyMarker = preg_match('/\b(curly|coily|afro|dread|twist|perm)\b/', $name) === 1
        || preg_match('/\b(curly|coily)\b/', $code) === 1;
    $hasWavyMarker = preg_match('/\bwavy\b/', $name) === 1
        || preg_match('/\bwavy\b/', $code) === 1;

    if ($user === 'straight') {
        if ($hasCurlyMarker || $hasWavyMarker) {
            return false;
        }
    }

    if ($user === 'wavy' && $hasCurlyMarker && !$hasWavyMarker) {
        return false;
    }

    return true;
}

function dedupe_recommendations_by_style_name(array $rows): array
{
    $bestByName = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $nameKey = strtolower(trim((string)($row['style_name'] ?? '')));
        if ($nameKey === '') {
            continue;
        }
        $score = (float)($row['match_score'] ?? 0);
        if (!isset($bestByName[$nameKey]) || $score > (float)($bestByName[$nameKey]['match_score'] ?? 0)) {
            $bestByName[$nameKey] = $row;
        }
    }

    $out = array_values($bestByName);
    usort(
        $out,
        static fn(array $a, array $b): int => ((float)($b['match_score'] ?? 0)) <=> ((float)($a['match_score'] ?? 0))
    );

    return $out;
}

function filter_recommendations_for_customer(array $rows, string $hairTexture, bool $allowLibraryRelax = false): array
{
    $strict = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        if (variant_matches_customer_texture($row, $hairTexture)) {
            $strict[] = $row;
        }
    }

    $deduped = dedupe_recommendations_by_style_name($strict);
    if ($hairTexture === '' || !$allowLibraryRelax) {
        return $deduped;
    }

    // The relax threshold used to be a flat 8. Straight hair yields exactly 8
    // matching styles, so deactivating a single straight style tipped it over
    // and the fallback below handed a straight-haired customer the entire
    // catalog, curly styles included. A handful of well-matched styles is a
    // better library than a padded, wrong one, so only relax when the strict
    // set is genuinely too thin to browse.
    if (count($deduped) >= 4) {
        return $deduped;
    }

    // Still keep the customer's own texture first when padding out.
    $relaxed = dedupe_recommendations_by_style_name(
        array_values(array_filter($rows, static fn($row): bool => is_array($row)))
    );
    $strictKeys = [];
    foreach ($deduped as $row) {
        $strictKeys[strtolower(trim((string)($row['style_name'] ?? '')))] = true;
    }
    usort($relaxed, static function (array $a, array $b) use ($strictKeys): int {
        $aStrict = isset($strictKeys[strtolower(trim((string)($a['style_name'] ?? '')))]) ? 0 : 1;
        $bStrict = isset($strictKeys[strtolower(trim((string)($b['style_name'] ?? '')))]) ? 0 : 1;
        if ($aStrict !== $bStrict) {
            return $aStrict <=> $bStrict;
        }

        return ((float)($b['match_score'] ?? 0)) <=> ((float)($a['match_score'] ?? 0));
    });

    return $relaxed;
}

/**
 * Keep only rows that belong to the overlay haircut library catalog.
 */
function filter_overlay_library_rows(array $rows): array
{
    $out = [];
    foreach ($rows as $row) {
        if (is_array($row) && is_overlay_library_row($row)) {
            $out[] = $row;
        }
    }

    return $out;
}

/**
 * @param array{
 *   limit?: int,
 *   libraryOnly?: bool,
 *   libraryFaceFilter?: bool,
 *   boostStyleKeys?: list<string>,
 *   downrankVariantIds?: list<int>
 * } $options
 */
/**
 * Admin switch for excluding a style from the general Top 3 while keeping it in
 * its category list. Defined here rather than only in admin_hairstyles.php
 * because the ranking query below selects the column, so it has to exist on any
 * deploy that serves recommendations -- not just one where an admin has opened
 * the hairstyles screen.
 */
function ensure_top_pick_eligible_column(PDO $pdo): void
{
    $pdo->exec(
        'ALTER TABLE hairstyles
         ADD COLUMN IF NOT EXISTS top_pick_eligible BOOLEAN NOT NULL DEFAULT TRUE'
    );
}

// Normally applied via hairstyle_categories_and_catalog.sql, but the admin
// editor and ranking query both read/write this column, so a fresh
// environment that hasn't run that migration must not 500 on first use.
function ensure_hairstyle_category_column(PDO $pdo): void
{
    $pdo->exec(
        "ALTER TABLE hairstyles
         ADD COLUMN IF NOT EXISTS category VARCHAR(20)"
    );
    $pdo->exec(
        "DO \$\$
         BEGIN
             IF NOT EXISTS (
                 SELECT 1 FROM pg_constraint WHERE conname = 'hairstyles_category_check'
             ) THEN
                 ALTER TABLE hairstyles
                 ADD CONSTRAINT hairstyles_category_check
                 CHECK (category IS NULL OR category IN ('formal', 'alternative'));
             END IF;
         END
         \$\$;"
    );
}

function fetch_ranked_variants(PDO $pdo, string $faceShape, string $hairTexture, array $options = []): array
{
    schema_ensure_once('hairstyles.top_pick_eligible', static function () use ($pdo): void {
        ensure_top_pick_eligible_column($pdo);
    });

    $catalogSize = overlay_library_catalog_size($pdo);
    $limit = max(1, min(48, (int)($options['limit'] ?? $catalogSize)));
    $libraryOnly = (bool)($options['libraryOnly'] ?? true);
    $libraryFaceFilter = (bool)($options['libraryFaceFilter'] ?? false);

    $faceWhere = '';
    if ($libraryFaceFilter) {
        $faceWhere = <<<'SQL'
    AND (
             :face_shape = ''
             OR LOWER(hv.face_shape) = LOWER(:face_shape)
             OR hv.face_shape IS NULL
             OR hv.face_shape = ''
    )
    AND (
             :hair_texture = ''
             OR LOWER(hv.hair_texture) = LOWER(:hair_texture)
             OR hv.hair_texture IS NULL
             OR hv.hair_texture = ''
    )
SQL;
    }

    $libraryWhere = '';
    $params = [
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
    ];
    if ($libraryOnly) {
        $codes = overlay_library_style_codes($pdo);
        $inParts = [];
        foreach ($codes as $index => $code) {
            $param = ':lib_code_' . $index;
            $inParts[] = $param;
            $params[$param] = $code;
        }
        if ($inParts !== []) {
            $libraryWhere = ' AND hs.style_code IN (' . implode(', ', $inParts) . ') ';
        }
    }

    $sqlLimit = $libraryOnly ? max(64, $catalogSize * 3) : max($limit, 24);

    $query = <<<SQL
SELECT
    hv.variant_id,
    hv.face_shape,
    hv.hair_texture,
    hv.front_view_url,
    hv.side_view_url,
    hv.back_view_url,
    hv.confidence_score,
    hv.barber_instructions,
    hv.clipper_sizes,
    hv.styling_products,
    hv.estimated_minutes,
    hs.style_name,
    -- Stable per-style category (see hairstyle_categories_and_catalog.sql).
    -- Replaces the old regex-over-style_name classification, which forced every
    -- 'Curly *' / 'Wavy *' cut into 'alternative' regardless of the actual cut.
    hs.category AS style_category,
    -- Admin switch: excluded styles stay in their category list but are kept
    -- out of the general Top 3 (see filter_top_picks_with_quality_gate).
    COALESCE(hs.top_pick_eligible, TRUE) AS top_pick_eligible,
    hs.style_code,
    hs.description,
    hs.ai_prompt,
    (
        hv.confidence_score
        + CASE
            WHEN :face_shape <> '' AND LOWER(hv.face_shape) = LOWER(:face_shape) THEN 0.45
            ELSE 0
          END
        + CASE
            WHEN :hair_texture <> '' AND LOWER(hv.hair_texture) = LOWER(:hair_texture) THEN 0.55
            WHEN :hair_texture <> '' AND hv.hair_texture IS NOT NULL AND hv.hair_texture <> '' THEN -0.15
            ELSE 0.05
          END
        + CASE
            WHEN :hair_texture <> ''
                AND LOWER(:hair_texture) NOT IN ('curly')
                AND (
                    LOWER(hs.style_name) LIKE '%afro%'
                    OR LOWER(hs.style_name) LIKE '%dread%'
                    OR LOWER(hs.style_name) LIKE '%twist%'
                )
            THEN -0.85
            ELSE 0
          END
    ) AS match_score
FROM hairstyle_variants hv
JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
WHERE hs.is_active = TRUE
  -- A barber's submission is not the shop's catalogue until the owner
  -- says so. COALESCE keeps pre-workflow rows visible.
  AND COALESCE(hs.review_status, 'Published') = 'Published'
{$libraryWhere}
{$faceWhere}
ORDER BY match_score DESC, hv.confidence_score DESC, hs.style_name
LIMIT {$sqlLimit}
SQL;

    $stmt = $pdo->prepare($query);
    $stmt->execute($params);

    $rows = array_map('annotate_variant_artwork', $stmt->fetchAll());
    $rows = array_map('attach_style_min_length', $rows);
    if ($libraryOnly) {
        $rows = filter_overlay_library_rows($rows);
    }
    $rows = filter_recommendations_for_customer($rows, $hairTexture, $libraryOnly && !$libraryFaceFilter);
    $rows = apply_variant_ranking_adjustments($rows, $options);

    return array_slice($rows, 0, $limit);
}

/**
 * Fill in bundled artwork, then say plainly whether there is any.
 *
 * A recommendation with no picture used to arrive looking identical to one
 * with a picture, so the app fell back to a bundled overlay and drew another
 * style's hair. `has_artwork` lets it draw a placeholder instead, and
 * `previewable` says a generation would still work.
 */
function annotate_variant_artwork(array $row): array
{
    $previewable = hairstyle_is_previewable_without_artwork($row);
    $row = apply_hairstyle_overlay_paths($row);
    $row['has_artwork'] = trim((string)($row['front_view_url'] ?? '')) !== '';
    $row['previewable'] = $previewable;
    unset($row['ai_prompt']);

    return $row;
}

/** @param array{boostStyleKeys?: list<string>, downrankVariantIds?: list<int>} $options */
function apply_variant_ranking_adjustments(array $rows, array $options): array
{
    $boostKeys = [];
    foreach (($options['boostStyleKeys'] ?? []) as $key) {
        $normalized = strtolower(trim((string)$key));
        if ($normalized !== '') {
            $boostKeys[$normalized] = true;
        }
    }

    $downrankIds = [];
    foreach (($options['downrankVariantIds'] ?? []) as $id) {
        $vid = (int)$id;
        if ($vid > 0) {
            $downrankIds[$vid] = true;
        }
    }

    if ($boostKeys === [] && $downrankIds === []) {
        return $rows;
    }

    foreach ($rows as &$row) {
        $score = (float)($row['match_score'] ?? 0);
        $variantId = (int)($row['variant_id'] ?? 0);
        $code = strtolower(trim((string)($row['style_code'] ?? '')));
        $name = strtolower(trim((string)($row['style_name'] ?? '')));

        foreach (array_keys($boostKeys) as $key) {
            if ($code === $key || str_contains($name, str_replace('_', ' ', $key))) {
                $score += 0.18;
                break;
            }
        }

        if ($variantId > 0 && isset($downrankIds[$variantId])) {
            $score -= 0.35;
        }

        $row['match_score'] = round($score, 4);
    }
    unset($row);

    usort(
        $rows,
        static fn(array $a, array $b): int => ((float)($b['match_score'] ?? 0)) <=> ((float)($a['match_score'] ?? 0))
    );

    return $rows;
}

function fetch_live_recommendations(PDO $pdo, string $faceShape, string $hairTexture, array $options = []): array
{
    $options['libraryOnly'] = (bool)($options['libraryOnly'] ?? true);
    $options['limit'] = (int)($options['limit'] ?? overlay_library_catalog_size());

    return fetch_ranked_variants($pdo, $faceShape, $hairTexture, $options);
}
