<?php
declare(strict_types=1);

/**
 * Shared hairstyle variant ranking (single source for ai_scan.php and haircuts.php).
 */

require_once __DIR__ . '/hairstyle_overlay_paths.php';

function variant_matches_customer_texture(array $row, string $hairTexture): bool
{
    $user = strtolower(trim($hairTexture));
    if ($user === '') {
        return true;
    }

    $variantTex = strtolower(trim((string)($row['hair_texture'] ?? '')));
    if ($variantTex !== '' && $variantTex !== $user) {
        if (
            ($user === 'wavy' && $variantTex === 'curly')
            || ($user === 'curly' && $variantTex === 'wavy')
        ) {
            return true;
        }

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
    if ($hairTexture === '' || count($deduped) >= 8 || !$allowLibraryRelax) {
        return $deduped;
    }

    return dedupe_recommendations_by_style_name(
        array_values(array_filter($rows, static fn($row): bool => is_array($row)))
    );
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

function fetch_ranked_variants(PDO $pdo, string $faceShape, string $hairTexture, array $options = []): array
{
    schema_ensure_once('hairstyles.top_pick_eligible', static function () use ($pdo): void {
        ensure_top_pick_eligible_column($pdo);
    });

    $catalogSize = overlay_library_catalog_size();
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
        $codes = overlay_library_style_codes();
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
{$libraryWhere}
{$faceWhere}
ORDER BY match_score DESC, hv.confidence_score DESC, hs.style_name
LIMIT {$sqlLimit}
SQL;

    $stmt = $pdo->prepare($query);
    $stmt->execute($params);

    $rows = array_map('apply_hairstyle_overlay_paths', $stmt->fetchAll());
    if ($libraryOnly) {
        $rows = filter_overlay_library_rows($rows);
    }
    $rows = filter_recommendations_for_customer($rows, $hairTexture, $libraryOnly && !$libraryFaceFilter);
    $rows = apply_variant_ranking_adjustments($rows, $options);

    return array_slice($rows, 0, $limit);
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
