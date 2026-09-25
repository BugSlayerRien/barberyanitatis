<?php

declare(strict_types=1);

/**
 * Recent activity for the admin dashboard.
 *
 * The dashboard used to run one query against `appointments` and stamp every
 * row with the literal title "New appointment created". The client offers four
 * category filters, so three of them could never match anything, and nothing
 * that was not a booking -- payments, refunds, walk-ins, account changes --
 * ever appeared.
 *
 * Entries come from the audit log (everything recorded since audit coverage
 * landed) plus the business tables themselves, so history that predates the
 * audit log still shows up. Each source contributes at most $perSource rows;
 * they are merged, sorted by time and trimmed.
 */

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/audit_view.php';

/** @return list<array<string, mixed>> */
function activity_feed_from_audit(PDO $pdo, int $perSource): array
{
    $stmt = $pdo->prepare(
        'SELECT action_type, table_name, record_id, actor_type, actor_label, created_at
         FROM audit_logs
         ORDER BY created_at DESC, log_id DESC
         LIMIT :limit'
    );
    $stmt->bindValue(':limit', $perSource, PDO::PARAM_INT);
    $stmt->execute();

    $items = [];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $actionType = (string)($row['action_type'] ?? '');
        $category = audit_event_category($actionType, $row['table_name'] ?? null);
        $actor = trim((string)($row['actor_label'] ?? '')) !== ''
            ? (string)$row['actor_label']
            : (trim((string)($row['actor_type'] ?? '')) !== '' ? (string)$row['actor_type'] : 'System');

        $details = [];
        if (($row['table_name'] ?? null) !== null && (string)$row['table_name'] !== '') {
            $details[] = (string)$row['table_name'];
        }
        if (($row['record_id'] ?? null) !== null && (string)$row['record_id'] !== '') {
            $details[] = '#' . $row['record_id'];
        }

        $items[] = [
            'icon' => activity_feed_icon($category),
            'title' => activity_feed_audit_title($actionType, $row['table_name'] ?? null),
            'description' => 'by ' . $actor . ($details === [] ? '' : ' (' . implode(' ', $details) . ')'),
            'time' => $row['created_at'],
            'category' => $category,
            'source' => 'audit',
            // Lets a table-sourced duplicate of the same event be dropped.
            'dedupeKey' => strtolower((string)($row['table_name'] ?? '')) . '#' . (string)($row['record_id'] ?? ''),
        ];
    }

    return $items;
}

/**
 * A bare action type reads as "Create" in the feed, which says nothing about
 * what was created. Name the thing when the action alone is ambiguous.
 */
function activity_feed_audit_title(string $actionType, ?string $tableName): string
{
    $title = audit_event_title($actionType);
    $subject = [
        'appointments' => 'appointment',
        'appointment_payments' => 'payment',
        'appointment_payment_intents' => 'payment intent',
        'appointment_refunds' => 'refund',
        'walkin_queue' => 'walk-in',
        'users' => 'user',
        'staff_users' => 'staff account',
        'barbers' => 'barber',
        'services' => 'service',
        'hairstyles' => 'hairstyle',
        'payments' => 'payment',
    ][strtolower((string)$tableName)] ?? null;

    if ($subject === null) {
        return $title;
    }
    // Already mentions its subject (e.g. "User delete", "Payment captured").
    if (str_contains(strtolower($title), $subject)) {
        return $title;
    }

    return $title . ' — ' . $subject;
}

function activity_feed_icon(string $category): string
{
    return [
        'money' => '💸',
        'appointments' => '📅',
        'users' => '👤',
        'services' => '✂️',
    ][$category] ?? '⚙️';
}

/**
 * Business-table sources, so the feed is not empty on a database whose audit
 * coverage only starts today.
 *
 * @return list<array<string, mixed>>
 */
