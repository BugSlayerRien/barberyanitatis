<?php
declare(strict_types=1);

/**
 * Provider abstraction for AI hairstyle try-on image generation. face_scan.php should
 * only ever call ai_tryon_generate_three_view_previews() — swapping providers (Gemini,
 * Grok, Replicate, etc.) never requires touching the API contract or the mobile client.
 */

require_once __DIR__ . '/replicate_helper.php';
require_once __DIR__ . '/ai_gemini_image_helper.php';
require_once __DIR__ . '/ai_grok_image_helper.php';

function ai_tryon_provider_name(): string
{
    $configured = strtolower(trim((string)(
        getenv('AI_TRYON_PROVIDER') ?: ($_ENV['AI_TRYON_PROVIDER'] ?? '')
    )));
    if (in_array($configured, ['gemini', 'grok', 'replicate'], true)) {
        return $configured;
    }
    if (gemini_image_is_configured()) {
        return 'gemini';
    }
    if (grok_image_is_configured()) {
        return 'grok';
    }
    if (replicate_is_configured()) {
        return 'replicate';
    }
    return 'none';
}

function ai_tryon_is_configured(): bool
{
    return gemini_image_is_configured() || grok_image_is_configured() || replicate_is_configured();
}

/**
 * True when AI_TRYON_PROVIDER is explicitly set to a cloud image provider that should
 * bypass the Python sidecar for generation (sidecar still used for face analysis).
 */
function ai_tryon_prefers_cloud_provider(): bool
{
    $configured = strtolower(trim((string)(
        getenv('AI_TRYON_PROVIDER') ?: ($_ENV['AI_TRYON_PROVIDER'] ?? '')
    )));
    return in_array($configured, ['gemini', 'grok'], true);
}

/**
 * When AI_TRYON_PROVIDER is explicitly set (gemini|grok|replicate), fail on that
 * provider instead of silently burning credits on another (e.g. Replicate).
 * Set AI_TRYON_ALLOW_FALLBACK=true to restore cross-provider fallbacks.
 */
function ai_tryon_allow_fallback(): bool
{
    $configured = strtolower(trim((string)(
        getenv('AI_TRYON_PROVIDER') ?: ($_ENV['AI_TRYON_PROVIDER'] ?? '')
    )));
    // Auto mode (blank provider) may still chain providers.
    if ($configured === '' || !in_array($configured, ['gemini', 'grok', 'replicate'], true)) {
        return true;
    }
    $raw = strtolower(trim((string)(
        getenv('AI_TRYON_ALLOW_FALLBACK') ?: ($_ENV['AI_TRYON_ALLOW_FALLBACK'] ?? '')
    )));
    return in_array($raw, ['1', 'true', 'yes', 'on'], true);
}

/**
 * Generate front/left/right try-on images using the configured provider, with fallbacks
 * to other configured providers on failure (only when allowed — see ai_tryon_allow_fallback).
 *
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array{ok: bool, images: array<string, string>, feasibleToday: bool, lengthNote: ?string, error: string, provider: string}
 */
