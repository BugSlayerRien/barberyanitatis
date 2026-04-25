<?php

declare(strict_types=1);

require_once __DIR__ . '/../api/db.php';

function upsert_staff(PDO $pdo, string $email, string $fullName, string $role, string $password): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO staff_users (email, password_hash, full_name, role, is_active)
         VALUES (:email, :password_hash, :full_name, :role, TRUE)
         ON CONFLICT (email)
         DO UPDATE SET
            password_hash = EXCLUDED.password_hash,
            full_name = EXCLUDED.full_name,
            role = EXCLUDED.role,
            is_active = TRUE,
            updated_at = NOW()'
    );

    $stmt->execute([
        ':email' => $email,
        ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
        ':full_name' => $fullName,
        ':role' => $role,
    ]);
}

function upsert_user(PDO $pdo, string $email, string $fullName, string $password): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO users (email, password_hash, full_name, is_active)
         VALUES (:email, :password_hash, :full_name, TRUE)
         ON CONFLICT (email)
         DO UPDATE SET
            password_hash = EXCLUDED.password_hash,
            full_name = EXCLUDED.full_name,
            is_active = TRUE,
            updated_at = NOW()'
    );

    $stmt->execute([
        ':email' => $email,
        ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
        ':full_name' => $fullName,
    ]);
}

function upsert_barber(PDO $pdo, string $barberCode, string $fullName, string $email, string $password): int
{
    $codeCheck = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE barber_code = :barber_code AND email <> :email');
    $codeCheck->execute([
        ':barber_code' => $barberCode,
        ':email' => $email,
    ]);
    if ((int)$codeCheck->fetchColumn() > 0) {
        for ($i = 900; $i < 1000; $i++) {
            $candidate = 'BRB' . $i;
            $candidateCheck = $pdo->prepare('SELECT COUNT(*) FROM barbers WHERE barber_code = :barber_code');
            $candidateCheck->execute([':barber_code' => $candidate]);
            if ((int)$candidateCheck->fetchColumn() === 0) {
                $barberCode = $candidate;
                break;
            }
        }
    }

    $stmt = $pdo->prepare(
        'INSERT INTO barbers (barber_code, full_name, email, password_hash, specialty, years_experience, rating, is_active)
         VALUES (:barber_code, :full_name, :email, :password_hash, :specialty, :years_experience, 5.00, TRUE)
         ON CONFLICT (email)
         DO UPDATE SET
            full_name = EXCLUDED.full_name,
            password_hash = EXCLUDED.password_hash,
            specialty = EXCLUDED.specialty,
            years_experience = EXCLUDED.years_experience,
            is_active = TRUE
         RETURNING barber_id'
    );

    $stmt->execute([
        ':barber_code' => $barberCode,
        ':full_name' => $fullName,
        ':email' => $email,
        ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
        ':specialty' => 'Fade and modern cuts',
        ':years_experience' => 5,
    ]);

    return (int)$stmt->fetchColumn();
}

function upsert_service(PDO $pdo, string $serviceCode, string $serviceName, int $duration, float $price): int
{
    $stmt = $pdo->prepare(
        'INSERT INTO services (service_code, service_name, description, base_duration, base_price, category, is_active)
         VALUES (:service_code, :service_name, :description, :base_duration, :base_price, :category, TRUE)
         ON CONFLICT (service_code)
         DO UPDATE SET
            service_name = EXCLUDED.service_name,
            description = EXCLUDED.description,
            base_duration = EXCLUDED.base_duration,
            base_price = EXCLUDED.base_price,
            category = EXCLUDED.category,
            is_active = TRUE
         RETURNING service_id'
    );

    $stmt->execute([
        ':service_code' => $serviceCode,
        ':service_name' => $serviceName,
        ':description' => 'Essential seeded service for booking and dashboard flows.',
        ':base_duration' => $duration,
        ':base_price' => $price,
        ':category' => 'Haircut',
    ]);

    return (int)$stmt->fetchColumn();
}

