<?php
// Admin hairstyles API (list + CRUD + variant CRUD + overlay upload)

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/hairstyle_authoring.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/hairstyle_overlay_paths.php';
// ensure_top_pick_eligible_column() lives there because the recommendation
// ranking query needs the column too, not just this screen.
require_once __DIR__ . '/variant_ranking.php';
require_once __DIR__ . '/schema_cache.php';

const ADMIN_OVERLAY_MAX_BYTES = 5 * 1024 * 1024;

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';

/**
 * A style needing medium or long hair must say which cut grows into it.
 *
 * Without one the app falls back to "the longest cut you can wear today",
 * which is related to the style the customer actually wanted by nothing but
 * length. The curated pairings exist to replace exactly that.
 *
 * Resolved, not read raw: the built-in styles are paired in
 * hairstyle_transition_defaults(), so testing the column alone would refuse
 * every one of their saves.
 *
 * @param array<string, mixed> $row the row as it will be stored
 */
function admin_hairstyle_transition_problem(array $row): string
{
    if (hairstyle_min_length_level($row) < 2) {
        return '';
    }
    if (hairstyle_transition_code($row) !== null) {
        return '';
    }

    return 'A haircut needing medium or long hair must name the cut that grows '
        . 'into it, so customers with shorter hair are offered a real step '
        . 'towards it.';
}

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);

    schema_ensure_once('hairstyles.top_pick_eligible', static function () use ($pdo): void {
        ensure_top_pick_eligible_column($pdo);
    });
    schema_ensure_once('hairstyles.category', static function () use ($pdo): void {
        ensure_hairstyle_category_column($pdo);
    });

    // Category decides which Library section a cut appears in. It is stored per
    // style (see hairstyle_categories_and_catalog.sql) so a haircut cannot drift
    // between sections between requests.
    $normalizeCategory = static function ($raw): string {
        $value = strtolower(trim((string)$raw));
        return in_array($value, ['formal', 'alternative'], true) ? $value : 'alternative';
    };

    // Absent means eligible: a client that does not send the field (an older
    // admin build) must not silently drop styles out of Top picks.
    $normalizeTopPickEligible = static function ($raw): bool {
        if ($raw === null) {
            return true;
        }
        if (is_bool($raw)) {
            return $raw;
        }
        return !in_array(strtolower(trim((string)$raw)), ['0', 'false', 'no', ''], true);
    };

    if ($method === 'GET') {
        $stmt = $pdo->query(<<<'SQL'
            SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description,
                   hs.gender, hs.difficulty, hs.maintenance, hs.category, hs.is_active,
                   hs.top_pick_eligible, hs.created_at,
                   -- The review workflow was invisible here: a barber could
                   -- submit a style and the owner had no row to act on.
                   COALESCE(hs.review_status, 'Published') AS review_status,
                   hs.ai_min_length_level, hs.transition_style_code,
                   hs.ai_prompt,
                   hs.authored_by_barber_id,
                   b.full_name AS authored_by_name,
                   COUNT(hv.variant_id) AS variant_count,
                   -- Textures live on the variants, not the style. Aggregate them
                   -- so the admin list can filter by texture without a second query.
                   -- Nowdoc, not a single-quoted string: the ',' separator below
                   -- would otherwise close the string and become a second
                   -- argument to PDO::query().
                   STRING_AGG(DISTINCT hv.hair_texture, ',') AS hair_textures
              FROM hairstyles hs
              LEFT JOIN hairstyle_variants hv ON hv.hairstyle_id = hs.hairstyle_id
              LEFT JOIN barbers b ON b.barber_id = hs.authored_by_barber_id
             GROUP BY hs.hairstyle_id, hs.style_code, hs.style_name, hs.description,
                      hs.gender, hs.difficulty, hs.maintenance, hs.category, hs.is_active,
                      hs.top_pick_eligible, hs.created_at, hs.review_status,
                      hs.ai_min_length_level, hs.transition_style_code, hs.ai_prompt,
                      hs.authored_by_barber_id,
                      b.full_name
             ORDER BY hs.style_name
            SQL
        );
        $rows = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $normalized = apply_hairstyle_overlay_paths($row);
            $overlayInfo = overlay_paths_for_hairstyle($row);
            $normalized['overlay_folder'] = $overlayInfo['folder'] ?? ($normalized['overlay_folder'] ?? null);
            $normalized['has_overlay_assets'] = hairstyle_overlay_files_exist($normalized);
            // Derived, not asked of SQL. The column is NULL on the styles that
            // shipped with the app, whose prompt lives in
            // replicate_style_prompts(), so the old `ai_prompt <> ''` test
            // badged all 32 of them "Not usable".
            $normalized['has_prompt'] = hairstyle_ai_prompt($normalized) !== '';
            $normalized['min_length_level'] = hairstyle_min_length_level($normalized);
            // The prompt is the image model's instructions, not the admin
            // list's business; the editor fetches it per style.
            unset($normalized['ai_prompt']);
            $rows[] = $normalized;
        }

        json_response(['hairstyles' => $rows]);
    }

    if ($method === 'POST' && isset($_POST['action']) && (string)$_POST['action'] === 'uploadOverlay') {
        handle_upload_overlay($pdo);
    }

    if ($method !== 'POST') {
        json_response(['error' => 'Method not allowed'], 405);
    }

    $input = get_json_input();
    $action = trim((string)($input['action'] ?? ''));

    if ($action === 'get') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        if ($hairstyleID <= 0) {
            json_response(['error' => 'Invalid hairstyleID'], 422);
        }

        $stmt = $pdo->prepare(
            "SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description, hs.gender,
                    hs.difficulty, hs.maintenance, hs.category, hs.is_active, hs.top_pick_eligible,
                    hs.created_at, hs.ai_prompt, hs.ai_min_length_level,
                    hs.transition_style_code,
                    COALESCE(hs.review_status, 'Published') AS review_status,
                    hs.authored_by_barber_id, b.full_name AS authored_by_name
             FROM hairstyles hs
             LEFT JOIN barbers b ON b.barber_id = hs.authored_by_barber_id
             WHERE hs.hairstyle_id = :id LIMIT 1"
        );
        $stmt->execute([':id' => $hairstyleID]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            json_response(['error' => 'Hairstyle not found'], 404);
        }

        $hairstyle = apply_hairstyle_overlay_paths($row);
        $overlayInfo = overlay_paths_for_hairstyle($row);
        $hairstyle['overlay_folder'] = $overlayInfo['folder'] ?? ($hairstyle['overlay_folder'] ?? null);
        $hairstyle['has_overlay_assets'] = hairstyle_overlay_files_exist($hairstyle);

        $variantStmt = $pdo->prepare(
            'SELECT variant_id, hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
                    barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
             FROM hairstyle_variants
             WHERE hairstyle_id = :id
             ORDER BY face_shape, hair_texture'
        );
        $variantStmt->execute([':id' => $hairstyleID]);

        // What the generator will really use, so the editor shows it rather
        // than an empty box. The column is NULL on the 32 styles that shipped
        // with the app -- their prompt and minimum length live in
        // replicate_helper.php -- and the portal refused to save any edit to
        // them because the box looked blank.
        $hairstyle['ai_prompt_effective'] = hairstyle_ai_prompt($row);
        $hairstyle['ai_prompt_source'] = hairstyle_ai_prompt_source($row);
        $hairstyle['min_length_level'] = hairstyle_min_length_level($row);
        $hairstyle['min_length_source'] =
            ($row['ai_min_length_level'] ?? null) !== null
            && (string)$row['ai_min_length_level'] !== ''
                ? 'stored'
                : 'builtin';
        $hairstyle['transition_style_code_effective'] =
            hairstyle_transition_code($row);

        json_response([
            'hairstyle' => $hairstyle,
            'variants' => $variantStmt->fetchAll(PDO::FETCH_ASSOC),
        ]);
    }

    if ($action === 'create') {
        $styleName = trim((string)($input['styleName'] ?? ''));
        $styleCode = trim((string)($input['styleCode'] ?? ''));
        if ($styleName === '') {
            json_response(['error' => 'styleName is required'], 422);
        }

        ensure_hairstyle_authoring_columns($pdo);

        // Checked before the insert rather than left to the UNIQUE constraint,
        // which answered with a raw Postgres message and an HTTP 500.
        $nameProblem = hairstyle_name_problem($pdo, $styleName);
        if ($nameProblem !== '') {
            json_response(['error' => $nameProblem], 422);
        }

        if ($styleCode === '') {
            $styleCode = hairstyle_unique_code($pdo, hairstyle_code_from_name($styleName));
        } else {
            $codeProblem = hairstyle_code_problem($pdo, $styleCode);
            if ($codeProblem !== '') {
                json_response(['error' => $codeProblem], 422);
            }
            $styleCode = strtoupper(trim($styleCode));
        }
        $minLevel = max(0, min(3, (int)($input['aiMinLengthLevel'] ?? 1)));
        $transition =
            strtoupper(trim((string)($input['transitionStyleCode'] ?? ''))) ?: null;

        $transitionProblem = admin_hairstyle_transition_problem([
            'style_name' => $styleName,
            'style_code' => $styleCode,
            'ai_min_length_level' => $minLevel,
            'transition_style_code' => $transition,
        ]);
        if ($transitionProblem !== '') {
            json_response(['error' => $transitionProblem], 422);
        }

        $stmt = $pdo->prepare(
            'INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, category, is_active, top_pick_eligible, ai_prompt, ai_min_length_level, transition_style_code)
             VALUES (:style_code, :style_name, :description, :gender, :difficulty, :maintenance, :category, :is_active, :top_pick_eligible, :ai_prompt, :ai_min_length_level, :transition_style_code)
             RETURNING hairstyle_id'
        );
        $stmt->execute([
            ':style_code' => $styleCode,
            ':style_name' => $styleName,
            ':description' => trim((string)($input['description'] ?? '')) ?: null,
            ':gender' => normalize_hairstyle_gender($input['gender'] ?? 'Unisex'),
            ':difficulty' => normalize_hairstyle_tier($input['difficulty'] ?? 'Medium', ['Easy', 'Medium', 'Hard']),
            ':maintenance' => normalize_hairstyle_tier($input['maintenance'] ?? 'Medium', ['Low', 'Medium', 'High']),
            ':category' => $normalizeCategory($input['category'] ?? 'alternative'),
            ':is_active' => (int)(!empty($input['isActive']) && (string)$input['isActive'] !== '0'),
            ':top_pick_eligible' => (int)$normalizeTopPickEligible($input['topPickEligible'] ?? null),
            // Without a prompt the style can be saved but never previewed, so
            // the field belongs on the same form as the name.
            ':ai_prompt' => trim((string)($input['aiPrompt'] ?? '')) ?: null,
            ':ai_min_length_level' => $minLevel,
            // Only meaningful for a style needing more than short hair; the
            // portal hides the field otherwise. Empty stores as NULL so the
            // built-in defaults still apply.
            ':transition_style_code' =>
                strtoupper(trim((string)($input['transitionStyleCode'] ?? ''))) ?: null,
        ]);

        // Which styles qualify for the customer catalog is cached for
        // five minutes. Without this the portal would say "saved" and the
        // app would keep serving the old catalog -- which at a live demo is
        // indistinguishable from the save not working.
        schema_cache_invalidate('overlay_library_catalog');

        json_response([
            'message' => 'Hairstyle created',
            'hairstyleID' => (int)$stmt->fetchColumn(),
        ]);
    }

    if ($action === 'update') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        $styleName = trim((string)($input['styleName'] ?? ''));
        if ($hairstyleID <= 0 || $styleName === '') {
            json_response(['error' => 'Invalid hairstyle payload'], 422);
        }

        // Same checks on edit, excluding this row so a style can keep its own
        // name and code.
        $nameProblem = hairstyle_name_problem($pdo, $styleName, $hairstyleID);
        if ($nameProblem !== '') {
            json_response(['error' => $nameProblem], 422);
        }

        $styleCode = trim((string)($input['styleCode'] ?? ''));
        if ($styleCode !== '') {
            $codeProblem = hairstyle_code_problem($pdo, $styleCode, $hairstyleID);
            if ($codeProblem !== '') {
                json_response(['error' => $codeProblem], 422);
            }
            $styleCode = strtoupper($styleCode);
        }

        // The name and code the row will carry, which is what the built-in
        // tables are keyed on. An edit that renames a style must resolve
        // against the new name, not the one on disk.
        $identity = [
            'style_name' => $styleName,
            'style_code' => $styleCode !== ''
                ? $styleCode
                : (string)$pdo->query(
                    'SELECT style_code FROM hairstyles WHERE hairstyle_id = '
                    . $hairstyleID
                )->fetchColumn(),
        ];

        // Stored only when it differs from the built-in description. Opening a
        // style and pressing Save must not fork it from
        // replicate_style_prompts(), which is version-controlled, tested and
        // improved from time to time; only a real edit should.
        $submittedPrompt = trim((string)($input['aiPrompt'] ?? ''));
        $builtinPrompt = hairstyle_ai_prompt(
            $identity + ['ai_prompt' => null]
        );
        $storedPrompt = ($submittedPrompt === '' || $submittedPrompt === $builtinPrompt)
            ? null
            : $submittedPrompt;

        // Same rule, and here it also repairs a silent downgrade: the portal
        // showed "1 - short" for every style whose column was NULL and wrote
        // that number back, so saving Modern Mullet to change its category
        // dropped it from medium to short and switched off its length
        // warning, its grow-out badge and its transition cut.
        $submittedLevel = max(0, min(3, (int)($input['aiMinLengthLevel'] ?? 1)));
        $builtinLevel = hairstyle_builtin_min_length_level($identity);
        $storedLevel = $submittedLevel === $builtinLevel ? null : $submittedLevel;

        $transition =
            strtoupper(trim((string)($input['transitionStyleCode'] ?? ''))) ?: null;

        $transitionProblem = admin_hairstyle_transition_problem($identity + [
            'ai_min_length_level' => $storedLevel,
            'transition_style_code' => $transition,
        ]);
        if ($transitionProblem !== '') {
            json_response(['error' => $transitionProblem], 422);
        }

        $sql = 'UPDATE hairstyles
                SET style_name = :style_name,
                    description = :description,
                    gender = :gender,
                    difficulty = :difficulty,
                    maintenance = :maintenance,
                    category = :category,
                    is_active = :is_active,
                    top_pick_eligible = :top_pick_eligible,
                    ai_prompt = :ai_prompt,
                    ai_min_length_level = :ai_min_length_level,
                    transition_style_code = :transition_style_code';
        $params = [
            ':style_name' => $styleName,
            ':description' => trim((string)($input['description'] ?? '')) ?: null,
            ':gender' => normalize_hairstyle_gender($input['gender'] ?? 'Unisex'),
            ':difficulty' => normalize_hairstyle_tier($input['difficulty'] ?? 'Medium', ['Easy', 'Medium', 'Hard']),
            ':maintenance' => normalize_hairstyle_tier($input['maintenance'] ?? 'Medium', ['Low', 'Medium', 'High']),
            ':category' => $normalizeCategory($input['category'] ?? 'alternative'),
            ':is_active' => (int)(!empty($input['isActive']) && (string)$input['isActive'] !== '0'),
            ':top_pick_eligible' => (int)$normalizeTopPickEligible($input['topPickEligible'] ?? null),
            ':ai_prompt' => $storedPrompt,
            ':ai_min_length_level' => $storedLevel,
            ':transition_style_code' => $transition,
            ':id' => $hairstyleID,
        ];

        if ($styleCode !== '') {
            $sql .= ', style_code = :style_code';
            $params[':style_code'] = $styleCode;
        }
        $sql .= ' WHERE hairstyle_id = :id';

        $pdo->prepare($sql)->execute($params);
        schema_cache_invalidate('overlay_library_catalog');
        json_response(['message' => 'Hairstyle updated']);
    }

    // Deactivation, not deletion: past scans and saved looks point at the
    // hairstyle, and a customer's history should not change shape because the
    // shop stopped offering the style.
    /**
     * Publish or reject a barber's submission.
     *
     * Publishing is refused while the style would not actually appear, because
     * the alternative is what the panel found: a row that saves cleanly, looks
     * fine in the list, and silently never reaches a customer.
     */
    if ($action === 'reviewHairstyle') {
        ensure_hairstyle_authoring_columns($pdo);
        $hairstyleID = (int)($input['hairstyleID'] ?? 0);
        $decision = trim((string)($input['decision'] ?? ''));
        if ($hairstyleID <= 0 || !in_array($decision, ['Published', 'Rejected'], true)) {
            json_response(['error' => 'Invalid hairstyleID or decision'], 422);
        }

        $styleStmt = $pdo->prepare('SELECT * FROM hairstyles WHERE hairstyle_id = :id LIMIT 1');
        $styleStmt->execute([':id' => $hairstyleID]);
        $style = $styleStmt->fetch(PDO::FETCH_ASSOC);
        if (!$style) {
            json_response(['error' => 'Hairstyle not found'], 404);
        }

        if ($decision === 'Published') {
            $variantStmt = $pdo->prepare(
                'SELECT * FROM hairstyle_variants WHERE hairstyle_id = :id'
            );
            $variantStmt->execute([':id' => $hairstyleID]);
            $problems = hairstyle_readiness_problems($style, $variantStmt->fetchAll(PDO::FETCH_ASSOC));
            if ($problems !== []) {
                json_response([
                    'error' => 'This style is not ready to publish.',
                    'problems' => $problems,
                ], 422);
            }
        }

        $pdo->prepare('UPDATE hairstyles SET review_status = :status WHERE hairstyle_id = :id')
            ->execute([':status' => $decision, ':id' => $hairstyleID]);

        audit_log($pdo, 'HAIRSTYLE_' . strtoupper($decision), 'hairstyles', (string)$hairstyleID, [
            'review_status' => $style['review_status'] ?? null,
        ], [
            'review_status' => $decision,
            'style_name' => $style['style_name'] ?? '',
        ], null);

        schema_cache_invalidate('overlay_library_catalog');

        json_response([
            'message' => $decision === 'Published'
                ? 'Hairstyle published — it is now visible in the app.'
                : 'Hairstyle rejected.',
            'reviewStatus' => $decision,
        ]);
    }

    /** What still stands between this style and a customer seeing it. */
    if ($action === 'readiness') {
        ensure_hairstyle_authoring_columns($pdo);
        $hairstyleID = (int)($input['hairstyleID'] ?? 0);
        if ($hairstyleID <= 0) {
            json_response(['error' => 'Invalid hairstyleID'], 422);
        }

        $styleStmt = $pdo->prepare('SELECT * FROM hairstyles WHERE hairstyle_id = :id LIMIT 1');
        $styleStmt->execute([':id' => $hairstyleID]);
        $style = $styleStmt->fetch(PDO::FETCH_ASSOC);
        if (!$style) {
            json_response(['error' => 'Hairstyle not found'], 404);
        }

        $variantStmt = $pdo->prepare('SELECT * FROM hairstyle_variants WHERE hairstyle_id = :id');
        $variantStmt->execute([':id' => $hairstyleID]);
        $variants = $variantStmt->fetchAll(PDO::FETCH_ASSOC);
        $problems = hairstyle_readiness_problems($style, $variants);

        json_response([
            'ready' => $problems === [],
            'problems' => $problems,
            'warnings' => hairstyle_readiness_warnings($style, $variants),
            'reviewStatus' => $style['review_status'] ?? 'Published',
        ]);
    }

    if ($action === 'delete' || $action === 'restore') {
        $hairstyleID = (int)($input['hairstyleID'] ?? $input['hairstyle_id'] ?? 0);
        if ($hairstyleID <= 0) {
            json_response(['error' => 'Invalid hairstyleID'], 422);
        }

        $activate = $action === 'restore';
        $stmt = $pdo->prepare(
            'UPDATE hairstyles SET is_active = :is_active WHERE hairstyle_id = :id
             RETURNING hairstyle_id, style_name, style_code, is_active'
        );
        $stmt->execute([':is_active' => (int)$activate, ':id' => $hairstyleID]);
        $updated = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$updated) {
            json_response(['error' => 'Hairstyle not found'], 404);
        }

        audit_log(
            $pdo,
            $activate ? 'HAIRSTYLE_RESTORE' : 'HAIRSTYLE_DEACTIVATE',
            'hairstyles',
            (string)$hairstyleID,
            null,
            $updated,
            null
        );

        schema_cache_invalidate('overlay_library_catalog');
        json_response(['message' => $activate ? 'Hairstyle reactivated' : 'Hairstyle deactivated']);
    }

    if ($action === 'createVariant') {
        $hairstyleID = (int)($input['hairstyleID'] ?? 0);
        $faceShape = trim((string)($input['faceShape'] ?? 'Oval'));
        $hairTexture = trim((string)($input['hairTexture'] ?? 'Straight'));
        if ($hairstyleID <= 0) {
            json_response(['error' => 'hairstyleID is required'], 422);
        }

        // Uploaded artwork wins over the bundled map. Without this the NOT
        // NULL front_view_url was filled with '' for any style that is not one
        // of the built-ins, which satisfies the constraint and fails every
        // catalog check -- the style saved cleanly and was never visible.
        $paths = variant_overlay_paths_for_hairstyle($pdo, $hairstyleID);
        foreach (['front' => 'frontViewUrl', 'side' => 'sideViewUrl', 'back' => 'backViewUrl'] as $slot => $field) {
            $supplied = trim((string)($input[$field] ?? ''));
            if ($supplied !== '') {
                $paths[$slot] = $supplied;
            }
        }
        $stmt = $pdo->prepare(
            'INSERT INTO hairstyle_variants (
                hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url,
                barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score
             ) VALUES (
                :hairstyle_id, :face_shape, :hair_texture, :front_view_url, :side_view_url, :back_view_url,
                :barber_instructions, :clipper_sizes, :styling_products, :estimated_minutes, :confidence_score
             )
             RETURNING variant_id'
        );
        $stmt->execute([
            ':hairstyle_id' => $hairstyleID,
            ':face_shape' => $faceShape,
            ':hair_texture' => normalize_hair_texture($hairTexture),
            ':front_view_url' => $paths['front'] ?? '',
            ':side_view_url' => $paths['side'] ?? '',
            ':back_view_url' => $paths['back'] ?? '',
            ':barber_instructions' => trim((string)($input['barberInstructions'] ?? 'Standard finish.')),
            ':clipper_sizes' => trim((string)($input['clipperSizes'] ?? '0.5, 1, 2')),
            ':styling_products' => trim((string)($input['stylingProducts'] ?? 'Matte clay')),
            ':estimated_minutes' => max(10, (int)($input['estimatedMinutes'] ?? 40)),
            ':confidence_score' => (float)($input['confidenceScore'] ?? 0.85),
        ]);

        schema_cache_invalidate('overlay_library_catalog');

        json_response([
            'message' => 'Variant created',
            'variantID' => (int)$stmt->fetchColumn(),
        ]);
    }

    if ($action === 'updateVariant') {
        $variantID = (int)($input['variantID'] ?? 0);
        if ($variantID <= 0) {
            json_response(['error' => 'variantID is required'], 422);
        }

        $pdo->prepare(
            'UPDATE hairstyle_variants
             SET face_shape = :face_shape,
                 hair_texture = :hair_texture,
                 barber_instructions = :barber_instructions,
                 clipper_sizes = :clipper_sizes,
                 styling_products = :styling_products,
                 estimated_minutes = :estimated_minutes,
                 confidence_score = :confidence_score
             WHERE variant_id = :variant_id'
        )->execute([
            ':face_shape' => trim((string)($input['faceShape'] ?? 'Oval')),
            ':hair_texture' => normalize_hair_texture((string)($input['hairTexture'] ?? 'Straight')),
            ':barber_instructions' => trim((string)($input['barberInstructions'] ?? '')),
            ':clipper_sizes' => trim((string)($input['clipperSizes'] ?? '')),
            ':styling_products' => trim((string)($input['stylingProducts'] ?? '')),
            ':estimated_minutes' => max(10, (int)($input['estimatedMinutes'] ?? 40)),
            ':confidence_score' => (float)($input['confidenceScore'] ?? 0.85),
            ':variant_id' => $variantID,
        ]);

        schema_cache_invalidate('overlay_library_catalog');
        json_response(['message' => 'Variant updated']);
    }

    if ($action === 'deleteVariant') {
        $variantID = (int)($input['variantID'] ?? 0);
        if ($variantID <= 0) {
            json_response(['error' => 'variantID is required'], 422);
        }

        $pdo->prepare('DELETE FROM hairstyle_variants WHERE variant_id = :id')
            ->execute([':id' => $variantID]);

        schema_cache_invalidate('overlay_library_catalog');
        json_response(['message' => 'Variant deleted']);
    }

    json_response(['error' => 'Invalid action'], 400);
} catch (PDOException $e) {
    // The message carries table and constraint names, which the browser has no
    // business seeing. Logged in full, summarised to the client.
    error_log('admin_hairstyles: ' . $e->getMessage());
    json_response(['error' => hairstyle_friendly_db_error($e)], 500);
} catch (Throwable $e) {
    error_log('admin_hairstyles: ' . $e->getMessage());
    json_response(['error' => 'Something went wrong saving that haircut.'], 500);
}