function activity_feed_from_tables(PDO $pdo, int $perSource): array
{
    $items = [];

    $queries = [
        // [sql, row -> item]
        [
            "SELECT a.appointment_id, a.created_at, a.status, u.full_name
             FROM appointments a
             JOIN users u ON u.user_id = a.user_id
             ORDER BY a.created_at DESC
             LIMIT :limit",
            static fn(array $r): array => [
                'icon' => '📅',
                'title' => 'Appointment booked',
                'description' => ($r['full_name'] ?? 'Customer') . ' booked appointment #' . $r['appointment_id'],
                'time' => $r['created_at'],
                'category' => 'appointments',
                'source' => 'appointments',
                'dedupeKey' => 'appointments#' . $r['appointment_id'],
            ],
        ],
        [
            "SELECT payment_ref, total_amount, payment_method, COALESCE(paid_at, created_at) AS at
             FROM payments
             WHERE payment_status = 'Paid'
             ORDER BY COALESCE(paid_at, created_at) DESC
             LIMIT :limit",
            static fn(array $r): array => [
                'icon' => '💸',
                'title' => 'Payment received',
                'description' => '₱' . number_format((float)$r['total_amount'], 2)
                    . ' via ' . ($r['payment_method'] ?? 'Unknown') . ' (' . $r['payment_ref'] . ')',
                'time' => $r['at'],
                'category' => 'money',
                'source' => 'payments',
            ],
        ],
        [
            "SELECT refund_id, amount, status, created_at
             FROM appointment_refunds
             ORDER BY created_at DESC
             LIMIT :limit",
            static fn(array $r): array => [
                'icon' => '💸',
                'title' => 'Refund ' . strtolower((string)($r['status'] ?? 'requested')),
                'description' => '₱' . number_format((float)$r['amount'], 2) . ' refund #' . $r['refund_id'],
                'time' => $r['created_at'],
                'category' => 'money',
                'source' => 'refunds',
            ],
        ],
        [
            "SELECT queue_id, queue_number, status, guest_name, created_at
             FROM walkin_queue
             ORDER BY created_at DESC
             LIMIT :limit",
            static fn(array $r): array => [
                'icon' => '🚶',
                'title' => 'Walk-in ' . strtolower((string)($r['status'] ?? 'queued')),
                'description' => trim((string)($r['guest_name'] ?? '')) !== ''
                    ? (string)$r['guest_name'] . ' — queue #' . $r['queue_number']
                    : 'Queue #' . $r['queue_number'],
                'time' => $r['created_at'],
                'category' => 'appointments',
                'source' => 'walkins',
            ],
        ],
        [
            "SELECT f.rating, f.comment, f.created_at, b.full_name
             FROM barber_feedback f
             LEFT JOIN barbers b ON b.barber_id = f.barber_id
             ORDER BY f.created_at DESC
             LIMIT :limit",
            static fn(array $r): array => [
                'icon' => '⭐',
                'title' => 'Feedback received',
                'description' => str_repeat('★', max(0, min(5, (int)$r['rating'])))
                    . ' for ' . ($r['full_name'] ?? 'a barber')
                    . (trim((string)($r['comment'] ?? '')) !== '' ? ' — "' . $r['comment'] . '"' : ''),
                'time' => $r['created_at'],
                'category' => 'users',
                'source' => 'feedback',
            ],
        ],
    ];

    foreach ($queries as [$sql, $mapper]) {
        try {
            $stmt = $pdo->prepare($sql);
            $stmt->bindValue(':limit', $perSource, PDO::PARAM_INT);
            $stmt->execute();
            foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
                $items[] = $mapper($row);
            }
        } catch (PDOException $e) {
            // A missing optional table must not blank the whole dashboard.
            error_log('Activity feed source skipped: ' . $e->getMessage());
        }
    }

    return $items;
}

/**
 * @return list<array<string, mixed>> Newest first.
 */
function build_recent_activity(PDO $pdo, int $limit = 30, int $perSource = 10): array
{
    $items = array_merge(
        activity_feed_from_audit($pdo, $perSource),
        activity_feed_from_tables($pdo, $perSource)
    );

    usort($items, static function (array $a, array $b): int {
        return strtotime((string)($b['time'] ?? '')) <=> strtotime((string)($a['time'] ?? ''));
    });

    // The audit log and the business tables both know about the same booking,
    // so without this the feed shows every recent appointment twice. Audit
    // entries sort first for equal timestamps only by luck, so prefer them
    // explicitly: they carry the actor.
    $auditKeys = [];
    foreach ($items as $item) {
        if (($item['source'] ?? '') === 'audit' && ($item['dedupeKey'] ?? null) !== null) {
            $auditKeys[$item['dedupeKey']] = true;
        }
    }

    $deduped = [];
    foreach ($items as $item) {
        $key = $item['dedupeKey'] ?? null;
        unset($item['dedupeKey']);
        if ($key !== null && ($item['source'] ?? '') !== 'audit' && isset($auditKeys[$key])) {
            continue;
        }
        $deduped[] = $item;
    }

    return array_slice($deduped, 0, $limit);
}
