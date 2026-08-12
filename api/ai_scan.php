<?php
// AI Face Scan API — feature ranking + Gemini-powered categorized recommendations

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/ai_gemini_helper.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';
require_once __DIR__ . '/variant_ranking.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ($_POST['action'] ?? 'rankByFeatures')));

$userID = isset($input['userID']) ? (int)$input['userID'] : (isset($_POST['userID']) ? (int)$_POST['userID'] : 0);
$faceShape = trim((string)($input['faceShape'] ?? ($_POST['faceShape'] ?? '')));
$hairTexture = trim((string)($input['hairTexture'] ?? ($_POST['hairTexture'] ?? '')));
$hairDensity = trim((string)($input['hairDensity'] ?? ($_POST['hairDensity'] ?? '')));
$boostStyleKeys = [];
foreach (($input['boostStyleKeys'] ?? []) as $key) {
    if (is_string($key) && trim($key) !== '') {
        $boostStyleKeys[] = trim($key);
    }
}
$downrankVariantIds = [];
foreach (($input['downrankVariantIds'] ?? []) as $id) {
    $vid = (int)$id;
    if ($vid > 0) {
        $downrankVariantIds[] = $vid;
    }
}

$rankingOptions = [
    'boostStyleKeys' => $boostStyleKeys,
    'downrankVariantIds' => $downrankVariantIds,
];

/**
 * Recompute match components in PHP (mirrors SQL in fetch_live_recommendations).
 *
 * @return array{match_score: float, match_breakdown: list<array{key: string, label: string, contribution: float, detail: string}>}
 */
function compute_match_components(array $row, string $faceShape, string $hairTexture): array
{
    $confidence = (float)($row['confidence_score'] ?? 0);
    $variantFace = strtolower(trim((string)($row['face_shape'] ?? '')));
    $variantTexture = strtolower(trim((string)($row['hair_texture'] ?? '')));
    $userFace = strtolower(trim($faceShape));
    $userTexture = strtolower(trim($hairTexture));
    $styleName = strtolower((string)($row['style_name'] ?? ''));

    $faceBonus = ($userFace !== '' && $variantFace === $userFace) ? 0.45 : 0.0;
    $faceDetail = $faceBonus > 0
        ? 'Matches your ' . $faceShape . ' face'
        : ($variantFace !== '' ? 'Variant targets ' . ucfirst($variantFace) : 'No face-shape tag');

    $textureBonus = 0.05;
    $textureDetail = 'Neutral texture fit';
    if ($userTexture !== '') {
        if ($variantTexture === $userTexture) {
            $textureBonus = 0.55;
            $textureDetail = 'Matches your ' . $hairTexture . ' hair';
        } elseif ($variantTexture !== '') {
            $textureBonus = -0.15;
            $textureDetail = 'Variant is for ' . ucfirst($variantTexture) . ' hair';
        } else {
            $textureDetail = 'Works across textures';
        }
    }

    $compatBonus = 0.0;
    $compatDetail = 'No extra shape pairing';

    $penalty = 0.0;
    $penaltyDetail = 'No length/style penalty';
    if (
        $userTexture !== ''
        && $userTexture !== 'curly'
        && (
            str_contains($styleName, 'afro')
            || str_contains($styleName, 'dread')
            || str_contains($styleName, 'twist')
        )
    ) {
        $penalty = -0.85;
        $penaltyDetail = 'Needs more length for this style today';
    }

    $rawScore = $confidence + $faceBonus + $textureBonus + $compatBonus + $penalty;

    $breakdown = [
        [
            'key' => 'catalog',
            'label' => 'Catalog confidence',
            'contribution' => round($confidence, 3),
            'detail' => 'Base score ' . (int)round($confidence * 100) . '%',
        ],
        [
            'key' => 'face_shape',
            'label' => 'Face shape',
            'contribution' => round($faceBonus, 3),
            'detail' => $faceDetail,
        ],
        [
            'key' => 'hair_texture',
            'label' => 'Hair texture',
            'contribution' => round($textureBonus, 3),
            'detail' => $textureDetail,
        ],
    ];

    if ($compatBonus > 0) {
        $breakdown[] = [
            'key' => 'shape_compat',
            'label' => 'Shape compatibility',
            'contribution' => round($compatBonus, 3),
            'detail' => $compatDetail,
        ];
    }

    if ($penalty < 0) {
        $breakdown[] = [
            'key' => 'style_penalty',
            'label' => 'Length / style',
            'contribution' => round($penalty, 3),
            'detail' => $penaltyDetail,
        ];
    }

    return [
        'match_score' => round($rawScore, 4),
        'match_breakdown' => $breakdown,
    ];
}

/** Theoretical raw score range for absolute % display (see compute_match_components). */
function match_score_raw_floor(): float
{
    return 0.30;
}

