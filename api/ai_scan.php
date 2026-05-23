<?php
// AI Face Scan API — feature ranking + Gemini-powered categorized recommendations

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/ai_gemini_helper.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ($_POST['action'] ?? 'rankByFeatures')));

$userID = isset($input['userID']) ? (int)$input['userID'] : (isset($_POST['userID']) ? (int)$_POST['userID'] : 0);
$faceShape = trim((string)($input['faceShape'] ?? ($_POST['faceShape'] ?? '')));
$hairTexture = trim((string)($input['hairTexture'] ?? ($_POST['hairTexture'] ?? '')));
$hairDensity = trim((string)($input['hairDensity'] ?? ($_POST['hairDensity'] ?? '')));

function variant_matches_customer_texture(array $row, string $hairTexture): bool
{
    $user = strtolower(trim($hairTexture));
    if ($user === '') {
        return true;
    }

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
        if ($hasCurlyMarker) {
            return false;
        }
        if ($hasWavyMarker) {
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

function filter_recommendations_for_customer(array $rows, string $hairTexture): array
{
    $filtered = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        if (variant_matches_customer_texture($row, $hairTexture)) {
            $filtered[] = $row;
        }
    }

    return dedupe_recommendations_by_style_name($filtered);
}

function fetch_live_recommendations(PDO $pdo, string $faceShape, string $hairTexture): array
{
    $query = <<<'SQL'
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
            WHEN :face_shape <> ''
                AND :hair_texture <> ''
                AND LOWER(hv.face_shape) IN ('oval', 'oblong')
                AND LOWER(:face_shape) IN ('oval', 'oblong')
                AND LOWER(hv.face_shape) <> LOWER(:face_shape)
            THEN 0.12
            ELSE 0
          END
        + CASE
            WHEN :hair_texture <> ''
                AND LOWER(:hair_texture) <> 'coily'
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
ORDER BY match_score DESC, hv.confidence_score DESC, hs.style_name
LIMIT 24
SQL;

    $stmt = $pdo->prepare($query);
    $stmt->execute([
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
    ]);

    $rows = $stmt->fetchAll();
    $mapped = array_map('apply_hairstyle_overlay_paths', $rows);

    return array_slice(filter_recommendations_for_customer($mapped, $hairTexture), 0, 24);
}

function variant_catalog_line(array $row): string
{
    $id = (int)($row['variant_id'] ?? 0);
    $name = (string)($row['style_name'] ?? '');
    $face = (string)($row['face_shape'] ?? '');
    $texture = (string)($row['hair_texture'] ?? '');
    $score = (float)($row['match_score'] ?? 0);
    $desc = substr((string)($row['description'] ?? ''), 0, 120);
    return "variant_id={$id}; style=\"{$name}\"; face={$face}; texture={$texture}; score={$score}; notes={$desc}";
}

function categorize_variant_rule(array $row): string
{
    $name = strtolower((string)($row['style_name'] ?? ''));
    if (preg_match('/mullet|edgar|quiff|burst|messy|curtains|pompadour/', $name) === 1) {
        return 'alternative';
    }
    if (preg_match('/crop|taper|fade|buzz|caesar|french|classic|two.?block/', $name) === 1) {
        return 'formal';
    }
    if (preg_match('/curly|wavy|youth|modern/', $name) === 1) {
        return 'youthful';
    }
    return 'youthful';
}

function dedupe_variant_rows(array $rows, array &$usedIds): array
{
    $out = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $id = (int)($row['variant_id'] ?? 0);
        if ($id <= 0 || isset($usedIds[$id])) {
            continue;
        }
        $usedIds[$id] = true;
        $out[] = $row;
    }

    return $out;
}

function apply_category_rules_to_insights(array $insights): array
{
    $categories = $insights['categories'] ?? [];
    if (!is_array($categories)) {
        $categories = [];
    }

    $usedIds = [];
    $topPicks = dedupe_variant_rows($insights['topPicks'] ?? [], $usedIds);
    $topPicks = array_map(
        static function (array $row): array {
            $copy = $row;
            $copy['category'] = categorize_variant_rule($row);

            return $copy;
        },
        $topPicks
    );
    $insights['topPicks'] = $topPicks;

    $normalizedCategories = [];
    foreach (['formal', 'alternative', 'youthful'] as $cat) {
        $pool = [];
        foreach (($categories[$cat] ?? []) as $row) {
            if (!is_array($row)) {
                continue;
            }
            $pool[] = enrich_variant_copy($row, '', '', $cat);
        }
        $normalizedCategories[$cat] = pick_unique_variants($pool, $usedIds, 3);
    }

    $insights['categories'] = $normalizedCategories;

    return $insights;
}

