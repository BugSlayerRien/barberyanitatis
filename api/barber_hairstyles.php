<?php
// Barber-authored hairstyles.
//
// The panel's objection was fair: the admin portal is the owner's, and the
// owner may not know haircuts. The barber does -- and the fields a barber uses
// to describe a cut at the chair (fade height, guard numbers, length on top,
// what happens at the back) are exactly the fields the image model needs. So
// the barber answers in their own terms, the server composes the AI prompt
// from those answers, and nobody has to write a prompt.
//
// Barbers have no portal login -- they authenticate through Supabase in the
// Flutter app -- which is why this is its own endpoint rather than an action on
// admin_hairstyles.php. A submission lands as PendingReview: the knowledge
// comes from the barber, the decision about what the shop sells stays with the
// owner.

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/hairstyle_authoring.php';
require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/schema_cache.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

if (!in_array($action, [
    'submitHairstyle', 'listMyHairstyles', 'deleteHairstyle', 'listTransitionChoices',
], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

/** Resolves the signed-in barber, email first, as barbers.php does. */
function barber_hairstyles_resolve_barber(PDO $pdo, int $barberId, string $email): array
{
    if ($email !== '') {
        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name FROM barbers
             WHERE lower(email) = lower(?) AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$email]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return ['id' => (int)$row['barber_id'], 'name' => (string)$row['full_name']];
        }
    }

    if ($barberId > 0) {
        $stmt = $pdo->prepare(
            'SELECT barber_id, full_name FROM barbers
             WHERE barber_id = ? AND is_active = TRUE LIMIT 1'
        );
        $stmt->execute([$barberId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($row) {
            return ['id' => (int)$row['barber_id'], 'name' => (string)$row['full_name']];
        }
    }

    return ['id' => 0, 'name' => ''];
}

/** Stores one uploaded reference photo, returning its relative path. */
function barber_hairstyle_store_photo(int $hairstyleId, string $slot, string $base64): string
{
    $raw = $base64;
    if (str_contains($raw, ',')) {
        $raw = substr($raw, (int)strpos($raw, ',') + 1);
    }
    $bytes = base64_decode($raw, true);
    if ($bytes === false || strlen($bytes) < 32) {
        throw new InvalidArgumentException('Invalid image data for ' . $slot);
    }

    $relative = 'uploads/hairstyles/style_' . $hairstyleId . '_' . $slot . '_' . time() . '.jpg';
    storage_put_bytes($relative, $bytes, 'image/jpeg');

    return $relative;
}

try {
    with_pdo_retry(function (PDO $pdo) use ($action, $input): void {
        ensure_hairstyle_authoring_columns($pdo);

        $barber = barber_hairstyles_resolve_barber(
            $pdo,
            (int)($input['barberID'] ?? $input['barberId'] ?? 0),
            strtolower(trim((string)($input['email'] ?? '')))
        );
        if ($barber['id'] <= 0) {
            json_response(['error' => 'Barber not found'], 404);
        }

        if ($action === 'listMyHairstyles') {
            $stmt = $pdo->prepare(
                "SELECT hs.hairstyle_id, hs.style_code, hs.style_name, hs.description,
                        hs.review_status, hs.created_at,
                        -- Published means it is the shop's catalogue now and may
                        -- already be booked, so only the owner may remove it.
                        (COALESCE(hs.review_status, 'Published') <> 'Published') AS can_delete,
                        COUNT(hv.variant_id)::int AS variant_count
                 FROM hairstyles hs
                 LEFT JOIN hairstyle_variants hv ON hv.hairstyle_id = hs.hairstyle_id
                 WHERE hs.authored_by_barber_id = :barber_id
                 GROUP BY hs.hairstyle_id
                 ORDER BY hs.created_at DESC"
            );
            $stmt->execute([':barber_id' => $barber['id']]);

            json_response(['hairstyles' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
        }

        // The cuts a barber can pick as "grows into this". Published only --
        // suggesting a customer get a style that is not in the catalogue yet
        // would be worse than suggesting nothing.
        if ($action === 'listTransitionChoices') {
            $stmt = $pdo->query(
                "SELECT style_code, style_name
                 FROM hairstyles
                 WHERE is_active = TRUE
                   AND COALESCE(review_status, 'Published') = 'Published'
                 ORDER BY style_name"
            );

            json_response(['styles' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
        }

        if ($action === 'deleteHairstyle') {
            $hairstyleId = (int)($input['hairstyleID'] ?? $input['hairstyleId'] ?? 0);
            if ($hairstyleId <= 0) {
                json_response(['error' => 'Invalid hairstyleID'], 422);
            }

            // Scoped to this barber's own rows: the id comes from the client,
            // so ownership is a WHERE clause, not an assumption.
            $own = $pdo->prepare(
                "SELECT hairstyle_id, style_name, style_code,
                        COALESCE(review_status, 'Published') AS review_status
                 FROM hairstyles
                 WHERE hairstyle_id = :id AND authored_by_barber_id = :barber_id
                 LIMIT 1"
            );
            $own->execute([':id' => $hairstyleId, ':barber_id' => $barber['id']]);
            $row = $own->fetch(PDO::FETCH_ASSOC);
            if (!$row) {
                json_response(['error' => 'That haircut is not one of your submissions.'], 404);
            }

            if ((string)$row['review_status'] === 'Published') {
                json_response([
                    'error' => 'This haircut is already published and customers can book it. '
                        . 'Ask the shop owner to remove it.',
                ], 409);
            }

            $pdo->beginTransaction();
            try {
                $pdo->prepare('DELETE FROM hairstyle_variants WHERE hairstyle_id = :id')
                    ->execute([':id' => $hairstyleId]);
                $pdo->prepare('DELETE FROM hairstyles WHERE hairstyle_id = :id')
                    ->execute([':id' => $hairstyleId]);

                audit_log($pdo, 'HAIRSTYLE_WITHDRAWN', 'hairstyles', (string)$hairstyleId, [
                    'style_name' => $row['style_name'],
                    'style_code' => $row['style_code'],
                    'review_status' => $row['review_status'],
                ], null, null, audit_actor_system('Barber ' . $barber['name']));

                $pdo->commit();
            } catch (Throwable $e) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                throw $e;
            }

            schema_cache_invalidate('overlay_library_catalog');

            json_response(['message' => 'Submission withdrawn.']);
        }

        // ---- submitHairstyle ------------------------------------------------
        $styleName = trim((string)($input['styleName'] ?? ''));
        if ($styleName === '') {
            json_response(['error' => 'A style name is required.'], 422);
        }

        $textures = array_values(array_filter(array_map(
            static fn($t): string => ucfirst(strtolower(trim((string)$t))),
            (array)($input['hairTextures'] ?? [])
        ), static fn(string $t): bool => in_array($t, ['Straight', 'Wavy', 'Curly'], true)));
        if ($textures === []) {
            json_response(['error' => 'Pick at least one hair texture this suits.'], 422);
        }

        // A barber who would rather describe the cut in their own words gets
        // the admin's single box instead of the structured questions. Same
        // destination -- one prompt on the row -- so nothing downstream cares
        // which door it came through.
        $freeText = trim((string)($input['aiPrompt'] ?? ''));

        $fields = [
            'sides' => (string)($input['sides'] ?? ''),
            'guards' => (string)($input['guards'] ?? ''),
            'top' => (string)($input['top'] ?? ''),
            'fringe' => (string)($input['fringe'] ?? ''),
            'back' => (string)($input['back'] ?? ''),
            'neckline' => (string)($input['neckline'] ?? ''),
            'finish' => (string)($input['finish'] ?? ''),
        ];
        if ($freeText === '') {
            // The two that carry the shape. Without them the composed prompt is
            // a style name and little else, which is the vagueness that
            // produced wrong haircuts before.
            if (trim($fields['sides']) === '' || trim($fields['top']) === '') {
                json_response([
                    'error' => 'Describe the sides and the length on top — those two decide the cut.',
                ], 422);
            }
        } elseif (preg_match('/\b(back|nape|collar)\b/i', $freeText) !== 1) {
            // The composer always states the back; free text has to say it
            // itself. An unsaid back is where the model invents length.
            json_response([
                'error' => 'Say what happens at the back — left unsaid, the AI invents length there.',
            ], 422);
        }

        // Photos are welcome, not required. Demanding all three turned away
        // barbers who had the knowledge but not a photo of every angle, and a
        // described cut is already usable: the app draws a placeholder tile
        // and the AI preview works from the description alone. Photos can be
        // added later through the portal and simply replace the placeholder.
        $photos = (array)($input['photos'] ?? []);

        $prompt = $freeText !== ''
            ? $freeText
            : compose_hairstyle_prompt($styleName, $fields);
        // Two barbers submitting "Wolf Cut" generated the same code, and the
        // second saw a raw uniqueness error. The name is checked outright; the
        // code, which they never chose, is suffixed instead of refused.
        $nameProblem = hairstyle_name_problem($pdo, $styleName);
        if ($nameProblem !== '') {
            json_response(['error' => $nameProblem], 422);
        }

        $styleCode = hairstyle_unique_code($pdo, hairstyle_code_from_name($styleName));

        $minLevel = max(0, min(3, (int)($input['minLengthLevel'] ?? 1)));
        $transition =
            strtoupper(trim((string)($input['transitionStyleCode'] ?? ''))) ?: null;

        // A cut needing medium or long hair has to name the one that grows
        // into it. Without a pairing the app offers "the longest cut you can
        // wear today", which is related to what the customer asked for by
        // nothing but length. A submission is new, so there is no built-in
        // default to fall back on -- the barber is the only one who can say.
        if ($minLevel >= 2 && $transition === null) {
            json_response([
                'error' => 'This cut needs medium or long hair, so pick the cut that '
                    . 'grows into it. Customers with shorter hair are offered that '
                    . 'one as the step towards this.',
            ], 422);
        }

        $pdo->beginTransaction();
        try {
            $insert = $pdo->prepare(
                "INSERT INTO hairstyles
                    (style_code, style_name, description, gender, difficulty, maintenance,
                     category, is_active, top_pick_eligible, ai_prompt, ai_min_length_level,
                     authored_by_barber_id, review_status, transition_style_code)
                 VALUES
                    (:style_code, :style_name, :description, 'Unisex', 'Medium', 'Medium',
                     'alternative', TRUE, TRUE, :ai_prompt, :min_level,
                     :barber_id, 'PendingReview', :transition_style_code)
                 RETURNING hairstyle_id"
            );
            $insert->execute([
                ':style_code' => $styleCode,
                ':style_name' => $styleName,
                ':description' => trim((string)($input['description'] ?? '')) ?: null,
                ':ai_prompt' => $prompt,
                ':min_level' => $minLevel,
                ':barber_id' => $barber['id'],
                // Only asked for when the style needs medium or long hair, so
                // it is empty for most submissions and stored as NULL.
                ':transition_style_code' => $transition,
            ]);
            $hairstyleId = (int)$insert->fetchColumn();

            $stored = ['front' => '', 'side' => '', 'back' => ''];
            foreach (['front', 'side', 'back'] as $slot) {
                $raw = trim((string)($photos[$slot] ?? ''));
                if ($raw === '') {
                    continue;
                }
                $stored[$slot] = barber_hairstyle_store_photo($hairstyleId, $slot, $raw);
            }

            // One variant per face shape per texture: the ranking matches both
            // exactly, so a style with a single variant is invisible to most
            // customers.
            $variantStmt = $pdo->prepare(
                'INSERT INTO hairstyle_variants (
                    hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url,
                    back_view_url, barber_instructions, clipper_sizes, styling_products,
                    estimated_minutes, confidence_score
                 ) VALUES (
                    :hairstyle_id, :face_shape, :hair_texture, :front, :side, :back,
                    :instructions, :clippers, :products, :minutes, 0.85
                 )'
            );
            foreach (['Oval', 'Round', 'Square'] as $faceShape) {
                foreach ($textures as $texture) {
                    $variantStmt->execute([
                        ':hairstyle_id' => $hairstyleId,
                        ':face_shape' => $faceShape,
                        ':hair_texture' => $texture,
                        ':front' => $stored['front'],
                        ':side' => $stored['side'],
                        ':back' => $stored['back'],
                        ':instructions' => trim((string)($input['barberInstructions'] ?? '')) ?: $prompt,
                        ':clippers' => trim((string)($input['guards'] ?? '')) ?: null,
                        ':products' => trim((string)($input['finish'] ?? '')) ?: null,
                        ':minutes' => max(10, (int)($input['estimatedMinutes'] ?? 40)),
                    ]);
                }
            }

            audit_log($pdo, 'HAIRSTYLE_SUBMITTED', 'hairstyles', (string)$hairstyleId, null, [
                'style_name' => $styleName,
                'style_code' => $styleCode,
                'barber_id' => $barber['id'],
                'textures' => $textures,
                'review_status' => 'PendingReview',
            ], null, audit_actor_system('Barber ' . $barber['name']));

            $pdo->commit();

            // A submission arrives unpublished, so it changes nothing a
            // customer sees yet -- but the catalog cache also keys on artwork
            // existing, and three photos just landed in storage.
            schema_cache_invalidate('overlay_library_catalog');

            json_response([
                'message' => 'Submitted for the shop owner to review.',
                'hairstyleID' => $hairstyleId,
                'styleCode' => $styleCode,
                'aiPrompt' => $prompt,
                'reviewStatus' => 'PendingReview',
                'hasPhotos' => $stored['front'] !== '',
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    });
} catch (PDOException $e) {
    error_log('barber_hairstyles: ' . $e->getMessage());
    json_response(['error' => hairstyle_friendly_db_error($e)], 503);
} catch (InvalidArgumentException $e) {
    json_response(['error' => $e->getMessage()], 422);
} catch (Throwable $e) {
    json_response(['error' => $e->getMessage()], 500);
}
