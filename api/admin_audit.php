<?php
// Admin audit API

declare(strict_types=1);
require_once __DIR__ . '/db.php';
require_once __DIR__ . '/admin_auth.php';

require_method('GET');

try {
    $pdo = get_db_connection();
    // Server-side admin gate. The portal UI checks sessionStorage, which is
    // client-side only -- without this, anyone who can reach the API could
    // read or change admin data with a plain HTTP request.
    require_admin($pdo);
    // Find an audit table present in the DB (support multiple legacy naming conventions)
    $tableStmt = $pdo->prepare(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND lower(table_name) LIKE 'audit%';"
    );
    $tableStmt->execute();
    $tables = $tableStmt->fetchAll(PDO::FETCH_COLUMN);

    if (empty($tables)) {
        json_response(['events' => []]);
    }

    $auditTable = $tables[0];

    // Discover columns for mapping
    $colStmt = $pdo->prepare('SELECT column_name FROM information_schema.columns WHERE table_schema = :schema AND table_name = :table');
    $colStmt->execute([':schema' => 'public', ':table' => $auditTable]);
    $cols = array_map('strtolower', $colStmt->fetchAll(PDO::FETCH_COLUMN));

    // Helper to pick first matching column name from candidates
    $pick = function (array $candidates) use ($cols) {
        foreach ($candidates as $c) {
            if (in_array(strtolower($c), $cols, true)) return $c;
        }
        return null;
    };

    $map = [
        'log_id' => $pick(['log_id', 'logid', 'id']),
        'action_type' => $pick(['action_type', 'action', 'actiontype']),
        'table_name' => $pick(['table_name', 'table_changed', 'tablechanged', 'tablechanged', 'tablechanged']),
        'record_id' => $pick(['record_id', 'recordid', 'record_id']),
        'old_values' => $pick(['old_values', 'oldvalue', 'old_value', 'oldvalues']),
        'new_values' => $pick(['new_values', 'newvalue', 'new_value', 'newvalues']),
        'user_id' => $pick(['user_id', 'userid', 'user']),
        'created_at' => $pick(['created_at', 'timestamp', 'time', 'createdat']),
    ];

    // Build select list with aliases
    $selectParts = [];
    foreach ($map as $alias => $colName) {
        if ($colName !== null) {
            $selectParts[] = sprintf('"%s" AS %s', $colName, $alias);
        }
    }

    if (empty($selectParts)) {
        json_response(['events' => []]);
    }

    $orderBy = $map['created_at'] ?? $map['log_id'] ?? $map['action_type'];
    $sql = sprintf('SELECT %s FROM "%s" ORDER BY "%s" DESC LIMIT 200', implode(', ', $selectParts), $auditTable, $orderBy);

    $stmt = $pdo->prepare($sql);
    $stmt->execute();
    $rows = $stmt->fetchAll();

    $events = array_map(function (array $row): array {
        $details = [];
        if (!empty($row['table_name'])) {
            $details[] = 'table: ' . $row['table_name'];
        }
        if (!empty($row['record_id'])) {
            $details[] = 'record: ' . $row['record_id'];
        }

        return [
            'title' => $row['action_type'] ?? 'Audit Event',
            'description' => trim(implode(' | ', $details)),
            'time' => $row['created_at'] ?? ($row['timestamp'] ?? null),
        ];
    }, $rows);

    json_response(['events' => $events]);
} catch (PDOException $e) {
    json_response(['error' => 'Database error', 'details' => $e->getMessage()], 500);
}
