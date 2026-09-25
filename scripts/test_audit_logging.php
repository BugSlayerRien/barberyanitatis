<?php

declare(strict_types=1);

/**
 * Exercises the audit writer and the pieces the reader is built on.
 *
 * The previous version inserted rows with raw SQL, which tested nothing about
 * audit_log() itself, and left two junk rows in the table on every run. This
 * one calls the real writer and rolls everything back, so it is safe to run
 * against a live database.
 *
 * Usage: php scripts/test_audit_logging.php
 */

require_once __DIR__ . '/../api/db.php';
require_once __DIR__ . '/../api/audit_view.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $ok, string $detail = ''): void
{
    global $failures, $checks;
    $checks++;
    if ($ok) {
        echo "  PASS  {$label}\n";

        return;
    }
    $failures++;
    echo "  FAIL  {$label}" . ($detail !== '' ? " -- {$detail}" : '') . "\n";
}

$pdo = get_db_connection();
schema_ensure_once('audit_logs.actor', static function () use ($pdo): void {
    ensure_audit_actor_columns($pdo);
});

echo "Audit logging\n";

$pdo->beginTransaction();
try {
    $before = (int)$pdo->query('SELECT COUNT(*) FROM audit_logs')->fetchColumn();

    // 1. The writer stores what it is given, including the actor.
    $ok = audit_log(
        $pdo,
        'TEST_PAYMENT_CAPTURED',
        'appointment_payments',
        '4242',
        ['status' => 'PendingGateway'],
        ['status' => 'Paid', 'amount' => 300.0],
        77,
        audit_actor_staff(['staff_id' => 9, 'role' => 'Admin', 'full_name' => 'Test Admin'])
    );
    check('audit_log() returns true', $ok);

    $row = $pdo->query(
        'SELECT * FROM audit_logs ORDER BY log_id DESC LIMIT 1'
    )->fetch(PDO::FETCH_ASSOC);

    check('action_type stored', ($row['action_type'] ?? '') === 'TEST_PAYMENT_CAPTURED');
    check('record_id stored', (string)($row['record_id'] ?? '') === '4242');
    check('actor_type is admin', ($row['actor_type'] ?? '') === 'admin');
    check('actor_id is the staff id, not the customer', (int)($row['actor_id'] ?? 0) === 9);
    check('actor_label stored', ($row['actor_label'] ?? '') === 'Test Admin');
    check('user_id still means the customer', (int)($row['user_id'] ?? 0) === 77);
    check(
        'new_values round-trips as JSON',
        (json_decode((string)($row['new_values'] ?? ''), true)['status'] ?? null) === 'Paid'
    );

    // 2. A null record_id must stay NULL, not become an empty string.
    audit_log($pdo, 'TEST_NO_RECORD', 'appointments', null, null, ['note' => 'x'], null, audit_actor_system());
    $nullRow = $pdo->query('SELECT record_id, actor_type FROM audit_logs ORDER BY log_id DESC LIMIT 1')->fetch(PDO::FETCH_ASSOC);
    check('null record_id stays NULL', $nullRow['record_id'] === null, var_export($nullRow['record_id'], true));
    check('system actor recorded', ($nullRow['actor_type'] ?? '') === 'system');

    // 3. The ambient actor is used when a call site does not pass one.
    audit_set_current_actor(audit_actor_webhook());
    audit_log($pdo, 'TEST_AMBIENT_ACTOR', 'appointment_payments', '1', null, null);
    audit_set_current_actor(null);
    $ambient = $pdo->query('SELECT actor_type FROM audit_logs ORDER BY log_id DESC LIMIT 1')->fetch(PDO::FETCH_ASSOC);
    check('ambient actor applied', ($ambient['actor_type'] ?? '') === 'webhook');

    // 4. Reader helpers: categories and the change diff.
    check('payment categorised as money', audit_event_category('PAYMENT_CAPTURED', 'appointment_payments') === 'money');
    check('reschedule categorised as appointments', audit_event_category('RESCHEDULE_APPOINTMENT', 'appointments') === 'appointments');
    check('user change categorised as users', audit_event_category('USER_DELETE', 'users') === 'users');
    check('unknown falls back to system', audit_event_category('SOMETHING_ELSE', null) === 'system');
    check('title humanised', audit_event_title('COMPLETE_REFUND') === 'Complete refund');

    $changes = audit_event_changes(['status' => 'Pending', 'amount' => 300], ['status' => 'Completed', 'amount' => 300]);
    check('only changed fields reported', count($changes) === 1 && $changes[0]['field'] === 'status');
    check('from/to captured', ($changes[0]['from'] ?? null) === 'Pending' && ($changes[0]['to'] ?? null) === 'Completed');

    $after = (int)$pdo->query('SELECT COUNT(*) FROM audit_logs')->fetchColumn();
    check('three rows written', $after - $before === 3, "before={$before} after={$after}");
} finally {
    // Nothing this script wrote is kept.
    $pdo->rollBack();
}

