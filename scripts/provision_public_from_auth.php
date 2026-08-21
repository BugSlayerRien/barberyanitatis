<?php
/**
 * Provision public.users records from Supabase Auth admin users list.
 * Usage:
 *  SUPABASE_URL=https://<project>.supabase.co SUPABASE_SERVICE_ROLE=<service_role_key> php scripts/provision_public_from_auth.php
 * Options: --dry-run
 */
declare(strict_types=1);
$shortopts = '';
$longopts = ['supabase-url::', 'service-role::', 'per-page::', 'dry-run', 'help'];
$opts = getopt($shortopts, $longopts);
if (isset($opts['help'])) {
    echo "Provision public.users from Supabase Auth admin users list.\n";
    echo "Options:\n  --supabase-url    Supabase project URL (or set SUPABASE_URL)\n  --service-role    Service Role key (or set SUPABASE_SERVICE_ROLE)\n  --per-page        Number of users to fetch per request (default 100)\n  --dry-run         Show actions without DB changes\n";
    exit(0);
}
$supabaseUrl = $opts['supabase-url'] ?? getenv('SUPABASE_URL') ?: getenv('NEXT_PUBLIC_SUPABASE_URL');
$serviceRole = $opts['service-role'] ?? getenv('SUPABASE_SERVICE_ROLE') ?: getenv('SUPABASE_SERVICE_ROLE_KEY');
$perPage = (int)($opts['per-page'] ?? getenv('PROVISION_PER_PAGE') ?: 100);
$dryRun = array_key_exists('dry-run', $opts);
if (!$supabaseUrl || !$serviceRole) {
    fwrite(STDERR, "ERROR: Supabase URL and Service Role key are required.\n");
    exit(2);
}
require_once __DIR__ . '/../api/db.php';
$pdo = get_db_connection();
$offset = 0;
$totalCreated = 0;
echo "Connecting to Supabase Auth API...\n";
while (true) {
    $url = rtrim($supabaseUrl, '/') . "/auth/v1/admin/users?per_page={$perPage}&offset={$offset}";
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'apikey: ' . $serviceRole,
        'Authorization: Bearer ' . $serviceRole,
    ]);
    $resp = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);
    echo "Fetching users (offset={$offset})... HTTP {$httpCode}\n";
    if ($err) {
        echo "Network error: $err\n";
        break;
    }
    if ($httpCode < 200 || $httpCode >= 300) {
        echo "HTTP $httpCode when fetching users: " . substr($resp, 0, 200) . "\n";
        break;
    }
    $decoded = json_decode($resp, true);
    $users = isset($decoded['users']) && is_array($decoded['users']) ? $decoded['users'] : (is_array($decoded) ? $decoded : []);
    if (!is_array($users) || count($users) === 0) {
        echo "No users found.\n";
        break;
    }
    echo "Found " . count($users) . " user(s).\n";
    echo "Users array type: " . gettype($users) . "\n";
    echo "First 3 keys: " . implode(", ", array_slice(array_keys($users), 0, 3)) . "\n";
    if ($dryRun && count($users) > 0) {
        echo "First user structure: " . substr(json_encode($users[0] ?? reset($users)), 0, 400) . "\n";
    }
    foreach ($users as $u) {
        $email = trim((string)($u['email'] ?? ''));
        $fullName = trim((string)($u['user_metadata']['full_name'] ?? ($u['user_metadata']['name'] ?? '')));
        if ($email === '') {
            echo "  [Skip: empty email]\n";
            continue;
        }
        echo "  Checking {$email} ... ";
        $check = $pdo->prepare('SELECT user_id FROM users WHERE lower(email) = lower(?)');
        $check->execute([$email]);
        $existing = $check->fetchColumn();
        if ($existing) {
            echo "EXISTS (user_id={$existing})\n";
            continue;
        }
        echo "MISSING\n";
        echo ($dryRun ? "DRY RUN: would create public.users\n" : "Creating public.users... ");
        if ($dryRun) continue;
        $stmt = $pdo->prepare('INSERT INTO users (email, full_name, password_hash, is_active) VALUES (?, ?, ?, TRUE) RETURNING user_id');
        try {
            $stmt->execute([$email, $fullName, '__auth_via_supabase__']);
            $id = $stmt->fetchColumn();
            echo "OK (user_id={$id})\n";
            $totalCreated++;
        } catch (Throwable $e) {
            echo "FAILED: " . $e->getMessage() . "\n";
        }
    }
    if (count($users) < $perPage) break;
    $offset += $perPage;
}
echo "Done. Created {$totalCreated} users.\n";