function match_score_raw_ceiling(): float
{
    return 2.10;
}

function absolute_match_percent(float $raw): int
{
    $floor = match_score_raw_floor();
    $ceiling = match_score_raw_ceiling();
    $span = max(0.01, $ceiling - $floor);
    $pct = (int)round(100 * (($raw - $floor) / $span));

    return max(40, min(98, $pct));
}

/**
 * Optional spread within a small list (top picks / category) so siblings are not identical %.
 *
 * @param list<array<string, mixed>> $rows
 * @return list<array<string, mixed>>
 */
function apply_section_percent_spread(array $rows): array
{
    if (count($rows) < 2) {
        return $rows;
    }

    $scores = array_map(static fn(array $r): float => (float)($r['match_score'] ?? 0), $rows);
    $min = min($scores);
    $max = max($scores);
    $span = $max - $min;
    if ($span < 0.02) {
        return $rows;
    }

    $out = [];
    foreach ($rows as $row) {
        $raw = (float)($row['match_score'] ?? 0);
        $base = (int)($row['match_percent'] ?? absolute_match_percent($raw));
        $relative = (int)round(68 + (28 * (($raw - $min) / $span)));
        $row['match_percent'] = max($base - 8, min(98, max($base, $relative)));
        $out[] = $row;
    }

    return $out;
}

/**
 * Assign absolute match_percent, catalog rank, and sort by raw score.
 *
 * @param list<array<string, mixed>> $rows
 * @param int $catalogTotal
 * @return list<array<string, mixed>>
 */
function assign_match_display_fields(array $rows, int $catalogTotal = 0): array
{
    if ($rows === []) {
        return [];
    }

    usort(
        $rows,
        static fn(array $a, array $b): int => ((float)($b['match_score'] ?? 0)) <=> ((float)($a['match_score'] ?? 0))
    );

    $total = $catalogTotal > 0 ? $catalogTotal : count($rows);
    $out = [];
    foreach ($rows as $rank => $row) {
        $raw = (float)($row['match_score'] ?? 0);
        $row['match_score_raw'] = $raw;
        $row['match_percent'] = absolute_match_percent($raw);
        $row['match_rank'] = $rank + 1;
        $row['match_rank_label'] = '#' . ($rank + 1) . ' of ' . $total;
        $out[] = $row;
    }

    return $out;
}

/**
 * @param list<array<string, mixed>> $variants sorted by match_score desc
 * @return list<array<string, mixed>>
 */
function filter_top_picks_with_quality_gate(array $variants, int $maxPicks = 3): array
{
    if ($variants === []) {
        return [];
    }

    $bestRaw = (float)($variants[0]['match_score'] ?? 0);
    $bestPercent = absolute_match_percent($bestRaw);
    $minRaw = $bestRaw - 0.25;
    $minPercent = 72;

    $picked = [];
    foreach ($variants as $row) {
        $raw = (float)($row['match_score'] ?? 0);
        $pct = absolute_match_percent($raw);
        if ($raw < $minRaw && $pct < $minPercent && $bestPercent >= 78) {
            continue;
        }
        $picked[] = $row;
        if (count($picked) >= $maxPicks) {
            break;
        }
    }

    if ($picked === []) {
        $picked[] = $variants[0];
    }

    return apply_section_percent_spread($picked);
}

/**
 * @param list<array<string, mixed>> $rows
 * @return list<array<string, mixed>>
 */
function enrich_recommendations_with_match_display(array $rows, string $faceShape, string $hairTexture): array
{
    $enriched = [];
    foreach ($rows as $row) {
        if (!is_array($row)) {
            continue;
        }
        $components = compute_match_components($row, $faceShape, $hairTexture);
        $enriched[] = array_merge($row, $components);
    }

    return assign_match_display_fields($enriched, count($enriched));
}

/**
 * @param list<array<string, mixed>> $items
 * @param array<int, array<string, mixed>> $byId
 * @return list<array<string, mixed>>
 */
function merge_match_fields_from_index(array $items, array $byId): array
{
    $keys = ['match_score', 'match_score_raw', 'match_percent', 'match_rank', 'match_rank_label', 'match_breakdown'];
    $out = [];
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $id = (int)($item['variant_id'] ?? 0);
        $base = $id > 0 && isset($byId[$id]) ? $byId[$id] : $item;
        $merged = $item;
        foreach ($keys as $key) {
            if (array_key_exists($key, $base)) {
                $merged[$key] = $base[$key];
            }
        }
        $out[] = $merged;
    }

    return $out;
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
    if (preg_match('/mullet|edgar|quiff|burst|messy|curtains|pompadour|curly|wavy|modern/', $name) === 1) {
        return 'alternative';
    }
    if (preg_match('/crop|taper|fade|buzz|caesar|french|classic|two.?block/', $name) === 1) {
        return 'formal';
    }

    return 'alternative';
}