function normalize_hairstyle_gender(string $value): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    return in_array($normalized, ['Male', 'Female', 'Unisex'], true) ? $normalized : 'Unisex';
}

/**
 * @param list<string> $allowed
 */
function normalize_hairstyle_tier(string $value, array $allowed): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    return in_array($normalized, $allowed, true) ? $normalized : $allowed[1];
}

function normalize_hair_texture(string $value): string
{
    $normalized = ucfirst(strtolower(trim($value)));
    if ($normalized === 'Coily') {
        return 'Curly';
    }
    return in_array($normalized, ['Straight', 'Wavy', 'Curly'], true) ? $normalized : 'Straight';
}

/**
 * @return array{front?: string, side?: string, back?: string}
 */
function variant_overlay_paths_for_hairstyle(PDO $pdo, int $hairstyleId): array
{
    $stmt = $pdo->prepare(
        'SELECT style_name, style_code FROM hairstyles WHERE hairstyle_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $hairstyleId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return [];
    }

    $paths = overlay_paths_for_hairstyle($row);

    return $paths ?? [];
}

function handle_upload_overlay(PDO $pdo): void
{
    $hairstyleID = (int)($_POST['hairstyleID'] ?? $_POST['hairstyle_id'] ?? 0);
    $view = trim((string)($_POST['view'] ?? ''));
    $folderOverride = trim((string)($_POST['overlayFolder'] ?? ''));

    if ($hairstyleID <= 0 || $view === '') {
        json_response(['error' => 'hairstyleID and view are required'], 422);
    }

    if (!isset($_FILES['file']) || !is_uploaded_file($_FILES['file']['tmp_name'] ?? '')) {
        json_response(['error' => 'PNG file is required'], 422);
    }

    $file = $_FILES['file'];
    if (($file['error'] ?? UPLOAD_ERR_OK) !== UPLOAD_ERR_OK) {
        json_response(['error' => 'Upload failed'], 422);
    }

    if ((int)($file['size'] ?? 0) > ADMIN_OVERLAY_MAX_BYTES) {
        json_response(['error' => 'File exceeds 5MB limit'], 422);
    }

    // A bundled scanner overlay has to be a transparent PNG cut-out. A
    // reference photo for a new style does not -- insisting on PNG meant an
    // admin with three JPEGs of a haircut had no way to add it.
    $mime = mime_content_type($file['tmp_name']) ?: '';
    $allowedMimes = [
        'image/png' => 'png',
        'image/x-png' => 'png',
        'image/jpeg' => 'jpg',
        'image/jpg' => 'jpg',
        'image/webp' => 'webp',
    ];
    if (!isset($allowedMimes[$mime])) {
        json_response(['error' => 'Upload a PNG, JPEG or WebP image'], 422);
    }
    $extension = $allowedMimes[$mime];

    $stmt = $pdo->prepare(
        'SELECT style_name, style_code FROM hairstyles WHERE hairstyle_id = :id LIMIT 1'
    );
    $stmt->execute([':id' => $hairstyleID]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    $styleName = (string)($row['style_name'] ?? '');
    $styleCode = (string)($row['style_code'] ?? '');
    if ($styleName === '' && $styleCode === '') {
        json_response(['error' => 'Hairstyle not found'], 404);
    }

    $viewSlot = match (strtolower($view)) {
        'front' => 'front',
        'left', 'side' => 'left',
        'right', 'back' => 'right',
        default => 'front',
    };

    $bytes = file_get_contents($file['tmp_name']);
    if ($bytes === false || $bytes === '') {
        json_response(['error' => 'Could not read overlay file'], 500);
    }

    $target = overlay_target_for_view($styleName, $view, $styleCode);
    $folder = null;

    if ($target === null) {
        // The style is not one of the bundled 24, so there is no overlay slot
        // to replace. This used to be written to assets/images/overlays/<new
        // folder>/ and that path stored as the URL -- but anything starting
        // with `assets/` is a *bundled Flutter asset*, and a folder created on
        // the server is in neither the APK nor pubspec.yaml. The upload
        // succeeded and the picture could never load. Uploads for new styles
        // belong in storage and are served over the network, the same place
        // barber_hairstyles.php puts them.
        $assetPath = sprintf(
            'uploads/hairstyles/style_%d_%s_%d.%s',
            $hairstyleID,
            $viewSlot,
            time(),
            $extension
        );
        storage_put_bytes($assetPath, $bytes, $mime);
    } else {
        $folder = $target['folder'];
        $filename = $target['filename'];
        $dir = mobile_app_overlay_root() . '/' . $folder;
        $dest = $dir . '/' . $filename;
        $assetPath = 'assets/images/overlays/' . $folder . '/' . $filename;
        $wroteLocal = false;
        if (!is_dir($dir) && !mkdir($dir, 0775, true) && !is_dir($dir)) {
            if (storage_driver() !== 'supabase') {
                json_response(['error' => 'Could not create overlay directory'], 500);
            }
        } else {
            $wroteLocal = file_put_contents($dest, $bytes) !== false;
            if (!$wroteLocal && storage_driver() !== 'supabase') {
                json_response(['error' => 'Could not save overlay file'], 500);
            }
        }

        if (storage_driver() === 'supabase') {
            storage_put_bytes($assetPath, $bytes, $mime);
        } elseif (!$wroteLocal) {
            json_response(['error' => 'Could not save overlay file'], 500);
        }
    }
    $column = match (strtolower($view)) {
        'front' => 'front_view_url',
        'left', 'side' => 'side_view_url',
        'right', 'back' => 'back_view_url',
        default => null,
    };

    if ($column !== null) {
        $allowedColumns = [
            'front_view_url' => 'front_view_url',
            'side_view_url' => 'side_view_url',
            'back_view_url' => 'back_view_url',
        ];
        $safeColumn = $allowedColumns[$column] ?? null;
        if ($safeColumn !== null) {
            $pdo->prepare(
                "UPDATE hairstyle_variants SET {$safeColumn} = :path WHERE hairstyle_id = :hairstyle_id"
            )->execute([
                ':path' => $assetPath,
                ':hairstyle_id' => $hairstyleID,
            ]);
        }
    }

    // Whether this style qualifies for the catalog may have just changed.
    schema_cache_invalidate('overlay_library_catalog');

    json_response([
        'message' => 'Overlay uploaded',
        'path' => $assetPath,
        'folder' => $folder,
        'filename' => basename($assetPath),
    ]);
}