function ai_tryon_generate_three_view_previews(
    array $capturePaths,
    string $styleName,
    ?string $styleCode,
    int $hairLengthLevel,
    string $hairColorLabel
): array {
    $provider = ai_tryon_provider_name();
    $allowFallback = ai_tryon_allow_fallback();

    if ($provider === 'grok') {
        $result = grok_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
        if ($result['ok']) {
            $result['provider'] = 'grok';
            return $result;
        }
        error_log('ai_tryon_provider: Grok failed (' . $result['error'] . ')'
            . ($allowFallback ? ', trying fallbacks.' : ' — fallbacks disabled (AI_TRYON_PROVIDER=grok).'));

        if ($allowFallback && gemini_image_is_configured()) {
            $fallback = gemini_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
            if ($fallback['ok']) {
                $fallback['provider'] = 'gemini';
                return $fallback;
            }
            error_log('ai_tryon_provider: Gemini fallback failed (' . $fallback['error'] . ').');
        }

        if ($allowFallback && replicate_is_configured()) {
            $fallback = replicate_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
            $fallback['provider'] = 'replicate';
            return $fallback;
        }

        $result['provider'] = 'grok';
        return $result;
    }

    if ($provider === 'gemini') {
        $result = gemini_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
        if ($result['ok']) {
            $result['provider'] = 'gemini';
            return $result;
        }

        error_log('ai_tryon_provider: Gemini failed (' . $result['error'] . ')'
            . ($allowFallback ? ', trying fallbacks.' : ' — fallbacks disabled (AI_TRYON_PROVIDER=gemini).'));

        if ($allowFallback && grok_image_is_configured()) {
            $fallback = grok_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
            if ($fallback['ok']) {
                $fallback['provider'] = 'grok';
                return $fallback;
            }
            error_log('ai_tryon_provider: Grok fallback failed (' . $fallback['error'] . ').');
        }

        if ($allowFallback && replicate_is_configured()) {
            $fallback = replicate_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
            $fallback['provider'] = 'replicate';
            return $fallback;
        }

        $result['provider'] = 'gemini';
        return $result;
    }

    if ($provider === 'replicate') {
        $result = replicate_generate_three_view_previews($capturePaths, $styleName, $styleCode, $hairLengthLevel, $hairColorLabel);
        $result['provider'] = 'replicate';
        return $result;
    }

    return [
        'ok' => false,
        'images' => [],
        'feasibleToday' => true,
        'lengthNote' => null,
        'error' => 'No AI try-on provider is configured. Set XAI_API_KEY, GEMINI_API_KEY, or REPLICATE_API_TOKEN in .env.',
        'provider' => 'none',
    ];
}

/**
 * Developer/QA bypass — set AI_TRYON_UNLIMITED=true in .env to disable the per-user
 * style quota entirely without touching any code.
 */
function ai_tryon_unlimited(): bool
{
    $raw = strtolower(trim((string)(
        getenv('AI_TRYON_UNLIMITED') ?: ($_ENV['AI_TRYON_UNLIMITED'] ?? '')
    )));
    return in_array($raw, ['1', 'true', 'yes', 'on'], true);
}

/** Number of distinct hairstyles a user may generate for free. Default 2. */
function ai_tryon_style_limit(): int
{
    $raw = trim((string)(getenv('AI_TRYON_STYLE_LIMIT') ?: ($_ENV['AI_TRYON_STYLE_LIMIT'] ?? '')));
    $limit = $raw !== '' ? (int)$raw : 2;
    return $limit > 0 ? $limit : 2;
}

/**
 * Count of distinct hairstyles this user has ever successfully generated (across all of
 * their scan sessions). Counts DISTINCT variant_id since a style can have more than one
 * preview row (regenerate); staleness does not reduce the count — a slot, once spent,
 * stays spent even if the user later retakes their photos.
 */
function ai_tryon_styles_used(PDO $pdo, int $userId): int
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(DISTINCT fsp.variant_id)
         FROM face_scan_previews fsp
         JOIN face_scan_sessions fss ON fss.scan_session_id = fsp.scan_session_id
         WHERE fss.user_id = :user_id
           AND fsp.variant_id IS NOT NULL'
    );
    $stmt->execute([':user_id' => $userId]);

    return (int)$stmt->fetchColumn();
}

function ai_tryon_user_has_generated_variant(PDO $pdo, int $userId, int $variantId): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*)
         FROM face_scan_previews fsp
         JOIN face_scan_sessions fss ON fss.scan_session_id = fsp.scan_session_id
         WHERE fss.user_id = :user_id
           AND fsp.variant_id = :variant_id'
    );
    $stmt->execute([':user_id' => $userId, ':variant_id' => $variantId]);

    return (int)$stmt->fetchColumn() > 0;
}

/**
 * @return array{limit: int, used: int, remaining: int, unlimited: bool}
 */
function ai_tryon_quota_status(PDO $pdo, ?int $userId): array
{
    $unlimited = ai_tryon_unlimited();
    $limit = ai_tryon_style_limit();
    $used = $userId !== null ? ai_tryon_styles_used($pdo, $userId) : 0;
    $remaining = $unlimited ? $limit : max(0, $limit - $used);

    return [
        'limit' => $limit,
        'used' => $used,
        'remaining' => $remaining,
        'unlimited' => $unlimited,
    ];
}
