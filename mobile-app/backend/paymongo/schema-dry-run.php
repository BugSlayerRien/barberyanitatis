<?php
header('Content-Type: application/json');

// Load environment variables from .env file if it exists
$envFile = __DIR__ . '/.env';
if (file_exists($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) continue; // Skip comments
        if (strpos($line, '=') !== false) {
            list($key, $value) = explode('=', $line, 2);
            $key = trim($key);
            $value = trim($value, '\'\'"');
            if (!getenv($key)) {
                putenv("$key=$value");
            }
        }
    }
}


function get_env($name, $default = null) {
    $value = getenv($name);
    if ($value === false || $value === null || $value === '') {
        return $default;
    }
    return $value;
}

function table_columns(PDO $pdo, $tableName) {
    $stmt = $pdo->prepare("SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = :table ORDER BY ordinal_position");
    $stmt->execute(['table' => $tableName]);
    $cols = $stmt->fetchAll(PDO::FETCH_COLUMN);
    return is_array($cols) ? $cols : [];
}

function choose_first(array $columns, array $candidates) {
    $set = array_fill_keys($columns, true);
    foreach ($candidates as $c) {
        if (isset($set[$c])) {
            return $c;
        }
    }
    return null;
}

try {
    $dbHost = get_env('DB_HOST', '127.0.0.1');
    $dbPort = get_env('DB_PORT', '5432');
    $dbName = get_env('DB_NAME', '');
    $dbUser = get_env('DB_USER', '');
    $dbPass = get_env('DB_PASS', '');
    $sslMode = get_env('DB_SSLMODE', null);

    if ($dbName === '' || $dbUser === '') {
        http_response_code(400);
        echo json_encode([
            'ok' => false,
            'error' => 'Missing DB env. Required: DB_NAME, DB_USER (and usually DB_HOST, DB_PASS).',
        ]);
        exit;
    }

    $dsn = "pgsql:host={$dbHost};port={$dbPort};dbname={$dbName}";
    if ($sslMode) {
        $dsn .= ";sslmode={$sslMode}";
    }

    $pdo = new PDO($dsn, $dbUser, $dbPass, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);

    $tables = ['appointment_payment_intents', 'orders', 'payment_events'];
    $report = [];

    foreach ($tables as $table) {
        $cols = table_columns($pdo, $table);
        $statusCol = choose_first($cols, ['payment_state', 'payment_status', 'intent_status', 'status']);
        $externalMatchCols = array_values(array_filter([
            'intent_id',
            'paymongo_intent_id',
            'external_reference',
            'order_reference',
            'source_id',
            'paymongo_source_id',
        ], function ($c) use ($cols) {
            return in_array($c, $cols, true);
        }));

        $metaMatchCols = array_values(array_filter([
            'appointment_id',
            'order_id',
            'id',
            'external_reference',
            'order_reference',
        ], function ($c) use ($cols) {
            return in_array($c, $cols, true);
        }));

        $report[$table] = [
            'exists' => !empty($cols),
            'columns' => $cols,
            'chosen_status_column' => $statusCol,
            'external_match_columns' => $externalMatchCols,
            'metadata_match_columns' => $metaMatchCols,
        ];
    }

    echo json_encode([
        'ok' => true,
        'db' => [
            'host' => $dbHost,
            'port' => $dbPort,
            'name' => $dbName,
            'sslmode' => $sslMode,
        ],
        'write_priority' => ['appointment_payment_intents', 'orders', 'payment_events'],
        'tables' => $report,
    ]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'error' => 'DB connection/query failed.',
        'details' => $e->getMessage(),
    ]);
}
