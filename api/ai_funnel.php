<?php
// AI funnel tracking and personalization persistence API

declare(strict_types=1);
require_once __DIR__ . '/db.php';

require_method('POST');

$input = get_json_input();
$action = trim((string)($input['action'] ?? ''));

if (!in_array($action, ['trackScan', 'saveSelection', 'trackBookingCreated'], true)) {
    json_response(['error' => 'Invalid action'], 400);
}

function normalize_face_shape(?string $value): ?string
{
    if ($value === null) {
        return null;
    }
    $value = trim($value);
    if ($value === '') {
        return null;
    }
    $allowed = ['Oval', 'Round', 'Square', 'Heart', 'Diamond', 'Oblong'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return null;
}

function normalize_hair_texture(?string $value): ?string
{
    if ($value === null) {
        return null;
    }
    $value = trim($value);
    if ($value === '') {
        return null;
    }
    $allowed = ['Straight', 'Wavy', 'Curly', 'Coily'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return null;
}

function normalize_hair_density(?string $value): ?string
{
    if ($value === null) {
        return null;
    }
    $value = trim($value);
    if ($value === '') {
        return null;
    }
    $allowed = ['Thin', 'Medium', 'Thick'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return null;
}

function normalize_hair_length(?string $value): ?string
{
    if ($value === null) {
        return null;
    }
    $value = trim($value);
    if ($value === '') {
        return null;
    }
    $allowed = ['Short', 'Medium', 'Long'];
    foreach ($allowed as $item) {
        if (strcasecmp($item, $value) === 0) {
            return $item;
        }
    }
    return null;
}

function ensure_ai_funnel_tables(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS user_style_preferences (
            user_id BIGINT PRIMARY KEY,
            preferred_variant_id BIGINT,
            preferred_style_name VARCHAR(120),
            last_face_shape VARCHAR(50),
            last_hair_texture TEXT,
            last_hair_density TEXT,
            last_hair_length TEXT,
            selection_count INT NOT NULL DEFAULT 0,
            last_selected_at TIMESTAMPTZ,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_user_style_preferences_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
            CONSTRAINT fk_user_style_preferences_variant FOREIGN KEY (preferred_variant_id) REFERENCES hairstyle_variants(variant_id)
        )"
    );

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS ai_recommendation_events (
            event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            user_id BIGINT,
            scan_session_id VARCHAR(80),
            event_type VARCHAR(40) NOT NULL,
            variant_id BIGINT,
            style_name VARCHAR(120),
            service_id BIGINT,
            estimated_minutes INT,
            appointment_id BIGINT,
            face_shape VARCHAR(50),
            hair_texture TEXT,
            hair_density TEXT,
            hair_length TEXT,
            metadata JSONB,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            CONSTRAINT fk_ai_event_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,
            CONSTRAINT fk_ai_event_variant FOREIGN KEY (variant_id) REFERENCES hairstyle_variants(variant_id) ON DELETE SET NULL,
            CONSTRAINT fk_ai_event_service FOREIGN KEY (service_id) REFERENCES services(service_id) ON DELETE SET NULL,
            CONSTRAINT fk_ai_event_appointment FOREIGN KEY (appointment_id) REFERENCES appointments(appointment_id) ON DELETE SET NULL
        )"
    );

    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_ai_events_type_date ON ai_recommendation_events (event_type, created_at DESC)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_ai_events_scan_session ON ai_recommendation_events (scan_session_id)');
    $pdo->exec('CREATE INDEX IF NOT EXISTS idx_ai_events_user_variant ON ai_recommendation_events (user_id, variant_id)');
}

function upsert_user_profile(
    PDO $pdo,
    int $userID,
    ?string $faceShape,
    ?string $hairTexture,
    ?string $hairDensity,
    ?string $hairLength
): void {
    $stmt = $pdo->prepare(
        'INSERT INTO user_profiles (user_id, face_shape, hair_texture, hair_density, hair_length, last_scan_date, created_at)
         VALUES (:user_id, :face_shape, :hair_texture, :hair_density, :hair_length, CURRENT_DATE, NOW())
         ON CONFLICT (user_id) DO UPDATE
         SET face_shape = COALESCE(EXCLUDED.face_shape, user_profiles.face_shape),
             hair_texture = COALESCE(EXCLUDED.hair_texture, user_profiles.hair_texture),
             hair_density = COALESCE(EXCLUDED.hair_density, user_profiles.hair_density),
             hair_length = COALESCE(EXCLUDED.hair_length, user_profiles.hair_length),
             last_scan_date = CURRENT_DATE'
    );
    $stmt->execute([
        ':user_id' => $userID,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':hair_density' => $hairDensity,
        ':hair_length' => $hairLength,
    ]);
}

function insert_event(
    PDO $pdo,
    string $eventType,
    ?int $userID,
    ?string $scanSessionId,
    ?int $variantID,
    ?string $styleName,
    ?int $serviceID,
    ?int $estimatedMinutes,
    ?int $appointmentID,
    ?string $faceShape,
    ?string $hairTexture,
    ?string $hairDensity,
    ?string $hairLength,
    array $metadata
): void {
    $stmt = $pdo->prepare(
        'INSERT INTO ai_recommendation_events (
            user_id, scan_session_id, event_type, variant_id, style_name, service_id, estimated_minutes,
            appointment_id, face_shape, hair_texture, hair_density, hair_length, metadata
         ) VALUES (
            :user_id, :scan_session_id, :event_type, :variant_id, :style_name, :service_id, :estimated_minutes,
                :appointment_id, :face_shape, :hair_texture, :hair_density, :hair_length, CAST(:metadata AS jsonb)
         )'
    );

    $stmt->execute([
        ':user_id' => $userID,
        ':scan_session_id' => $scanSessionId !== '' ? $scanSessionId : null,
        ':event_type' => $eventType,
        ':variant_id' => $variantID,
        ':style_name' => $styleName !== '' ? $styleName : null,
        ':service_id' => $serviceID,
        ':estimated_minutes' => $estimatedMinutes,
        ':appointment_id' => $appointmentID,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':hair_density' => $hairDensity,
        ':hair_length' => $hairLength,
        ':metadata' => json_encode($metadata),
    ]);
}

