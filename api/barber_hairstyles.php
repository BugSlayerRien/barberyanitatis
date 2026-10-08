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

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

if (!in_array($action, ['submitHairstyle', 'listMyHairstyles'], true)) {
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

        $fields = [
            'sides' => (string)($input['sides'] ?? ''),
            'guards' => (string)($input['guards'] ?? ''),
            'top' => (string)($input['top'] ?? ''),
            'fringe' => (string)($input['fringe'] ?? ''),
            'back' => (string)($input['back'] ?? ''),
            'neckline' => (string)($input['neckline'] ?? ''),
            'finish' => (string)($input['finish'] ?? ''),
        ];
        // The two that carry the shape. Without them the composed prompt is a
        // style name and little else, which is the vagueness that produced
        // wrong haircuts before.
        if (trim($fields['sides']) === '' || trim($fields['top']) === '') {
            json_response([
                'error' => 'Describe the sides and the length on top — those two decide the cut.',
            ], 422);
        }

        $photos = (array)($input['photos'] ?? []);
        foreach (['front', 'side', 'back'] as $slot) {
            if (trim((string)($photos[$slot] ?? '')) === '') {
                json_response(['error' => 'Three reference photos are required: front, side and back.'], 422);
            }
        }

        $prompt = compose_hairstyle_prompt($styleName, $fields);
        $slug = preg_replace('/[^A-Z0-9]+/', '-', strtoupper($styleName)) ?? 'STYLE';
        $styleCode = substr('HC-' . trim($slug, '-'), 0, 20);

        $pdo->beginTransaction();
        try {
            $insert = $pdo->prepare(
                "INSERT INTO hairstyles
                    (style_code, style_name, description, gender, difficulty, maintenance,
                     category, is_active, top_pick_eligible, ai_prompt, ai_min_length_level,
                     authored_by_barber_id, review_status)
                 VALUES
                    (:style_code, :style_name, :description, 'Unisex', 'Medium', 'Medium',
                     'alternative', TRUE, TRUE, :ai_prompt, :min_level,
                     :barber_id, 'PendingReview')
                 RETURNING hairstyle_id"
            );
            $insert->execute([
                ':style_code' => $styleCode,
                ':style_name' => $styleName,
                ':description' => trim((string)($input['description'] ?? '')) ?: null,
                ':ai_prompt' => $prompt,
                ':min_level' => max(0, min(3, (int)($input['minLengthLevel'] ?? 1))),
                ':barber_id' => $barber['id'],
            ]);
            $hairstyleId = (int)$insert->fetchColumn();

            $stored = [];
            foreach (['front', 'side', 'back'] as $slot) {
                $stored[$slot] = barber_hairstyle_store_photo(
                    $hairstyleId,
                    $slot,
                    (string)$photos[$slot]
                );
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

            json_response([
                'message' => 'Submitted for the shop owner to review.',
                'hairstyleID' => $hairstyleId,
                'styleCode' => $styleCode,
                'aiPrompt' => $prompt,
                'reviewStatus' => 'PendingReview',
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $e;
        }
    });
} catch (PDOException $e) {
    json_response(db_error_response_payload($e), 503);
} catch (InvalidArgumentException $e) {
    json_response(['error' => $e->getMessage()], 422);
} catch (Throwable $e) {
    json_response(['error' => $e->getMessage()], 500);
}