function build_rule_based_fit_reason(array $row, string $faceShape, string $hairTexture, string $category = ''): string
{
    $style = trim((string)($row['style_name'] ?? 'This style'));
    $desc = trim((string)($row['description'] ?? ''));
    $variantId = (int)($row['variant_id'] ?? 0);
    $pct = (int)($row['match_percent'] ?? absolute_match_percent((float)($row['match_score'] ?? 0)));
    $rankLabel = trim((string)($row['match_rank_label'] ?? ''));

    $highlights = [];
    foreach (($row['match_breakdown'] ?? []) as $line) {
        if (!is_array($line)) {
            continue;
        }
        $contrib = (float)($line['contribution'] ?? 0);
        if ($contrib <= 0) {
            continue;
        }
        $detail = trim((string)($line['detail'] ?? ''));
        if ($detail !== '') {
            $highlights[] = $detail;
        }
    }

    $lead = $style;
    if ($faceShape !== '' && $hairTexture !== '') {
        $lead .= " is a {$pct}% match for your {$faceShape} face and {$hairTexture} hair";
    } else {
        $lead .= " scores {$pct}% for your features";
    }
    if ($rankLabel !== '') {
        $lead .= " ({$rankLabel} in our catalog)";
    }
    $lead .= '.';

    if ($category === 'formal') {
        $lead .= ' It reads clean and professional for work or events.';
    } elseif ($category === 'alternative') {
        $lead .= ' It adds a bolder, more expressive edge while staying wearable.';
    } else {
        $lead .= ' It works well as an everyday barbershop cut.';
    }

    if ($highlights !== []) {
        $lead .= ' ' . implode(' ', array_slice($highlights, 0, 2)) . '.';
    }

    if ($desc !== '') {
        $snippet = strlen($desc) > 100 ? substr($desc, 0, 97) . '...' : $desc;
        $lead .= ' Catalog note: ' . $snippet;
    }

    if ($variantId > 0) {
        $lead .= " (Ref #{$variantId}.)";
    }

    return preg_replace('/\s+/', ' ', $lead) ?? $lead;
}

function apply_unique_fit_reasons(array $items, string $faceShape, string $hairTexture): array
{
    $seen = [];
    $out = [];
    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }
        $reason = trim((string)($item['fit_reason'] ?? ''));
        $normalized = strtolower(preg_replace('/[^a-z0-9]+/', ' ', $reason) ?? $reason);
        if ($reason === '' || isset($seen[$normalized])) {
            $cat = trim((string)($item['category'] ?? ''));
            $item['fit_reason'] = build_rule_based_fit_reason($item, $faceShape, $hairTexture, $cat);
            $normalized = strtolower(preg_replace('/[^a-z0-9]+/', ' ', (string)$item['fit_reason']) ?? '');
        }
        $seen[$normalized] = true;
        $out[] = $item;
    }

    return $out;
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
    foreach (['formal', 'alternative'] as $cat) {
        $pool = [];
        foreach (($categories[$cat] ?? []) as $row) {
            if (!is_array($row)) {
                continue;
            }
            $pool[] = $row;
        }
        $normalizedCategories[$cat] = pick_unique_variants($pool, $usedIds, 2);
    }

    $insights['categories'] = $normalizedCategories;

    return $insights;
}

function enrich_variant_copy(array $row, string $faceShape, string $hairTexture, string $category = ''): array
{
    $copy = $row;
    $copy['fit_reason'] = build_rule_based_fit_reason($row, $faceShape, $hairTexture, $category);
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
            'categories' => ['formal' => [], 'alternative' => []],
            'aiSummary' => 'No matching hairstyles are available yet.',
            'aiPowered' => false,
        ];
    }

    $catalogTotal = count($variants);
    $usedIds = [];
    $topRows = filter_top_picks_with_quality_gate($variants, 3);
    foreach ($topRows as &$row) {
        $usedIds[(int)($row['variant_id'] ?? 0)] = true;
    }
    unset($row);

    $topWithReason = array_map(
        static fn(array $row): array => enrich_variant_copy($row, $faceShape, $hairTexture),
        $topRows
    );

    $byCategory = ['formal' => [], 'alternative' => []];
    foreach ($variants as $row) {
        $cat = categorize_variant_rule($row);
        $byCategory[$cat][] = $row;
    }

    $categories = ['formal' => [], 'alternative' => []];
    foreach (array_keys($categories) as $cat) {
        $picked = pick_unique_variants($byCategory[$cat], $usedIds, 2);
        $picked = apply_section_percent_spread($picked);
        foreach ($picked as $row) {
            $categories[$cat][] = enrich_variant_copy($row, $faceShape, $hairTexture, $cat);
        }
    }

    foreach (array_keys($categories) as $cat) {
        if ($categories[$cat] !== []) {
            continue;
        }
        $fallback = pick_unique_variants($variants, $usedIds, 1);
        foreach ($fallback as $row) {
            $categories[$cat][] = enrich_variant_copy($row, $faceShape, $hairTexture, $cat);
        }
    }

    $insights = apply_category_rules_to_insights([
        'topPicks' => $topWithReason,
        'categories' => $categories,
        'aiSummary' => "Based on your {$faceShape} face and {$hairTexture} hair, we picked formal and alternative styles ranked #{$catalogTotal} in our catalog.",
        'aiPowered' => false,
    ]);

    $insights['topPicks'] = apply_unique_fit_reasons($insights['topPicks'], $faceShape, $hairTexture);
    foreach (['formal', 'alternative'] as $cat) {
        $insights['categories'][$cat] = apply_unique_fit_reasons(
            $insights['categories'][$cat] ?? [],
            $faceShape,
            $hairTexture
        );
    }

    return $insights;
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
    "alternative": [{"variant_id": number, "fit_reason": "string"}]
  }
}

