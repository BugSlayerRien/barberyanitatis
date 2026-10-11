<?php
// Haircuts API (list + variants + create)

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';
require_once __DIR__ . '/variant_ranking.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['list', 'listByFaceShape', 'listLibrary', 'searchLibrary', 'create'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    with_pdo_retry(function (PDO $pdo) use ($input, $action): void {
    $normalizeHaircutRow = static function (array $row): array {
        $styleName = trim((string)($row['style_name'] ?? ''));
        if (strcasecmp($styleName, 'Curly Top Fade') === 0) {
            $row['style_name'] = 'Curly Taper Fade';
        }

        $previewable = hairstyle_is_previewable_without_artwork($row);
        $transition = hairstyle_transition_code($row);
        $row = apply_hairstyle_overlay_paths($row);

        // The app used to guess, and guessed wrong: with no artwork it fell
        // back to a bundled overlay and showed another style's hair. These two
        // flags let it draw a placeholder instead.
        $row['has_artwork'] = trim((string)($row['front_view_url'] ?? '')) !== '';
        $row['previewable'] = $previewable;
        $row['transition_style_code'] = $transition;
        // The library's own detail page gates on this as well, so it must
        // agree with the recommendations rather than defaulting to short.
        $row['min_length_level'] = hairstyle_min_length_level($row);
        // The prompt is fetched to decide the above; it is not the customer's
        // business what the image model is told.
        unset($row['ai_prompt']);

        return $row;
    };

    if ($action === 'list') {
        $stmt = $pdo->prepare(
            'SELECT hairstyle_id, style_code, style_name, description, gender, difficulty, maintenance, is_active, ai_prompt, ai_min_length_level, transition_style_code
             FROM hairstyles
               WHERE is_active = TRUE
               AND COALESCE(review_status, \'Published\') = \'Published\'
             ORDER BY style_name'
        );
        $stmt->execute();
        $haircuts = array_map($normalizeHaircutRow, $stmt->fetchAll());
        json_response(['haircuts' => $haircuts]);
    }

    if ($action === 'listByFaceShape') {
        $faceShape = trim((string)($input['faceShape'] ?? ''));
        $hairTexture = trim((string)($input['hairTexture'] ?? ''));

        $variants = array_map(
            $normalizeHaircutRow,
            fetch_ranked_variants($pdo, $faceShape, $hairTexture, [
                'limit' => 24,
                'libraryFaceFilter' => true,
            ])
        );
        json_response(['variants' => $variants]);
    }

    if ($action === 'listLibrary') {
        $codes = overlay_library_style_codes($pdo);
        $inParts = [];
        $params = [];
        foreach ($codes as $index => $code) {
            $param = ':lib_code_' . $index;
            $inParts[] = $param;
            $params[$param] = $code;
        }
        $libraryIn = $inParts !== [] ? ' AND hs.style_code IN (' . implode(', ', $inParts) . ') ' : '';

        $stmt = $pdo->prepare(
            'SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description, hs.gender, hs.difficulty, hs.maintenance, hs.is_active, hs.ai_prompt, hs.ai_min_length_level, hs.transition_style_code,
                    hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes
             FROM hairstyles hs
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = (
                SELECT hv2.variant_id
                FROM hairstyle_variants hv2
                WHERE hv2.hairstyle_id = hs.hairstyle_id
                ORDER BY hv2.confidence_score DESC, hv2.variant_id ASC
                LIMIT 1
             )
                 WHERE hs.is_active = TRUE
                   AND COALESCE(hs.review_status, \'Published\') = \'Published\'
                 ' . $libraryIn . '
             ORDER BY hs.style_name'
        );
        $stmt->execute($params);
        // Optional: the scan results page asks for only styles that suit the
        // scanned texture, using the same rule as the recommendations.
        $hairTexture = trim((string)($input['hairTexture'] ?? ''));
        $hairstyles = array_map(
            $normalizeHaircutRow,
            array_values(array_filter(
                $stmt->fetchAll(),
                static fn(array $row): bool => is_overlay_library_row($row, $codes)
                    && ($hairTexture === '' || variant_matches_customer_texture($row, $hairTexture))
            ))
        );
        json_response([
            'hairstyles' => $hairstyles,
            'libraryCatalogSize' => overlay_library_catalog_size($pdo),
        ]);
    }

    if ($action === 'searchLibrary') {
        $query = trim((string)($input['query'] ?? $input['q'] ?? ''));
        if ($query === '') {
            json_response(['hairstyles' => [], 'query' => '', 'message' => 'Enter a search term']);
        }

        $like = '%' . str_replace(['%', '_'], ['\\%', '\\_'], $query) . '%';
        $stmt = $pdo->prepare(
            'SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description, hs.gender, hs.difficulty, hs.maintenance, hs.is_active, hs.ai_prompt, hs.ai_min_length_level, hs.transition_style_code,
                    hv.variant_id, hv.face_shape, hv.hair_texture, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hv.confidence_score, hv.barber_instructions, hv.clipper_sizes, hv.styling_products, hv.estimated_minutes
             FROM hairstyles hs
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = (
                SELECT hv2.variant_id
                FROM hairstyle_variants hv2
                WHERE hv2.hairstyle_id = hs.hairstyle_id
                ORDER BY hv2.confidence_score DESC, hv2.variant_id ASC
                LIMIT 1
             )
             WHERE hs.is_active = TRUE
               AND COALESCE(hs.review_status, \'Published\') = \'Published\'
               AND (
                    LOWER(hs.style_name) LIKE LOWER(:q)
                    OR LOWER(COALESCE(hs.style_code, \'\')) LIKE LOWER(:q)
                    OR LOWER(COALESCE(hs.description, \'\')) LIKE LOWER(:q)
               )
             ORDER BY hs.style_name
             LIMIT 40'
        );
        $stmt->execute([':q' => $like]);
        $hairstyles = array_map($normalizeHaircutRow, $stmt->fetchAll());
        json_response([
            'hairstyles' => $hairstyles,
            'query' => $query,
            'count' => count($hairstyles),
        ]);
    }

    if ($action === 'create') {
        // TODO: enforce admin role
        $haircutName = trim((string)($input['haircutName'] ?? ''));
        $faceShape = trim((string)($input['faceShape'] ?? ''));
        $imagePath = trim((string)($input['imagePath'] ?? ''));
        $isActive = isset($input['isActive']) ? (int)$input['isActive'] : 1;

        if ($haircutName === '') {
            json_response(['error' => 'haircutName is required'], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO haircuts (haircutName, faceShape, imagePath, isActive)
             VALUES (:haircutName, :faceShape, :imagePath, :isActive)'
        );
        $stmt->execute([
            ':haircutName' => $haircutName,
            ':faceShape' => $faceShape !== '' ? $faceShape : null,
            ':imagePath' => $imagePath !== '' ? $imagePath : null,
            ':isActive' => $isActive,
        ]);

        json_response(['message' => 'Haircut created', 'haircutID' => (int)$pdo->lastInsertId()], 201);
    }
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 500);
}
