<?php
require_once __DIR__ . '/../api/db.php';
try {
    $pdo = get_db_connection();
    $stmt = $pdo->prepare("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND lower(table_name) LIKE 'audit%';");
    $stmt->execute();
    $tables = $stmt->fetchAll(PDO::FETCH_COLUMN);

    $s = $pdo->prepare("SELECT count(*) FROM services;");
    $s->execute();
    $total_services = $s->fetchColumn();

    $a = $pdo->prepare("SELECT count(*) FROM services WHERE is_active = TRUE;");
    $a->execute();
    $active_services = $a->fetchColumn();

    $listStmt = $pdo->prepare("SELECT * FROM services ORDER BY service_name");
    try {
        $listStmt->execute();
        $services_list = $listStmt->fetchAll();
    } catch (Exception $e) {
        $services_list = [];
    }

    $audit_columns = [];
    if (!empty($tables)) {
        try {
            $colStmt = $pdo->prepare("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = :t");
            $colStmt->execute([':t' => $tables[0]]);
            $audit_columns = $colStmt->fetchAll(PDO::FETCH_COLUMN);
            $countStmt = $pdo->prepare("SELECT count(*) FROM \"{$tables[0]}\"");
            try {
                $countStmt->execute();
                $audit_count = (int)$countStmt->fetchColumn();
            } catch (Exception $e) {
                $audit_count = null;
            }
        } catch (Exception $e) {
            $audit_columns = ['error' => $e->getMessage()];
        }
    }

    echo json_encode([
        'tables' => $tables,
        'total_services' => $total_services,
        'active_services' => $active_services,
        'services' => $services_list,
        'audit_columns' => $audit_columns,
        'audit_count' => $audit_count ?? 0,
    ]);
} catch (Exception $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