try {
    $pdo = get_db_connection();
    ensure_ai_funnel_tables($pdo);

    $userIDRaw = $input['userID'] ?? null;
    $userID = $userIDRaw !== null ? (int)$userIDRaw : null;
    if ($userID !== null && $userID <= 0) {
        $userID = null;
    }

    $scanSessionId = trim((string)($input['scanSessionId'] ?? ''));
    $faceShape = normalize_face_shape(isset($input['faceShape']) ? (string)$input['faceShape'] : null);
    $hairTexture = normalize_hair_texture(isset($input['hairTexture']) ? (string)$input['hairTexture'] : null);
    $hairDensity = normalize_hair_density(isset($input['hairDensity']) ? (string)$input['hairDensity'] : null);
    $hairLength = normalize_hair_length(isset($input['hairLength']) ? (string)$input['hairLength'] : null);

    if ($action === 'trackScan') {
        $recommendationCount = (int)($input['recommendationCount'] ?? 0);
        if ($userID !== null) {
            upsert_user_profile($pdo, $userID, $faceShape, $hairTexture, $hairDensity, $hairLength);
        }
        insert_event(
            $pdo,
            'scan_completed',
            $userID,
            $scanSessionId,
            null,
            null,
            null,
            null,
            null,
            $faceShape,
            $hairTexture,
            $hairDensity,
            $hairLength,
            ['recommendationCount' => $recommendationCount]
        );
        json_response(['message' => 'Scan tracked']);
    }

    if ($action === 'saveSelection') {
        if ($userID === null) {
            json_response(['error' => 'Invalid userID'], 422);
        }

        $variantID = (int)($input['variantID'] ?? 0);
        if ($variantID <= 0) {
            json_response(['error' => 'Invalid variantID'], 422);
        }

        $styleName = trim((string)($input['styleName'] ?? ''));
        $estimatedMinutes = (int)($input['estimatedMinutes'] ?? 0);
        if ($estimatedMinutes <= 0) {
            $estimatedMinutes = null;
        }

        $pdo->beginTransaction();

        upsert_user_profile($pdo, $userID, $faceShape, $hairTexture, $hairDensity, $hairLength);

        $prefStmt = $pdo->prepare(
            'INSERT INTO user_style_preferences (
                user_id, preferred_variant_id, preferred_style_name,
                last_face_shape, last_hair_texture, last_hair_density, last_hair_length,
                selection_count, last_selected_at, updated_at
             ) VALUES (
                :user_id, :preferred_variant_id, :preferred_style_name,
                :last_face_shape, :last_hair_texture, :last_hair_density, :last_hair_length,
                1, NOW(), NOW()
             )
             ON CONFLICT (user_id) DO UPDATE
             SET preferred_variant_id = EXCLUDED.preferred_variant_id,
                 preferred_style_name = EXCLUDED.preferred_style_name,
                 last_face_shape = COALESCE(EXCLUDED.last_face_shape, user_style_preferences.last_face_shape),
                 last_hair_texture = COALESCE(EXCLUDED.last_hair_texture, user_style_preferences.last_hair_texture),
                 last_hair_density = COALESCE(EXCLUDED.last_hair_density, user_style_preferences.last_hair_density),
                 last_hair_length = COALESCE(EXCLUDED.last_hair_length, user_style_preferences.last_hair_length),
                 selection_count = user_style_preferences.selection_count + 1,
                 last_selected_at = NOW(),
                 updated_at = NOW()'
        );
        $prefStmt->execute([
            ':user_id' => $userID,
            ':preferred_variant_id' => $variantID,
            ':preferred_style_name' => $styleName !== '' ? $styleName : null,
            ':last_face_shape' => $faceShape,
            ':last_hair_texture' => $hairTexture,
            ':last_hair_density' => $hairDensity,
            ':last_hair_length' => $hairLength,
        ]);

        insert_event(
            $pdo,
            'style_selected',
            $userID,
            $scanSessionId,
            $variantID,
            $styleName,
            null,
            $estimatedMinutes,
            null,
            $faceShape,
            $hairTexture,
            $hairDensity,
            $hairLength,
            []
        );

        $pdo->commit();
        json_response(['message' => 'Selection saved']);
    }

    if ($userID === null) {
        json_response(['error' => 'Invalid userID'], 422);
    }

    $variantID = (int)($input['variantID'] ?? 0);
    $appointmentID = (int)($input['appointmentID'] ?? 0);
    if ($variantID <= 0 || $appointmentID <= 0) {
        json_response(['error' => 'Invalid booking tracking payload'], 422);
    }

    $serviceID = (int)($input['serviceID'] ?? 0);
    if ($serviceID <= 0) {
        $serviceID = null;
    }
    $estimatedMinutes = (int)($input['estimatedMinutes'] ?? 0);
    if ($estimatedMinutes <= 0) {
        $estimatedMinutes = null;
    }

    insert_event(
        $pdo,
        'booking_created',
        $userID,
        $scanSessionId,
        $variantID,
        '',
        $serviceID,
        $estimatedMinutes,
        $appointmentID,
        $faceShape,
        $hairTexture,
        $hairDensity,
        $hairLength,
        []
    );

    json_response(['message' => 'Booking tracked']);
} catch (PDOException $e) {
    if (isset($pdo) && $pdo->inTransaction()) {
        $pdo->rollBack();
    }
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
