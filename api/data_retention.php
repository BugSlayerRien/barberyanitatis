<?php

declare(strict_types=1);

/**
 * Deletes personal data once it has outlived its purpose.
 *
 * Face captures and AI previews are the sensitive part of this system: they
 * are photographs of a customer's face. They are useful during the scan
 * session and while a booking made from them is still ahead, and worthless
 * afterwards -- so they are deleted on a much shorter clock than the account
 * itself. Everything derived from them (face shape, hair texture) is plain
 * text and is kept, so recommendations still work.
 *
 * Accounts and bookings are kept longer because they are business records, and
 * account deletion is deliberately opt-in: silently removing a customer who
 * simply has not visited in a while is worse than keeping a stale row.
 */

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/schema_cache.php';
require_once __DIR__ . '/storage.php';

/** How long a face capture / AI preview is kept. Default 90 days. */
function scan_media_retention_days(): int
{
    $raw = trim((string)(getenv('SCAN_MEDIA_RETENTION_DAYS')
        ?: ($_ENV['SCAN_MEDIA_RETENTION_DAYS'] ?? '')));
    $days = $raw !== '' ? (int)$raw : 90;

    return $days > 0 ? $days : 90;
}

/** How long an inactive account is kept. Default 3 years. */
function account_retention_days(): int
{
    $raw = trim((string)(getenv('ACCOUNT_RETENTION_DAYS')
        ?: ($_ENV['ACCOUNT_RETENTION_DAYS'] ?? '')));
    $days = $raw !== '' ? (int)$raw : 1095;

    return $days > 0 ? $days : 1095;
}

/**
 * Account deletion is destructive and cannot be undone, so it only runs when
 * explicitly switched on.
 */
function account_purge_enabled(): bool
{
    $raw = strtolower(trim((string)(getenv('ACCOUNT_PURGE_ENABLED')
        ?: ($_ENV['ACCOUNT_PURGE_ENABLED'] ?? ''))));

    return in_array($raw, ['1', 'true', 'yes', 'on'], true);
}

/**
 * Removes stored face captures and AI previews past the retention window.
 *
 * @param bool $dryRun Report what would go without deleting anything.
 * @return array{previews: int, savedLooks: int, sessions: int, files: int, dryRun: bool}
 */
function purge_expired_scan_media(PDO $pdo, bool $dryRun = false): array
{
    $days = scan_media_retention_days();
    $result = ['previews' => 0, 'savedLooks' => 0, 'sessions' => 0, 'files' => 0, 'dryRun' => $dryRun];

    // Collect the file paths first: once the rows are gone there is nothing
    // left pointing at the images, and they would sit in storage forever.
    $paths = [];
    $collect = static function (array $row) use (&$paths): void {
        foreach (['front_url', 'left_url', 'right_url'] as $column) {
            $value = trim((string)($row[$column] ?? ''));
            if ($value !== '') {
                $paths[$value] = true;
            }
        }
    };

    $previewStmt = $pdo->prepare(
        "SELECT preview_id, front_url, left_url, right_url
         FROM face_scan_previews
         WHERE created_at < NOW() - (:days || ' days')::interval"
    );
    $previewStmt->execute([':days' => $days]);
    $previews = $previewStmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($previews as $row) {
        $collect($row);
    }
    $result['previews'] = count($previews);

    $savedStmt = $pdo->prepare(
        "SELECT saved_preview_id, front_url, left_url, right_url
         FROM user_saved_previews
         WHERE created_at < NOW() - (:days || ' days')::interval"
    );
    $savedStmt->execute([':days' => $days]);
    $saved = $savedStmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($saved as $row) {
        $collect($row);
    }
    $result['savedLooks'] = count($saved);

    $sessionStmt = $pdo->prepare(
        "SELECT COUNT(*) FROM face_scan_sessions
         WHERE created_at < NOW() - (:days || ' days')::interval"
    );
    $sessionStmt->execute([':days' => $days]);
    $result['sessions'] = (int)$sessionStmt->fetchColumn();

    if ($dryRun) {
        $result['files'] = count($paths);

        return $result;
    }

    foreach (array_keys($paths) as $path) {
        if (storage_delete((string)$path)) {
            $result['files']++;
        }
    }

    $pdo->prepare(
        "DELETE FROM face_scan_previews WHERE created_at < NOW() - (:days || ' days')::interval"
    )->execute([':days' => $days]);
    $pdo->prepare(
        "DELETE FROM user_saved_previews WHERE created_at < NOW() - (:days || ' days')::interval"
    )->execute([':days' => $days]);
    // Sessions last: previews reference them.
    $pdo->prepare(
        "DELETE FROM face_scan_sessions WHERE created_at < NOW() - (:days || ' days')::interval"
    )->execute([':days' => $days]);

    if ($result['previews'] > 0 || $result['savedLooks'] > 0 || $result['sessions'] > 0) {
        audit_log($pdo, 'SCAN_MEDIA_PURGED', 'face_scan_previews', null, null, [
            'retention_days' => $days,
            'previews' => $result['previews'],
            'saved_looks' => $result['savedLooks'],
            'sessions' => $result['sessions'],
            'files_deleted' => $result['files'],
        ], null, audit_actor_system('Data retention'));
    }

    return $result;
}

/**
 * Accounts with no activity inside the retention window.
 *
 * Reports by default; only deletes when ACCOUNT_PURGE_ENABLED is set. A
 * customer with any appointment inside the window is never touched, however
 * old the account itself is.
 *
 * @return array{candidates: int, deleted: int, enabled: bool}
 */
function purge_inactive_accounts(PDO $pdo, bool $dryRun = false): array
{
    $days = account_retention_days();
    $enabled = account_purge_enabled();

    $stmt = $pdo->prepare(
        "SELECT u.user_id
         FROM users u
         WHERE u.created_at < NOW() - (:days || ' days')::interval
           AND NOT EXISTS (
                SELECT 1 FROM appointments a
                WHERE a.user_id = u.user_id
                  AND a.created_at >= NOW() - (:days || ' days')::interval
           )"
    );
    $stmt->execute([':days' => $days]);
    $ids = array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));

    $result = ['candidates' => count($ids), 'deleted' => 0, 'enabled' => $enabled];
    if (!$enabled || $dryRun || $ids === []) {
        return $result;
    }

    foreach ($ids as $userId) {
        try {
            $pdo->prepare('DELETE FROM users WHERE user_id = :id')->execute([':id' => $userId]);
            $result['deleted']++;
            audit_log($pdo, 'ACCOUNT_PURGED', 'users', (string)$userId, null, [
                'retention_days' => $days,
                'reason' => 'no activity within retention window',
            ], $userId, audit_actor_system('Data retention'));
        } catch (Throwable $e) {
            // A row another table still references stays; report and move on.
            error_log('Account purge skipped for ' . $userId . ': ' . $e->getMessage());
        }
    }

    return $result;
}

/**
 * Entry point for request traffic. Throttled to once a day: this is
 * housekeeping, not something a customer should ever wait for.
 */
function run_data_retention_sweep(PDO $pdo): void
{
    if (!schema_cache_should_run('data_retention_sweep', 86400)) {
        return;
    }

    try {
        purge_expired_scan_media($pdo);
        purge_inactive_accounts($pdo);
    } catch (Throwable $e) {
        error_log('Data retention sweep skipped: ' . $e->getMessage());
    }

    schema_cache_done('data_retention_sweep');
}