Rules:
- topPicks: exactly 3 distinct variant_ids (best overall matches).
- formal: exactly 2 distinct variant_ids (clean/professional).
- alternative: exactly 2 distinct variant_ids (bold/edgy).
- fit_reason MUST be unique per variant_id — never reuse the same sentence.
- fit_reason MUST name the customer's exact face shape "{$faceShape}" and hair texture "{$hairTexture}" (not generic "face shape").
- Mention something specific from the catalog notes when available.
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
                $reason = build_rule_based_fit_reason($row, $faceShape, $hairTexture, $category);
            }
            $copy['fit_reason'] = $reason;
            if ($category !== '') {
                $copy['category'] = $category;
            }
            $out[] = $copy;
        }
        return $out;
    };

    $topPicks = merge_match_fields_from_index($enrich($parsed['topPicks'] ?? [], $byId), $byId);
    $categoriesIn = $parsed['categories'] ?? [];
    $categories = [
        'formal' => merge_match_fields_from_index($enrich($categoriesIn['formal'] ?? [], $byId, 'formal'), $byId),
        'alternative' => merge_match_fields_from_index($enrich($categoriesIn['alternative'] ?? [], $byId, 'alternative'), $byId),
    ];

    if ($topPicks === []) {
        return null;
    }

    $insights = apply_category_rules_to_insights([
        'topPicks' => merge_match_fields_from_index($topPicks, $byId),
        'categories' => [
            'formal' => merge_match_fields_from_index($categories['formal'], $byId),
            'alternative' => merge_match_fields_from_index($categories['alternative'], $byId),
        ],
        'aiSummary' => trim((string)($parsed['aiSummary'] ?? '')),
        'aiPowered' => true,
    ]);

    $insights['topPicks'] = apply_unique_fit_reasons($insights['topPicks'], $faceShape, $hairTexture);
    foreach (['formal', 'alternative'] as $cat) {
        $insights['categories'][$cat] = apply_unique_fit_reasons(
            $insights['categories'][$cat] ?? [],
            $faceShape,
            $hairTexture
        );
    }

    return $insights;
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $userID, $faceShape, $hairTexture, $hairDensity, $rankingOptions): void {
    $recommendations = enrich_recommendations_with_match_display(
        fetch_live_recommendations($pdo, $faceShape, $hairTexture, $rankingOptions),
        $faceShape,
        $hairTexture
    );
    $byVariantId = [];
    foreach ($recommendations as $row) {
        $byVariantId[(int)($row['variant_id'] ?? 0)] = $row;
    }

    if ($action === 'rankByFeatures') {
        $usedIds = [];
        $deduped = dedupe_variant_rows($recommendations, $usedIds);
    json_response([
        'message' => 'Live recommendations ready',
        'userID' => $userID,
        'faceShape' => $faceShape,
        'hairTexture' => $hairTexture,
        'hairDensity' => $hairDensity,
            'libraryCatalogSize' => overlay_library_catalog_size(),
            'libraryOnly' => true,
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

        $insights['topPicks'] = merge_match_fields_from_index($insights['topPicks'] ?? [], $byVariantId);
        $catIn = $insights['categories'] ?? [];
        $insights['categories'] = [
            'formal' => merge_match_fields_from_index($catIn['formal'] ?? [], $byVariantId),
            'alternative' => merge_match_fields_from_index($catIn['alternative'] ?? [], $byVariantId),
        ];

        json_response([
            'message' => 'AI recommendations ready',
            'userID' => $userID,
            'faceShape' => $faceShape,
            'hairTexture' => $hairTexture,
            'hairDensity' => $hairDensity,
            'libraryCatalogSize' => overlay_library_catalog_size(),
            'libraryOnly' => true,
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