$mine = "('TEST_PAYMENT_CAPTURED', 'TEST_NO_RECORD', 'TEST_AMBIENT_ACTOR')";
$left = (int)$pdo->query("SELECT COUNT(*) FROM audit_logs WHERE action_type IN {$mine}")->fetchColumn();
check('this run left nothing behind', $left === 0, "found {$left}");

// Junk from the previous version of this script, which inserted with raw SQL
// and never cleaned up. Reported, not failed: removing rows is the operator's
// call, not a test's.
$legacy = (int)$pdo->query(
    "SELECT COUNT(*) FROM audit_logs WHERE action_type IN ('TEST_CREATE', 'TEST_UPDATE')"
)->fetchColumn();
if ($legacy > 0) {
    echo "  NOTE  {$legacy} row(s) from the old test script are still in audit_logs.\n";
    echo "        DELETE FROM audit_logs WHERE action_type IN ('TEST_CREATE', 'TEST_UPDATE');\n";
}

echo "\nRecent activity feed\n";

require_once __DIR__ . '/../api/activity_feed.php';

$feed = build_recent_activity($pdo, 20);
$known = ['money', 'appointments', 'users', 'services', 'system'];
$shapeOk = true;
$categoryOk = true;
foreach ($feed as $item) {
    foreach (['icon', 'title', 'description', 'time', 'category', 'source'] as $field) {
        if (!array_key_exists($field, $item)) {
            $shapeOk = false;
        }
    }
    if (!in_array($item['category'] ?? '', $known, true)) {
        $categoryOk = false;
    }
}
check('every entry has the expected fields', $shapeOk);
check('every category is a known bucket', $categoryOk);
check('internal dedupe key is not leaked to the client', !array_key_exists('dedupeKey', $feed[0] ?? ['dedupeKey' => null]));

// The old feed could only ever produce one title; the point of B4 is variety.
$titles = array_unique(array_map(static fn(array $i): string => (string)$i['title'], $feed));
check('feed is not a single repeated title', $feed === [] || count($titles) > 1, implode(', ', $titles));

// An appointment already covered by the audit log must not ALSO be listed
// from the appointments table -- that showed every booking twice. Two
// different audit events for one appointment (created, then cancelled) are
// two real events and must both survive.
$fromAudit = [];
$fromTable = [];
foreach ($feed as $item) {
    if (preg_match('/appointments? #(\d+)/', (string)$item['description'], $m) !== 1) {
        continue;
    }
    if (($item['source'] ?? '') === 'audit') {
        $fromAudit[$m[1]] = true;
    } elseif (($item['source'] ?? '') === 'appointments') {
        $fromTable[$m[1]] = true;
    }
}
$overlap = array_keys(array_intersect_key($fromTable, $fromAudit));
check(
    'no booking listed from both the audit log and the appointments table',
    $overlap === [],
    'appointments: ' . implode(', ', $overlap)
);

$sorted = $feed;
usort($sorted, static fn(array $a, array $b): int => strtotime((string)$b['time']) <=> strtotime((string)$a['time']));
check('feed is newest first', array_map(static fn(array $i): string => (string)$i['time'], $feed)
    === array_map(static fn(array $i): string => (string)$i['time'], $sorted));

echo "\n{$checks} checks, {$failures} failed\n";
exit($failures === 0 ? 0 : 1);
