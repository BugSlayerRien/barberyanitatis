<?php
declare(strict_types=1);

// Provision demo users into Supabase Auth via Admin API.
// Usage:
//  SUPABASE_URL=https://<project>.supabase.co SUPABASE_SERVICE_ROLE=<service_role_key> php scripts/provision_auth_users.php
// Or pass args: --supabase-url=... --service-role=...

$shortopts = '';
$longopts = ['supabase-url::', 'service-role::', 'default-password::', 'dry-run', 'help'];
$opts = getopt($shortopts, $longopts);

if (isset($opts['help'])) {
    echo "Provision Supabase Auth users for seeded demo accounts.\n";
    echo "Options:\n  --supabase-url    Supabase project URL (or set SUPABASE_URL)\n  --service-role    Service Role key (or set SUPABASE_SERVICE_ROLE)\n  --default-password  Password to use for users without known mapping\n  --dry-run         Show actions without calling API\n";
    exit(0);
}

$supabaseUrl = $opts['supabase-url'] ?? getenv('SUPABASE_URL') ?: getenv('NEXT_PUBLIC_SUPABASE_URL');
$serviceRole = $opts['service-role'] ?? getenv('SUPABASE_SERVICE_ROLE') ?: getenv('SUPABASE_SERVICE_ROLE_KEY');
$defaultPassword = $opts['default-password'] ?? getenv('PROVISION_DEFAULT_PASSWORD') ?: null;
$dryRun = array_key_exists('dry-run', $opts);

if (!$supabaseUrl || !$serviceRole) {
    fwrite(STDERR, "ERROR: Supabase URL and Service Role key are required.\n");
    fwrite(STDERR, "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE environment variables or pass via args.\n");
    exit(2);
}

require_once __DIR__ . '/../api/db.php';

// Known seed emails -> their demo plaintext passwords.
$seedPasswords = [
    'admin@tatis.local' => 'Admin123!',
    'receptionist@tatis.local' => 'Reception123!',
    'barber@tatis.local' => 'Barber123!',
    'customer@tatis.local' => 'Customer123!',
];

$pdo = get_db_connection();
$stmt = $pdo->query("SELECT email, full_name FROM users WHERE is_active = TRUE ORDER BY email");
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (!$rows) {
    echo "No active users found in public.users table.\n";
    exit(0);
}

echo "Found " . count($rows) . " users to consider for provisioning.\n";

foreach ($rows as $row) {
    $email = trim($row['email']);
    if ($email === '') continue;

    $password = $seedPasswords[$email] ?? $defaultPassword;
    if ($password === null) {
        echo "Skipping $email — no known password mapping. Provide --default-password to set one.\n";
        continue;
    }

    $payload = [
        'email' => $email,
        'password' => $password,
        'email_confirm' => true,
        'user_metadata' => [ 'full_name' => $row['full_name'] ?? null ],
    ];

    $url = rtrim($supabaseUrl, '/') . '/auth/v1/admin/users';

    echo ($dryRun ? "DRY RUN: would POST $email\n" : "Creating/updating auth user: $email\n");

    if ($dryRun) continue;

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Content-Type: application/json',
        'apikey: ' . $serviceRole,
        'Authorization: Bearer ' . $serviceRole,
    ]);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($payload));
    $resp = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err = curl_error($ch);
    curl_close($ch);

    if ($err) {
        echo "Network error for $email: $err\n";
        continue;
    }

    if ($httpCode >= 200 && $httpCode < 300) {
        echo "OK: provisioned $email (HTTP $httpCode)\n";
    } else {
        $msg = $resp ?: 'Empty response';
        echo "WARN: failed to provision $email — HTTP $httpCode — $msg\n";
    }
}

echo "Done. Review output above for errors.\n";
