<?php
declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/customer_auth.php';
require_once __DIR__ . '/face_scan_attach.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

if (!in_array($action, ['listByUser', 'save', 'delete', 'status'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

/**
 * Opt-in gallery of AI try-on previews the customer chose to keep.
 *
 * Deliberately separate from face_scan_previews: that table is the generation
 * cache, scoped to one scan session and invalidated when captures are retaken
 * (see invalidate_stale_previews_for_session). This one is a durable, user-owned
 * keepsake list -- deleting a row here never touches the underlying image, which
 * may still be serving that session's cache or an attached booking.
 */
function ensure_saved_previews_table(PDO $pdo): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS user_saved_previews (
            saved_preview_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            user_id BIGINT NOT NULL,
            variant_id BIGINT NOT NULL,
            scan_session_id VARCHAR(80) NOT NULL,
            style_name TEXT,
            front_url TEXT NOT NULL,
            left_url TEXT,
            right_url TEXT,
            face_shape TEXT,
            hair_texture TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )'
    );
    // Re-saving the same look from the same scan is a no-op rather than a
    // duplicate row.
    $pdo->exec(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_user_saved_preview
         ON user_saved_previews (user_id, variant_id, scan_session_id)'
    );
}

try {
    $pdo = get_db_connection();
    schema_ensure_once('user_saved_previews', static function () use ($pdo): void {
        ensure_saved_previews_table($pdo);
    });

    $customer = require_customer($pdo, $input);
    $userID = (int)$customer['user_id'];

    if ($action === 'listByUser') {
        $stmt = $pdo->prepare(
            'SELECT saved_preview_id, variant_id, scan_session_id, style_name,
                    front_url, left_url, right_url, face_shape, hair_texture, created_at
             FROM user_saved_previews
             WHERE user_id = :user_id
             ORDER BY created_at DESC'
        );
        $stmt->execute([':user_id' => $userID]);
        json_response(['savedPreviews' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
    }

    if ($action === 'delete') {
        $savedID = (int)($input['savedPreviewID'] ?? $input['savedPreviewId'] ?? 0);
        if ($savedID <= 0) {
            json_response(['error' => 'Invalid savedPreviewID'], 422);
        }
        // Scoped by user_id so one customer can never delete another's row.
        $stmt = $pdo->prepare(
            'DELETE FROM user_saved_previews
             WHERE saved_preview_id = :saved_preview_id AND user_id = :user_id'
        );
        $stmt->execute([':saved_preview_id' => $savedID, ':user_id' => $userID]);
        if ($stmt->rowCount() === 0) {
            json_response(['error' => 'Saved preview not found'], 404);
        }
        json_response(['message' => 'Removed']);
    }

    $variantID = (int)($input['variantID'] ?? $input['variantId'] ?? 0);
    $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
    if ($variantID <= 0 || $scanSessionId === '') {
        json_response(['error' => 'variantID and scanSessionId are required'], 422);
    }

    if ($action === 'status') {
        $stmt = $pdo->prepare(
            'SELECT saved_preview_id FROM user_saved_previews
             WHERE user_id = :user_id AND variant_id = :variant_id AND scan_session_id = :scan_session_id
             LIMIT 1'
        );
        $stmt->execute([
            ':user_id' => $userID,
            ':variant_id' => $variantID,
            ':scan_session_id' => $scanSessionId,
        ]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
        json_response([
            'isSaved' => $row !== false,
            'savedPreviewID' => isset($row['saved_preview_id']) ? (int)$row['saved_preview_id'] : null,
        ]);
    }

    // action === 'save'
    require_scan_session_access($pdo, $scanSessionId, $userID);

    $frontUrl = normalize_preview_relative_url((string)($input['frontViewUrl'] ?? ''));
    $leftUrl = normalize_preview_relative_url((string)($input['sideViewUrl'] ?? ''));
    $rightUrl = normalize_preview_relative_url((string)($input['backViewUrl'] ?? ''));

    // Never persist a path the client merely claims is a preview: it must be a
    // real file under this session's own folder. Without this, a crafted request
    // could park an arbitrary path in the gallery.
    if (!is_scan_session_preview_url($frontUrl, $scanSessionId)) {
        json_response(['error' => 'frontViewUrl is not a preview from this scan session'], 422);
    }
    foreach ([$leftUrl, $rightUrl] as $optional) {
        if ($optional !== '' && !is_scan_session_preview_url($optional, $scanSessionId)) {
            json_response(['error' => 'Preview URLs must belong to this scan session'], 422);
        }
    }

    $stmt = $pdo->prepare(
        'INSERT INTO user_saved_previews
            (user_id, variant_id, scan_session_id, style_name, front_url, left_url, right_url, face_shape, hair_texture)
         VALUES (:user_id, :variant_id, :scan_session_id, :style_name, :front_url, :left_url, :right_url, :face_shape, :hair_texture)
         ON CONFLICT (user_id, variant_id, scan_session_id) DO UPDATE
         SET front_url = EXCLUDED.front_url,
             left_url = EXCLUDED.left_url,
             right_url = EXCLUDED.right_url,
             style_name = COALESCE(EXCLUDED.style_name, user_saved_previews.style_name)
         RETURNING saved_preview_id'
    );
    $stmt->execute([
        ':user_id' => $userID,
        ':variant_id' => $variantID,
        ':scan_session_id' => $scanSessionId,
        ':style_name' => trim((string)($input['styleName'] ?? '')) ?: null,
        ':front_url' => $frontUrl,
        ':left_url' => $leftUrl !== '' ? $leftUrl : null,
        ':right_url' => $rightUrl !== '' ? $rightUrl : null,
        ':face_shape' => trim((string)($input['faceShape'] ?? '')) ?: null,
        ':hair_texture' => trim((string)($input['hairTexture'] ?? '')) ?: null,
    ]);

    json_response([
        'message' => 'Saved',
        'savedPreviewID' => (int)$stmt->fetchColumn(),
    ], 201);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
} catch (Throwable $e) {
    json_response(['error' => 'Error', 'details' => $e->getMessage()], 500);
}
