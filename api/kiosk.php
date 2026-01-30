<?php
// Kiosk API (selection flow)

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = $input['action'] ?? '';

if (!in_array($action, ['selectRecommendation', 'getSession'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

try {
    $pdo = get_db_connection();

    if ($action === 'selectRecommendation') {
        $sessionId = trim((string)($input['sessionID'] ?? ''));
        $recommendationId = (int)($input['recommendationID'] ?? 0);
        $selectedView = trim((string)($input['selectedView'] ?? 'Front'));

        if ($sessionId === '' || $recommendationId <= 0) {
            json_response(['error' => 'Missing sessionID or recommendationID'], 422);
        }

        $pdo->beginTransaction();

        $resetStmt = $pdo->prepare(
            'UPDATE kiosk_recommendations
             SET is_selected = 0
             WHERE session_id = :session_id'
        );
        $resetStmt->execute([':session_id' => $sessionId]);

        $selectStmt = $pdo->prepare(
            'UPDATE kiosk_recommendations
             SET is_selected = 1, selected_view = :selected_view
             WHERE recommendation_id = :recommendation_id AND session_id = :session_id'
        );
        $selectStmt->execute([
            ':selected_view' => $selectedView !== '' ? $selectedView : 'Front',
            ':recommendation_id' => $recommendationId,
            ':session_id' => $sessionId,
        ]);

        $pdo->commit();

        json_response(['message' => 'Selection updated']);
    }

    if ($action === 'getSession') {
        $sessionId = trim((string)($input['sessionID'] ?? ''));
        if ($sessionId === '') {
            json_response(['error' => 'Missing sessionID'], 422);
        }

        $sessionStmt = $pdo->prepare(
            'SELECT session_id, original_image_url, face_shape, hair_texture, hair_density, scan_timestamp, expires_at
             FROM kiosk_sessions
             WHERE session_id = :session_id'
        );
        $sessionStmt->execute([':session_id' => $sessionId]);
        $session = $sessionStmt->fetch();

        if (!$session) {
            json_response(['error' => 'Session not found'], 404);
        }

        $recStmt = $pdo->prepare(
            'SELECT kr.recommendation_id, kr.rank_position, kr.match_score, kr.is_selected, kr.selected_view,
                    hv.variant_id, hv.front_view_url, hv.side_view_url, hv.back_view_url,
                    hs.style_name, hs.style_code
             FROM kiosk_recommendations kr
             JOIN hairstyle_variants hv ON kr.variant_id = hv.variant_id
             JOIN hairstyles hs ON hv.hairstyle_id = hs.hairstyle_id
             WHERE kr.session_id = :session_id
             ORDER BY kr.rank_position ASC'
        );
        $recStmt->execute([':session_id' => $sessionId]);

        json_response([
            'session' => $session,
            'recommendations' => $recStmt->fetchAll(),
        ]);
    }
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