function enrich_variant_copy(array $row, string $faceShape, string $hairTexture, string $category = ''): array
{
    $copy = $row;
    $style = (string)($row['style_name'] ?? 'This style');
    $copy['fit_reason'] = $category !== ''
        ? "The {$style} balances your {$faceShape} face shape and {$hairTexture} hair texture for a {$category} look."
        : "{$style} complements your {$faceShape} face and {$hairTexture} hair for everyday wear.";
    if ($category !== '') {
        $copy['category'] = $category;
    }
    return $copy;
}

function pick_unique_variants(array $variants, array &$usedIds, int $limit = 1): array
{
    $picked = [];
    foreach ($variants as $row) {
        $id = (int)($row['variant_id'] ?? 0);
        if ($id <= 0 || isset($usedIds[$id])) {
            continue;
        }
        $usedIds[$id] = true;
        $picked[] = $row;
        if (count($picked) >= $limit) {
            break;
        }
    }
    return $picked;
}

function build_rule_based_insights(array $variants, string $faceShape, string $hairTexture): array
{
    if ($variants === []) {
        return [
            'topPicks' => [],
            'categories' => ['formal' => [], 'alternative' => [], 'youthful' => []],
            'aiSummary' => 'No matching hairstyles are available yet.',
            'aiPowered' => false,
        ];
    }

    $usedIds = [];
    $topRows = pick_unique_variants($variants, $usedIds, 3);
    $topWithReason = array_map(
        static fn(array $row): array => enrich_variant_copy($row, $faceShape, $hairTexture),
        $topRows
    );

    $byCategory = ['formal' => [], 'alternative' => [], 'youthful' => []];
    foreach ($variants as $row) {
        $byCategory[categorize_variant_rule($row)][] = $row;
    }

    $categories = ['formal' => [], 'alternative' => [], 'youthful' => []];
    foreach (array_keys($categories) as $cat) {
        $picked = pick_unique_variants($byCategory[$cat], $usedIds, 3);
        foreach ($picked as $row) {
            $categories[$cat][] = enrich_variant_copy($row, $faceShape, $hairTexture, $cat);
        }
    }

    // Fill empty category slots from remaining ranked variants (never duplicate IDs).
    foreach (array_keys($categories) as $cat) {
        if ($categories[$cat] !== []) {
            continue;
        }
        $fallback = pick_unique_variants($variants, $usedIds, 1);
        foreach ($fallback as $row) {
            $categories[$cat][] = enrich_variant_copy($row, $faceShape, $hairTexture, $cat);
        }
    }

    return apply_category_rules_to_insights([
        'topPicks' => $topWithReason,
        'categories' => $categories,
        'aiSummary' => "Based on your {$faceShape} face and {$hairTexture} hair, we grouped styles into formal, alternative, and youthful options.",
        'aiPowered' => false,
    ]);
}

