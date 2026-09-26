<?php

declare(strict_types=1);

/**
 * Data retention sweep, run by hand or from cron.
 *
 * Deletes face captures and AI previews past their retention window, and
 * reports (or, when ACCOUNT_PURGE_ENABLED is set, removes) accounts with no
 * activity inside the account window.
 *
 *   php scripts/run_data_retention.php --dry-run   report only, delete nothing
 *   php scripts/run_data_retention.php             perform the deletions
 */

require_once __DIR__ . '/../api/data_retention.php';

$dryRun = in_array('--dry-run', $argv, true);
$pdo = get_db_connection();

echo 'Scan media retention: ' . scan_media_retention_days() . " days\n";
echo 'Account retention:    ' . account_retention_days() . " days\n";
echo 'Account purge:        ' . (account_purge_enabled() ? 'enabled' : 'report only') . "\n";
echo $dryRun ? "Mode: DRY RUN (nothing is deleted)\n\n" : "Mode: LIVE\n\n";

$media = purge_expired_scan_media($pdo, $dryRun);
printf(
    "Scan media  previews=%d savedLooks=%d sessions=%d files=%d\n",
    $media['previews'],
    $media['savedLooks'],
    $media['sessions'],
    $media['files']
);

$accounts = purge_inactive_accounts($pdo, $dryRun);
printf(
    "Accounts    candidates=%d deleted=%d\n",
    $accounts['candidates'],
    $accounts['deleted']
);

if (!$accounts['enabled'] && $accounts['candidates'] > 0) {
    echo "\nSet ACCOUNT_PURGE_ENABLED=1 to delete those accounts. Deletion cannot be undone.\n";
}
