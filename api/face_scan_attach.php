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
    $pdo->exec('ALTER TABLE face_scan_previews ADD COLUMN IF NOT EXISTS is_stale BOOLEAN NOT NULL DEFAULT FALSE');
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
 * True only when $url is a real AI-generated capture/preview file that belongs to
 * this exact scan session (uploads/face_scans/{scanSessionId}/...). Catalog/library
 * asset paths (e.g. assets/images/overlays/...) and other sessions' files must never
 * pass this check — otherwise they can be written into an appointment's "AI preview"
 * columns or the face_scan_previews table.
 */
function is_scan_session_preview_url(string $url, string $scanSessionId): bool
{
    $normalized = normalize_preview_relative_url($url);
    if ($normalized === '') {
        return false;
    }

    $safeSession = preg_replace('/[^a-zA-Z0-9_\-]/', '', $scanSessionId) ?? '';
    if ($safeSession === '') {
        return false;
    }

    $prefix = 'uploads/face_scans/' . $safeSession . '/';
    if (!str_starts_with($normalized, $prefix)) {
        return false;
    }

    return face_scan_preview_file_exists($normalized);
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

    $validFront = $front !== '' && is_scan_session_preview_url($front, $scanSessionId);
    $validLeft = $left !== '' && is_scan_session_preview_url($left, $scanSessionId);
    $validRight = $right !== '' && is_scan_session_preview_url($right, $scanSessionId);
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

    // Soft-bind: if this appointment and this scan session both have a known owner and
    // they disagree, never attach — otherwise another user's session could paste its
    // preview images onto this appointment.
    $apptOwnerStmt = $pdo->prepare(
        'SELECT user_id FROM appointments WHERE appointment_id = :appointment_id LIMIT 1'
    );
    $apptOwnerStmt->execute([':appointment_id' => $appointmentId]);
    $apptUserIdRaw = $apptOwnerStmt->fetchColumn();
    $apptUserId = ($apptUserIdRaw !== false && $apptUserIdRaw !== null) ? (int)$apptUserIdRaw : null;

    $sessionOwnerStmt = $pdo->prepare(
        'SELECT user_id FROM face_scan_sessions WHERE scan_session_id = :scan_session_id LIMIT 1'
    );
    $sessionOwnerStmt->execute([':scan_session_id' => $scanSessionId]);
    $sessionUserIdRaw = $sessionOwnerStmt->fetchColumn();
    $sessionUserId = ($sessionUserIdRaw !== false && $sessionUserIdRaw !== null) ? (int)$sessionUserIdRaw : null;

    if ($apptUserId !== null && $sessionUserId !== null && $apptUserId !== $sessionUserId) {
        error_log(sprintf(
            'face_scan_attach: skipped — appointment %d belongs to user %d but scan session %s belongs to user %d',
            $appointmentId,
            $apptUserId,
            $scanSessionId,
            $sessionUserId
        ));
        return ['front' => null, 'left' => null, 'right' => null, 'attached' => false];
    }

    $fallback = $urlFallback ?? [];
    if ($variantId > 0 && $fallback !== []) {
        upsert_face_scan_previews_from_urls($pdo, $scanSessionId, $variantId, $fallback);
    }

    // NOTE: :variant_id is bound twice below under two different placeholder names —
    // PDO with ATTR_EMULATE_PREPARES=false (native prepares) rejects reusing the same
    // named placeholder more than once in a single statement.
    $previewStmt = $pdo->prepare(
        'SELECT front_url, left_url, right_url
         FROM face_scan_previews
         WHERE scan_session_id = :scan_session_id
           AND is_stale = FALSE
           AND (:variant_id_filter <= 0 OR variant_id = :variant_id_match)
         ORDER BY preview_id DESC
         LIMIT 1'
    );
    $previewStmt->execute([
        ':scan_session_id' => $scanSessionId,
        ':variant_id_filter' => $variantId,
        ':variant_id_match' => $variantId,
    ]);
    $preview = $previewStmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $front = $preview['front_url'] ?? null;
    $left = $preview['left_url'] ?? null;
    $right = $preview['right_url'] ?? null;

    // Fallback URLs from the client are only trusted when they are real AI preview
    // files that belong to this exact scan session — never catalog/library asset paths.
    if (($front === null || $front === '') && !empty($fallback['frontViewUrl'])
        && is_scan_session_preview_url((string)$fallback['frontViewUrl'], $scanSessionId)) {
        $front = normalize_preview_relative_url((string)$fallback['frontViewUrl']);
    }
    if (($left === null || $left === '') && !empty($fallback['sideViewUrl'])
        && is_scan_session_preview_url((string)$fallback['sideViewUrl'], $scanSessionId)) {
        $left = normalize_preview_relative_url((string)$fallback['sideViewUrl']);
    }
    if (($right === null || $right === '') && !empty($fallback['backViewUrl'])
        && is_scan_session_preview_url((string)$fallback['backViewUrl'], $scanSessionId)) {
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