function upsert_hairstyle(PDO $pdo, string $styleCode, string $styleName, string $description): int
{
    $stmt = $pdo->prepare(
        'INSERT INTO hairstyles (style_code, style_name, description, gender, difficulty, maintenance, popularity_score, is_active)
         VALUES (:style_code, :style_name, :description, :gender, :difficulty, :maintenance, 0, TRUE)
         ON CONFLICT (style_code)
         DO UPDATE SET
            style_name = EXCLUDED.style_name,
            description = EXCLUDED.description,
            is_active = TRUE
         RETURNING hairstyle_id'
    );

    $stmt->execute([
        ':style_code' => $styleCode,
        ':style_name' => $styleName,
        ':description' => $description,
        ':gender' => 'Unisex',
        ':difficulty' => 'Medium',
        ':maintenance' => 'Medium',
    ]);

    return (int)$stmt->fetchColumn();
}

function upsert_variant(PDO $pdo, int $hairstyleId, string $faceShape, string $hairTexture, string $front, string $side, string $back, float $confidence): void
{
    $stmt = $pdo->prepare(
        'INSERT INTO hairstyle_variants
            (hairstyle_id, face_shape, hair_texture, front_view_url, side_view_url, back_view_url, barber_instructions, clipper_sizes, styling_products, estimated_minutes, confidence_score)
         VALUES
            (:hairstyle_id, :face_shape, :hair_texture, :front_view_url, :side_view_url, :back_view_url, :barber_instructions, :clipper_sizes, :styling_products, :estimated_minutes, :confidence_score)
         ON CONFLICT (hairstyle_id, face_shape, hair_texture)
         DO UPDATE SET
            front_view_url = EXCLUDED.front_view_url,
            side_view_url = EXCLUDED.side_view_url,
            back_view_url = EXCLUDED.back_view_url,
            barber_instructions = EXCLUDED.barber_instructions,
            clipper_sizes = EXCLUDED.clipper_sizes,
            styling_products = EXCLUDED.styling_products,
            estimated_minutes = EXCLUDED.estimated_minutes,
            confidence_score = EXCLUDED.confidence_score'
    );

    $stmt->execute([
        ':hairstyle_id' => $hairstyleId,
        ':face_shape' => $faceShape,
        ':hair_texture' => $hairTexture,
        ':front_view_url' => $front,
        ':side_view_url' => $side,
        ':back_view_url' => $back,
        ':barber_instructions' => 'Seeded baseline instructions for a clean finish and taper blend.',
        ':clipper_sizes' => '0.5, 1, 2',
        ':styling_products' => 'Matte clay, light hold spray',
        ':estimated_minutes' => 35,
        ':confidence_score' => $confidence,
    ]);
}

function seed_time_slots(PDO $pdo, int $barberId): void
{
    $slotStmt = $pdo->prepare(
        'INSERT INTO time_slots (barber_id, slot_date, slot_time, duration, status)
         VALUES (:barber_id, :slot_date, :slot_time, 35, :status)
         ON CONFLICT (barber_id, slot_date, slot_time)
         DO UPDATE SET status = EXCLUDED.status, duration = EXCLUDED.duration'
    );

    $today = new DateTimeImmutable('today');
    for ($d = 0; $d < 3; $d++) {
        $date = $today->modify('+' . $d . ' day')->format('Y-m-d');
        foreach (['09:00:00', '09:50:00', '10:40:00'] as $time) {
            $slotStmt->execute([
                ':barber_id' => $barberId,
                ':slot_date' => $date,
                ':slot_time' => $time,
                ':status' => 'Available',
            ]);
        }
    }
}

