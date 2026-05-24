<?php
// Shared helpers: attach face-scan AI previews to appointments.

declare(strict_types=1);

function ensure_face_scan_preview_storage(PDO $pdo): void
{
    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS face_scan_previews (
            preview_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            scan_session_id VARCHAR(80) NOT NULL,
            variant_id BIGINT,
            front_url TEXT,
            left_url TEXT,
            right_url TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )"
    );
    $pdo->exec(
        'ALTER TABLE appointments
         ADD COLUMN IF NOT EXISTS scan_session_id VARCHAR(80)'
    );
    $pdo->exec(
        'ALTER TABLE appointment_details
         ADD COLUMN IF NOT EXISTS customer_front_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_left_url TEXT,
         ADD COLUMN IF NOT EXISTS customer_right_url TEXT'
    );
}

function face_scan_preview_file_exists(string $relativeUrl): bool
{
    $relativeUrl = trim($relativeUrl);
    if ($relativeUrl === '') {
        return false;
    }
    $root = dirname(__DIR__);
    $fullPath = $root . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim($relativeUrl, '/'));
    return is_file($fullPath) && filesize($fullPath) > 0;
}

/**
 * Normalize a preview path to a relative uploads URL when possible.
 */
function normalize_preview_relative_url(string $url): string
{
    $url = trim($url);
    if ($url === '') {
        return '';
    }
    if (str_starts_with($url, 'uploads/')) {
        return $url;
    }
    if (str_contains($url, 'uploads/face_scans/')) {
        $pos = strpos($url, 'uploads/face_scans/');
        if ($pos !== false) {
            return substr($url, $pos);
        }
    }
    return $url;
}

/**
 * @param array{frontViewUrl?: string, sideViewUrl?: string, backViewUrl?: string} $fallback
 */
function upsert_face_scan_previews_from_urls(
    PDO $pdo,
    string $scanSessionId,
    int $variantId,
    array $fallback
): void {
    $front = normalize_preview_relative_url((string)($fallback['frontViewUrl'] ?? ''));
    $left = normalize_preview_relative_url((string)($fallback['sideViewUrl'] ?? ''));
    $right = normalize_preview_relative_url((string)($fallback['backViewUrl'] ?? ''));

    if ($front === '' && $left === '' && $right === '') {
        return;
    }

    $validFront = $front !== '' && face_scan_preview_file_exists($front);
    $validLeft = $left !== '' && face_scan_preview_file_exists($left);
    $validRight = $right !== '' && face_scan_preview_file_exists($right);
    if (!$validFront && !$validLeft && !$validRight) {
        return;
    }

    $check = $pdo->prepare(
        'SELECT preview_id FROM face_scan_previews
         WHERE scan_session_id = :scan_session_id
           AND variant_id = :variant_id
         ORDER BY preview_id DESC
         LIMIT 1'
    );
    $check->execute([
        ':scan_session_id' => $scanSessionId,
        ':variant_id' => $variantId > 0 ? $variantId : null,
    ]);
    $existing = $check->fetch();

    if ($existing) {
        $stmt = $pdo->prepare(
            'UPDATE face_scan_previews
             SET front_url = COALESCE(NULLIF(:front_url, \'\'), front_url),
                 left_url = COALESCE(NULLIF(:left_url, \'\'), left_url),
                 right_url = COALESCE(NULLIF(:right_url, \'\'), right_url)
             WHERE preview_id = :preview_id'
        );
        $stmt->execute([
            ':preview_id' => (int)$existing['preview_id'],
            ':front_url' => $validFront ? $front : '',
            ':left_url' => $validLeft ? $left : '',
            ':right_url' => $validRight ? $right : '',
        ]);
        return;
    }

    $stmt = $pdo->prepare(
        'INSERT INTO face_scan_previews (scan_session_id, variant_id, front_url, left_url, right_url)
         VALUES (:scan_session_id, :variant_id, :front_url, :left_url, :right_url)'
    );
    $stmt->execute([
        ':scan_session_id' => $scanSessionId,
        ':variant_id' => $variantId > 0 ? $variantId : null,
        ':front_url' => $validFront ? $front : null,
        ':left_url' => $validLeft ? $left : null,
        ':right_url' => $validRight ? $right : null,
    ]);
}

/**
 * Resolve preview URLs from DB or fallback, then link to appointment.
 *
 * @param array{frontViewUrl?: string, sideViewUrl?: string, backViewUrl?: string}|null $urlFallback
 * @return array{front:?string,left:?string,right:?string,attached:bool}
 */
function attach_scan_previews_to_appointment(
    PDO $pdo,
    int $appointmentId,
    string $scanSessionId,
    int $variantId,
    ?array $urlFallback = null
): array {
    if ($appointmentId <= 0 || $scanSessionId === '') {
        return ['front' => null, 'left' => null, 'right' => null, 'attached' => false];
    }

    ensure_face_scan_preview_storage($pdo);

    $fallback = $urlFallback ?? [];
    if ($variantId > 0 && $fallback !== []) {
        upsert_face_scan_previews_from_urls($pdo, $scanSessionId, $variantId, $fallback);
    }

    $previewStmt = $pdo->prepare(
        'SELECT front_url, left_url, right_url
         FROM face_scan_previews
         WHERE scan_session_id = :scan_session_id
           AND (:variant_id <= 0 OR variant_id = :variant_id)
         ORDER BY preview_id DESC
         LIMIT 1'
    );
    $previewStmt->execute([
        ':scan_session_id' => $scanSessionId,
        ':variant_id' => $variantId,
    ]);
    $preview = $previewStmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $front = $preview['front_url'] ?? null;
    $left = $preview['left_url'] ?? null;
    $right = $preview['right_url'] ?? null;

    if (($front === null || $front === '') && !empty($fallback['frontViewUrl'])) {
        $front = normalize_preview_relative_url((string)$fallback['frontViewUrl']);
    }
    if (($left === null || $left === '') && !empty($fallback['sideViewUrl'])) {
        $left = normalize_preview_relative_url((string)$fallback['sideViewUrl']);
    }
    if (($right === null || $right === '') && !empty($fallback['backViewUrl'])) {
        $right = normalize_preview_relative_url((string)$fallback['backViewUrl']);
    }

    $hasAny = ($front !== null && $front !== '')
        || ($left !== null && $left !== '')
        || ($right !== null && $right !== '');

    if (!$hasAny) {
        return ['front' => null, 'left' => null, 'right' => null, 'attached' => false];
    }

    $apptStmt = $pdo->prepare(
        'UPDATE appointments SET scan_session_id = :scan_session_id WHERE appointment_id = :appointment_id'
    );
    $apptStmt->execute([
        ':scan_session_id' => $scanSessionId,
        ':appointment_id' => $appointmentId,
    ]);

    $detailStmt = $pdo->prepare(
        'UPDATE appointment_details
         SET customer_front_url = COALESCE(:front_url, customer_front_url),
             customer_left_url = COALESCE(:left_url, customer_left_url),
             customer_right_url = COALESCE(:right_url, customer_right_url)
         WHERE appointment_id = :appointment_id'
    );
    $detailStmt->execute([
        ':appointment_id' => $appointmentId,
        ':front_url' => $front,
        ':left_url' => $left,
        ':right_url' => $right,
    ]);

    return [
        'front' => $front,
        'left' => $left,
        'right' => $right,
        'attached' => true,
    ];
}
