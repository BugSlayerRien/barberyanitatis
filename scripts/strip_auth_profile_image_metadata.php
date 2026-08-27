<?php
/**
 * Strip profile_image_base64 from Supabase Auth user_metadata (raw_user_meta_data).
 *
 * That JPEG was being copied into every access token (~102 KB) and rejected by
 * Cloudflare/Apache request-header limits. Other metadata keys are preserved.
 *
 * CLI only. Lists/verifies with the service role. Apply uses SQL
 * `raw_user_meta_data - 'profile_image_base64'` because the Auth Admin PUT
 * merges metadata and cannot delete the key. Never send the service role to
 * Flutter; never commit it.
 *
 * Dry-run (default):
 *   php scripts/strip_auth_profile_image_metadata.php
 *
 * Apply:
 *   php scripts/strip_auth_profile_image_metadata.php --apply
 *
 * Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE / SUPABASE_SERVICE_ROLE_KEY from
 * the repo .env, or --supabase-url / --service-role.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    fwrite(STDERR, "Run this script from the command line only.\n");
    exit(1);
}

require_once dirname(__DIR__) . '/api/db.php';
load_project_env();

$opts = getopt('', ['apply', 'dry-run', 'supabase-url::', 'service-role::', 'per-page::', 'help']);
if (isset($opts['help'])) {
    echo file_get_contents(__FILE__, false, null, 0, 900);
    exit(0);
}

$apply = isset($opts['apply']);
$supabaseUrl = trim((string)($opts['supabase-url'] ?? getenv('SUPABASE_URL') ?: ''));
$serviceRole = trim((string)($opts['service-role'] ?? getenv('SUPABASE_SERVICE_ROLE') ?: getenv('SUPABASE_SERVICE_ROLE_KEY') ?: ''));
$perPage = isset($opts['per-page']) ? max(1, min(200, (int)$opts['per-page'])) : 50;

$supabaseUrl = trim($supabaseUrl, "\"'");
$serviceRole = trim($serviceRole, "\"'");

if ($supabaseUrl === '' || $serviceRole === '') {
    fwrite(STDERR, "ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE[_KEY] are required.\n");
    exit(2);
}

function strip_auth_curl(string $method, string $url, string $serviceRole, ?array $jsonBody = null): array
{
    $ch = curl_init($url);
    $headers = [
        'apikey: ' . $serviceRole,
        'Authorization: Bearer ' . $serviceRole,
        'Content-Type: application/json',
    ];
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
    curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);
    curl_setopt($ch, CURLOPT_TIMEOUT, 60);
    if ($jsonBody !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($jsonBody, JSON_UNESCAPED_SLASHES));
    }
    $raw = curl_exec($ch);
    $errno = curl_errno($ch);
    $err = curl_error($ch);
    $status = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($errno !== 0) {
        throw new RuntimeException("Network error: {$err}");
    }

    $decoded = is_string($raw) && $raw !== '' ? json_decode($raw, true) : null;

    return [
        'status' => $status,
        'raw' => is_string($raw) ? $raw : '',
        'json' => is_array($decoded) ? $decoded : null,
    ];
}

/**
 * @return list<array<string, mixed>>
 */
function strip_auth_list_page(string $supabaseUrl, string $serviceRole, int $page, int $perPage): array
{
    $url = rtrim($supabaseUrl, '/') . '/auth/v1/admin/users?page=' . $page . '&per_page=' . $perPage;
    $res = strip_auth_curl('GET', $url, $serviceRole);
    if ($res['status'] < 200 || $res['status'] >= 300) {
        throw new RuntimeException('List users HTTP ' . $res['status'] . ': ' . substr($res['raw'], 0, 300));
    }
    $json = $res['json'] ?? [];
    $users = $json['users'] ?? $json;
    if (!is_array($users)) {
        return [];
    }

    return array_values(array_filter($users, 'is_array'));
}

function strip_auth_sql_remove_blob(PDO $pdo): int
{
    $stmt = $pdo->query(
        "UPDATE auth.users
         SET raw_user_meta_data = (raw_user_meta_data - 'profile_image_base64' - 'profileImageBase64'),
             updated_at = NOW()
         WHERE jsonb_exists(raw_user_meta_data, 'profile_image_base64')
            OR jsonb_exists(raw_user_meta_data, 'profileImageBase64')"
    );

    return $stmt !== false ? $stmt->rowCount() : 0;
}

$scanned = 0;
$affected = 0;
$updated = 0;
$skipped = 0;
$failed = 0;

echo $apply ? "APPLY: stripping profile_image_base64 from Auth metadata\n" : "DRY RUN: no Auth users will be updated (pass --apply to write)\n";
echo 'Project: ' . $supabaseUrl . "\n";

$page = 1;
while (true) {
    $users = strip_auth_list_page($supabaseUrl, $serviceRole, $page, $perPage);
    if ($users === []) {
        break;
    }

    foreach ($users as $user) {
        $scanned++;
        $email = trim((string)($user['email'] ?? ''));
        $id = trim((string)($user['id'] ?? ''));
        $meta = $user['user_metadata'] ?? [];
        if (!is_array($meta)) {
            $meta = [];
        }

        $hasBlob = array_key_exists('profile_image_base64', $meta)
            || array_key_exists('profileImageBase64', $meta);
        if (!$hasBlob) {
            $skipped++;
            continue;
        }

        $blob = $meta['profile_image_base64'] ?? $meta['profileImageBase64'] ?? '';
        $blobLen = is_string($blob) ? strlen($blob) : 0;
        $affected++;
        $label = $email !== '' ? $email : $id;
        echo "  {$label} has profile_image_base64 ({$blobLen} chars)\n";
    }

    if (count($users) < $perPage) {
        break;
    }
    $page++;
}

if ($apply && $affected > 0) {
    echo "Removing key via auth.users.raw_user_meta_data...\n";
    try {
        $pdo = get_db_connection();
        $updated = strip_auth_sql_remove_blob($pdo);
        echo "SQL updated {$updated} auth.users row(s).\n";

        echo "Re-checking Auth Admin API...\n";
        $page = 1;
        $still = 0;
        while (true) {
            $users = strip_auth_list_page($supabaseUrl, $serviceRole, $page, $perPage);
            if ($users === []) {
                break;
            }
            foreach ($users as $user) {
                $meta = is_array($user['user_metadata'] ?? null) ? $user['user_metadata'] : [];
                if (array_key_exists('profile_image_base64', $meta) || array_key_exists('profileImageBase64', $meta)) {
                    $still++;
                    echo '  STILL PRESENT: ' . trim((string)($user['email'] ?? $user['id'] ?? '')) . "\n";
                }
            }
            if (count($users) < $perPage) {
                break;
            }
            $page++;
        }
        if ($still > 0) {
            $failed = $still;
        }
    } catch (Throwable $e) {
        fwrite(STDERR, 'SQL cleanup failed: ' . $e->getMessage() . "\n");
        $failed++;
    }
}

echo "Scanned: {$scanned}\n";
echo "Had profile_image_base64: {$affected}\n";
echo "Already clean: {$skipped}\n";
echo 'Updated: ' . ($apply ? (string)$updated : '0 (dry-run)') . "\n";
echo "Failed: {$failed}\n";

exit($failed > 0 ? 1 : 0);