try {
    $pdo = get_db_connection();
    $pdo->beginTransaction();

    upsert_staff($pdo, 'admin@tatis.local', 'System Admin', 'Admin', 'Admin123!');
    upsert_staff($pdo, 'receptionist@tatis.local', 'Front Desk', 'Receptionist', 'Reception123!');
    upsert_user($pdo, 'customer@tatis.local', 'Demo Customer', 'Customer123!');

    $barberId = upsert_barber($pdo, 'BRB001', 'Demo Barber', 'barber@tatis.local', 'Barber123!');

    upsert_service($pdo, 'HCT-CLASSIC', 'Classic Haircut', 35, 180.00);

    $afroTaper = upsert_hairstyle($pdo, 'STYLE-AFRO-TAPER', 'Afro Taper', 'Balanced taper that works with textured volume.');
    $crop = upsert_hairstyle($pdo, 'STYLE-TEXTURED-CROP', 'Textured Crop', 'Modern textured crop with clean edges.');

    upsert_variant(
        $pdo,
        $afroTaper,
        'Oval',
        'Coily',
        '/database/assets/hairstyles/afro_taper_front.png',
        '/database/assets/hairstyles/afro_taper_left.png',
        '/database/assets/hairstyles/afro_taper_right.png',
        0.930
    );
    upsert_variant(
        $pdo,
        $afroTaper,
        'Round',
        'Curly',
        '/database/assets/hairstyles/afro_taper_front.png',
        '/database/assets/hairstyles/afro_taper_left.png',
        '/database/assets/hairstyles/afro_taper_right.png',
        0.910
    );
    upsert_variant(
        $pdo,
        $afroTaper,
        'Square',
        'Coily',
        '/database/assets/hairstyles/afro_taper_front.png',
        '/database/assets/hairstyles/afro_taper_left.png',
        '/database/assets/hairstyles/afro_taper_right.png',
        0.900
    );
    upsert_variant(
        $pdo,
        $crop,
        'Oval',
        'Straight',
        '/database/assets/hairstyles/textured_crop_front.png',
        '/database/assets/hairstyles/textured_crop_left.png',
        '/database/assets/hairstyles/textured_crop_right.png',
        0.920
    );
    upsert_variant(
        $pdo,
        $crop,
        'Oblong',
        'Wavy',
        '/database/assets/hairstyles/textured_crop_front.png',
        '/database/assets/hairstyles/textured_crop_left.png',
        '/database/assets/hairstyles/textured_crop_right.png',
        0.905
    );

    seed_time_slots($pdo, $barberId);

    $settingStmt = $pdo->prepare(
        'INSERT INTO system_settings (setting_key, setting_value, setting_type, category, description, is_editable, updated_at)
         VALUES (:setting_key, :setting_value, :setting_type, :category, :description, TRUE, NOW())
         ON CONFLICT (setting_key)
         DO UPDATE SET
            setting_value = EXCLUDED.setting_value,
            setting_type = EXCLUDED.setting_type,
            category = EXCLUDED.category,
            description = EXCLUDED.description,
            is_editable = TRUE,
            updated_at = NOW()'
    );
    $settingStmt->execute([
        ':setting_key' => 'shop_open_hours',
        ':setting_value' => '09:00-19:00',
        ':setting_type' => 'String',
        ':category' => 'operations',
        ':description' => 'Baseline shop opening hours for seeded environments.',
    ]);

    $pdo->commit();

    $counts = [];
    foreach (['users', 'staff_users', 'barbers', 'services', 'hairstyles', 'hairstyle_variants', 'time_slots'] as $table) {
        $counts[$table] = (int)$pdo->query('SELECT COUNT(*) FROM ' . $table)->fetchColumn();
    }

    echo json_encode([
        'message' => 'Minimum seed upsert complete',
        'counts' => $counts,
    ], JSON_PRETTY_PRINT) . PHP_EOL;
} catch (Throwable $e) {
    if (isset($pdo) && $pdo instanceof PDO && $pdo->inTransaction()) {
        $pdo->rollBack();
    }

    fwrite(STDERR, 'Seed failed: ' . $e->getMessage() . PHP_EOL);
    exit(1);
}