function build_gemini_insights(array $variants, string $faceShape, string $hairTexture, string $hairDensity): ?array
{
    if (!ai_gemini_enabled() || $variants === []) {
        return null;
    }

    $lines = array_map('variant_catalog_line', array_slice($variants, 0, 18));
    $catalog = implode("\n", $lines);
    $densityLine = $hairDensity !== '' ? "Hair density: {$hairDensity}." : '';

    $prompt = <<<PROMPT
You are an expert barber AI for Tati's Barbershop in the Philippines.
Customer profile:
- Face shape: {$faceShape}
- Hair texture: {$hairTexture}
{$densityLine}

Available hairstyle variants (pick ONLY from this list by variant_id):
{$catalog}

Return strict JSON with this schema:
{
  "aiSummary": "2 sentences about this customer's features and styling direction",
  "topPicks": [
    {"variant_id": number, "fit_reason": "1-2 sentences why this suits them"}
  ],
  "categories": {
    "formal": [{"variant_id": number, "fit_reason": "string"}],
    "alternative": [{"variant_id": number, "fit_reason": "string"}],
    "youthful": [{"variant_id": number, "fit_reason": "string"}]
  }
}

Rules:
- topPicks: exactly 3 distinct variant_ids (best overall matches).
- Each category: 1-3 distinct variant_ids not repeated across categories when possible.
- formal = clean/professional; alternative = bold/edgy; youthful = trendy/fresh.
- fit_reason must mention face shape and/or hair texture.
PROMPT;

    $raw = ai_gemini_generate_text($prompt, 0.35, 2200);
    $parsed = ai_gemini_parse_json($raw);
    if ($parsed === null) {
        return null;
    }

    $byId = [];
    foreach ($variants as $row) {
        $byId[(int)$row['variant_id']] = $row;
    }

    $enrich = static function (array $items, array $byId, string $category = '') use ($faceShape, $hairTexture): array {
        $out = [];
        foreach ($items as $item) {
            if (!is_array($item)) {
                continue;
            }
            $id = (int)($item['variant_id'] ?? 0);
            if ($id <= 0 || !isset($byId[$id])) {
                continue;
            }
            $row = $byId[$id];
            $copy = $row;
            $reason = trim((string)($item['fit_reason'] ?? ''));
            if ($reason === '') {
                $style = (string)($row['style_name'] ?? 'This style');
                $reason = "{$style} suits your {$faceShape} face and {$hairTexture} hair.";
            }
            $copy['fit_reason'] = $reason;
            if ($category !== '') {
                $copy['category'] = $category;
            }
            $out[] = $copy;
        }
        return $out;
    };

    $topPicks = $enrich($parsed['topPicks'] ?? [], $byId);
    $categoriesIn = $parsed['categories'] ?? [];
    $categories = [
        'formal' => $enrich($categoriesIn['formal'] ?? [], $byId, 'formal'),
        'alternative' => $enrich($categoriesIn['alternative'] ?? [], $byId, 'alternative'),
        'youthful' => $enrich($categoriesIn['youthful'] ?? [], $byId, 'youthful'),
    ];

    if ($topPicks === []) {
        return null;
    }

    return apply_category_rules_to_insights([
        'topPicks' => $topPicks,
        'categories' => $categories,
        'aiSummary' => trim((string)($parsed['aiSummary'] ?? '')),
        'aiPowered' => true,
    ]);
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $userID, $faceShape, $hairTexture, $hairDensity): void {
    $recommendations = fetch_live_recommendations($pdo, $faceShape, $hairTexture);

    if ($action === 'rankByFeatures') {
        $usedIds = [];
        $deduped = dedupe_variant_rows($recommendations, $usedIds);
        json_response([
            'message' => 'Live recommendations ready',
            'userID' => $userID,
            'faceShape' => $faceShape,
            'hairTexture' => $hairTexture,
            'hairDensity' => $hairDensity,
            'recommendations' => $deduped,
            'variants' => $deduped,
        ]);
    }

    if ($action === 'recommendWithInsights') {
        $insights = build_gemini_insights($recommendations, $faceShape, $hairTexture, $hairDensity);
        if ($insights === null) {
            $insights = build_rule_based_insights($recommendations, $faceShape, $hairTexture);
        } elseif (trim((string)($insights['aiSummary'] ?? '')) === '') {
            $fallback = build_rule_based_insights($recommendations, $faceShape, $hairTexture);
            $insights['aiSummary'] = $fallback['aiSummary'];
        }

        json_response([
            'message' => 'AI recommendations ready',
            'userID' => $userID,
            'faceShape' => $faceShape,
            'hairTexture' => $hairTexture,
            'hairDensity' => $hairDensity,
            'recommendations' => $recommendations,
            'topPicks' => $insights['topPicks'],
            'categories' => $insights['categories'],
            'aiSummary' => $insights['aiSummary'],
            'aiPowered' => (bool)($insights['aiPowered'] ?? false),
        ]);
    }

    json_response(['error' => 'Invalid action'], 400);
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
}
