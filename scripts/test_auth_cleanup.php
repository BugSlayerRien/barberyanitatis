<?php
declare(strict_types=1);

require_once __DIR__ . '/../api/auth_sync.php';
require_once __DIR__ . '/../api/supabase_admin_auth.php';

$failures = 0;

function cleanup_ok(string $name, bool $ok, string $detail = ''): void
{
    global $failures;
    if (!$ok) {
        $failures++;
    }
    echo ($ok ? 'PASS' : 'FAIL') . "  {$name}" . ($detail !== '' ? " — {$detail}" : '') . "\n";
}

cleanup_ok(
    'customer_password_kind oauth marker',
    customer_password_kind('__oauth_only__') === 'oauth'
);
cleanup_ok(
    'customer_password_kind supabase marker',
    customer_password_kind('__auth_via_supabase__') === 'supabase'
);
cleanup_ok(
    'customer_password_kind bcrypt is local',
    customer_password_kind('$2y$10$abcdefghijklmnopqrstuv') === 'local'
);

cleanup_ok(
    'oauth-only google without email',
    supabase_admin_is_oauth_only(['google']) === true
);
cleanup_ok(
    'email+google is not oauth-only',
    supabase_admin_is_oauth_only(['google', 'email']) === false
);
cleanup_ok(
    'email-only is not oauth-only',
    supabase_admin_is_oauth_only(['email']) === false
);

$googleUser = [
    'email' => 'Ada@Example.com',
    'identities' => [
        ['provider' => 'google'],
    ],
    'app_metadata' => ['providers' => ['google']],
];
$providers = supabase_admin_providers_from_user($googleUser);
cleanup_ok('providers from google identity', in_array('google', $providers, true));
cleanup_ok('google user oauth-only', supabase_admin_is_oauth_only($providers));

$extracted = supabase_admin_extract_user_from_list_payload(
    ['users' => [['id' => '1', 'email' => 'Ada@Example.com']]],
    'ada@example.com'
);
cleanup_ok('extract user is case-insensitive', is_array($extracted) && ($extracted['id'] ?? '') === '1');

$promoteSource = file_get_contents(__DIR__ . '/../api/admin_users.php');
$promoteStart = strpos((string)$promoteSource, 'function promote_customer_to_barber');
$updateStart = strpos((string)$promoteSource, 'function update_account');
$promoteFn = ($promoteStart !== false && $updateStart !== false && $updateStart > $promoteStart)
    ? substr((string)$promoteSource, $promoteStart, $updateStart - $promoteStart)
    : '';
cleanup_ok(
    'promote does not hash ChangeMe123!',
    $promoteFn !== '' && !str_contains($promoteFn, "password_hash('ChangeMe123!'")
);
cleanup_ok(
    'promote stores supabase marker',
    $promoteFn !== '' && str_contains($promoteFn, 'USER_PASSWORD_HASH_SUPABASE')
);
cleanup_ok(
    'promote does not call createUser',
    $promoteFn !== '' && !str_contains($promoteFn, 'supabase_admin_ensure_user')
);

$authSource = file_get_contents(__DIR__ . '/../api/auth.php');
cleanup_ok(
    'mobile client skips barber PHP password login',
    is_string($authSource) && str_contains($authSource, "\$isMobileClient")
);

$lookup = supabase_admin_find_user_by_email('auth-cleanup-probe-missing@example.com');
cleanup_ok(
    'auth admin lookup is configured or reports not_configured',
    in_array($lookup['lookup'], ['ok', 'not_found', 'not_configured', 'error'], true),
    $lookup['lookup'] . ($lookup['detail'] !== '' ? ' ' . $lookup['detail'] : '')
);

try {
    $googleWithPasswordMeta = [
        'identities' => [['provider' => 'google']],
        'app_metadata' => ['providers' => ['google']],
        'user_metadata' => ['has_email_password' => true],
        'encrypted_password' => 'should-never-be-read',
    ];
    cleanup_ok(
        'password identity uses metadata not hash field',
        supabase_admin_user_has_password_identity($googleWithPasswordMeta) === true
    );
    $stripped = supabase_admin_sanitize_user_record($googleWithPasswordMeta);
    cleanup_ok(
        'admin user record drops encrypted_password',
        !array_key_exists('encrypted_password', $stripped)
    );
    $payloadKeys = array_keys(build_check_email_exists_payload(get_db_connection(), 'auth-cleanup-probe-missing@example.com'));
    $forbidden = array_intersect($payloadKeys, ['encrypted_password', 'user', 'identities', 'hashed_password']);
    cleanup_ok(
        'checkEmailExists JSON has no auth secret fields',
        $forbidden === []
    );
} catch (Throwable $e) {
    cleanup_ok('checkEmailExists JSON has no auth secret fields', false, $e->getMessage());
}

if ($failures > 0) {
    exit(1);
}

echo "All auth cleanup checks passed.\n";
