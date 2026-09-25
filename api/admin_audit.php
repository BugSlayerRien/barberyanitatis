<?php
// Admin audit API

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';
require_once __DIR__ . '/audit_view.php';

require_method('GET');

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);

    $exists = $pdo->query(
        "SELECT 1 FROM information_schema.tables
         WHERE table_schema = 'public' AND table_name = 'audit_logs' LIMIT 1"
    )->fetchColumn();
    if ($exists === false) {
        json_response(['events' => [], 'total' => 0, 'page' => 1, 'perPage' => 0]);
    }

    schema_ensure_once('audit_logs.actor', static function () use ($pdo): void {
        ensure_audit_actor_columns($pdo);
    });

    $perPage = (int)($_GET['perPage'] ?? 100);
    $perPage = max(1, min(200, $perPage));
    $page = max(1, (int)($_GET['page'] ?? 1));
    $search = trim((string)($_GET['search'] ?? ''));
    $category = strtolower(trim((string)($_GET['category'] ?? 'all')));
    $actorType = strtolower(trim((string)($_GET['actorType'] ?? '')));

    // Filtering happens in SQL so a search reaches the whole history, not just
    // whatever the old hard 200-row cap happened to include.
    $where = [];
    $params = [];
    if ($search !== '') {
        $where[] = '(action_type ILIKE :search OR table_name ILIKE :search OR record_id ILIKE :search
                     OR actor_label ILIKE :search OR old_values ILIKE :search OR new_values ILIKE :search)';
        $params[':search'] = '%' . $search . '%';
    }
    if ($actorType !== '' && $actorType !== 'all') {
        $where[] = 'LOWER(actor_type) = :actor_type';
        $params[':actor_type'] = $actorType;
    }
    $whereSql = $where === [] ? '' : ' WHERE ' . implode(' AND ', $where);

    $countStmt = $pdo->prepare("SELECT COUNT(*) FROM audit_logs{$whereSql}");
    $countStmt->execute($params);
    $total = (int)$countStmt->fetchColumn();

    $stmt = $pdo->prepare(
        "SELECT log_id, action_type, table_name, record_id, old_values, new_values,
                user_id, actor_type, actor_id, actor_label, ip_address, created_at
         FROM audit_logs{$whereSql}
         ORDER BY created_at DESC, log_id DESC
         LIMIT :limit OFFSET :offset"
    );
    foreach ($params as $key => $value) {
        $stmt->bindValue($key, $value);
    }
    $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
    $stmt->bindValue(':offset', ($page - 1) * $perPage, PDO::PARAM_INT);
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $events = [];
    foreach ($rows as $row) {
        $actionType = (string)($row['action_type'] ?? '');
        $tableName = $row['table_name'] !== null ? (string)$row['table_name'] : null;
        $rowCategory = audit_event_category($actionType, $tableName);
        if ($category !== '' && $category !== 'all' && $rowCategory !== $category) {
            continue;
        }

        $old = audit_decode_values($row['old_values'] ?? null);
        $new = audit_decode_values($row['new_values'] ?? null);
        $changes = audit_event_changes($old, $new);

        $actorLabel = trim((string)($row['actor_label'] ?? ''));
        $actorType = trim((string)($row['actor_type'] ?? ''));
        $who = $actorLabel !== ''
            ? ($actorType !== '' ? $actorLabel . ' (' . $actorType . ')' : $actorLabel)
            : ($actorType !== '' ? $actorType : 'Unknown');

        $descriptionParts = [];
        if ($tableName !== null && $tableName !== '') {
            $descriptionParts[] = 'table: ' . $tableName;
        }
        if (($row['record_id'] ?? null) !== null && (string)$row['record_id'] !== '') {
            $descriptionParts[] = 'record: ' . $row['record_id'];
        }
        $descriptionParts[] = 'by: ' . $who;
        foreach (array_slice($changes, 0, 3) as $change) {
            $descriptionParts[] = sprintf(
                '%s: %s -> %s',
                $change['field'],
                $change['from'] === null ? '-' : (string)json_encode($change['from']),
                $change['to'] === null ? '-' : (string)json_encode($change['to'])
            );
        }

        $events[] = [
            'logID' => (int)$row['log_id'],
            'title' => audit_event_title($actionType),
            'actionType' => $actionType,
            'description' => implode(' | ', $descriptionParts),
            'category' => $rowCategory,
            'table' => $tableName,
            'recordID' => $row['record_id'],
            'actor' => [
                'type' => $actorType !== '' ? $actorType : null,
                'id' => $row['actor_id'] !== null ? (int)$row['actor_id'] : null,
                'label' => $actorLabel !== '' ? $actorLabel : null,
                'display' => $who,
            ],
            'userID' => $row['user_id'] !== null ? (int)$row['user_id'] : null,
            'changes' => $changes,
            'oldValues' => $old,
            'newValues' => $new,
            'ipAddress' => $row['ip_address'],
            'time' => $row['created_at'],
        ];
    }

    json_response([
        'events' => $events,
        'total' => $total,
        'page' => $page,
        'perPage' => $perPage,
    ]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
