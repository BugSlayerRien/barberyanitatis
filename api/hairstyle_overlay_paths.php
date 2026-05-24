<?php
// Maps hairstyle style_name keys to mobile overlay asset paths.

declare(strict_types=1);

/**
 * Canonical HC-* codes for the mobile overlay haircut library (24 styles).
 * Keep in sync with scripts/seed_all_overlay_hairstyles.php and OverlayRegistry.
 *
 * @return list<string>
 */
function overlay_library_style_codes(): array
{
    return [
        'HC-BLOWOUT-TAPER',
        'HC-BUZZ-CUT',
        'HC-CAESAR',
        'HC-CREW',
        'HC-CURLY-BURST',
        'HC-CURLY-CREW',
        'HC-CURLY-DROP',
        'HC-CURLY-MID',
        'HC-CURLY-MULLET',
        'HC-CURLY-TAPER',
        'HC-EDGAR',
        'HC-FRENCH-CROP',
        'HC-LOW-FADE',
        'HC-MESSY-QUIFF',
        'HC-MODERN-CURTAINS',
        'HC-MODERN-MULLET',
        'HC-POMPADOUR',
        'HC-TEXTURED-CROP',
        'HC-TWO-BLOCK',
        'HC-WAVY-BURST',
        'HC-WAVY-FRINGE',
        'HC-WAVY-MESSY',
        'HC-WAVY-MOD',
        'HC-WAVY-SWEEP',
    ];
}

function overlay_library_catalog_size(): int
{
    return count(overlay_library_style_codes());
}

function is_overlay_library_row(array $row): bool
{
    $code = strtoupper(trim((string)($row['style_code'] ?? '')));
    if ($code !== '' && in_array($code, overlay_library_style_codes(), true)) {
        return true;
    }

    $name = (string)($row['style_name'] ?? '');

    return resolve_hairstyle_overlay_key($name) !== null;
}

function hairstyle_overlay_paths(): array
{
    return [
        'blowout taper' => [
            'front' => 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
            'side' => 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
            'back' => 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
        ],
        'buzz cut' => [
            'front' => 'assets/images/overlays/buzz_cut/buzz_cut_front.png',
            'side' => 'assets/images/overlays/buzz_cut/buzz_cut_left.png',
            'back' => 'assets/images/overlays/buzz_cut/buzz_cut_right.png',
        ],
        'caesar cut' => [
            'front' => 'assets/images/overlays/caesar_cut/caesar_front.png',
            'side' => 'assets/images/overlays/caesar_cut/caesar_left.png',
            'back' => 'assets/images/overlays/caesar_cut/caesar_right.png',
        ],
        'crew cut' => [
            'front' => 'assets/images/overlays/crew_cut/crew_front.png',
            'side' => 'assets/images/overlays/crew_cut/crew_left.png',
            'back' => 'assets/images/overlays/crew_cut/crew_right.png',
        ],
        'curly burst fade' => [
            'front' => 'assets/images/overlays/curly_burst_fade/curly_burst_front.png',
            'side' => 'assets/images/overlays/curly_burst_fade/curly_burst_left.png',
            'back' => 'assets/images/overlays/curly_burst_fade/curly_burst_right.png',
        ],
        'curly crew cut' => [
            'front' => 'assets/images/overlays/curly_crew_cut/curly_crew_front.png',
            'side' => 'assets/images/overlays/curly_crew_cut/curly_crew_left.png',
            'back' => 'assets/images/overlays/curly_crew_cut/curly_crew_right.png',
        ],
        'curly drop fade' => [
            'front' => 'assets/images/overlays/curly_drop_fade/curly_drop_front.png',
            'side' => 'assets/images/overlays/curly_drop_fade/curly_drop_left.png',
            'back' => 'assets/images/overlays/curly_drop_fade/curly_drop_right.png',
        ],
        'curly mid fade' => [
            'front' => 'assets/images/overlays/curly_mid_fade/curly_mid_front.png',
            'side' => 'assets/images/overlays/curly_mid_fade/curly_mid_left.png',
            'back' => 'assets/images/overlays/curly_mid_fade/curly_mid_right.png',
        ],
        'curly modern mullet' => [
            'front' => 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_front.png',
            'side' => 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_left.png',
            'back' => 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_right.png',
        ],
        'curly taper fade' => [
            'front' => 'assets/images/overlays/curly_taper/curly_taper_fade_front.png',
            'side' => 'assets/images/overlays/curly_taper/curly_taper_fade_left.png',
            'back' => 'assets/images/overlays/curly_taper/curly_taper_fade_right.png',
        ],
        'edgar cut' => [
            'front' => 'assets/images/overlays/edgar_cut/edgar_front.png',
            'side' => 'assets/images/overlays/edgar_cut/edgar_left.png',
            'back' => 'assets/images/overlays/edgar_cut/edgar_right.png',
        ],
        'french crop' => [
            'front' => 'assets/images/overlays/french_crop/french_crop_front.png',
            'side' => 'assets/images/overlays/french_crop/french_crop_left.png',
            'back' => 'assets/images/overlays/french_crop/french_crop_right.png',
        ],
        'low fade' => [
            'front' => 'assets/images/overlays/low_fade/low_fade_front.png',
            'side' => 'assets/images/overlays/low_fade/low_fade_left.png',
            'back' => 'assets/images/overlays/low_fade/low_fade_right.png',
        ],
        'messy quiff' => [
            'front' => 'assets/images/overlays/messy_quiff/messy_quiff_front.png',
            'side' => 'assets/images/overlays/messy_quiff/messy_quiff_left.png',
            'back' => 'assets/images/overlays/messy_quiff/messy_quiff_right.png',
        ],
        'modern curtains' => [
            'front' => 'assets/images/overlays/modern_curtains/modern_curtains_front.png',
            'side' => 'assets/images/overlays/modern_curtains/modern_curtains_left.png',
            'back' => 'assets/images/overlays/modern_curtains/modern_curtains_right.png',
        ],
        'modern mullet' => [
            'front' => 'assets/images/overlays/modern_mullet/modern_mullet_front.png',
            'side' => 'assets/images/overlays/modern_mullet/modern_mullet_left.png',
            'back' => 'assets/images/overlays/modern_mullet/modern_mullet_right.png',
        ],
        'pompadour' => [
            'front' => 'assets/images/overlays/pompadour/pompadour_front.png',
            'side' => 'assets/images/overlays/pompadour/pompadour_left.png',
            'back' => 'assets/images/overlays/pompadour/pompadour_right.png',
        ],
        'textured crop' => [
            'front' => 'assets/images/overlays/textured_crop/textured_crop_front.png',
            'side' => 'assets/images/overlays/textured_crop/textured_crop_left.png',
            'back' => 'assets/images/overlays/textured_crop/textured_crop_right.png',
        ],
        'two block' => [
            'front' => 'assets/images/overlays/two_block/two_block_front.png',
            'side' => 'assets/images/overlays/two_block/two_block_left.png',
            'back' => 'assets/images/overlays/two_block/two_block_right.png',
        ],
        'wavy burst fade' => [
            'front' => 'assets/images/overlays/wavy_burst_fade/wavy_burst_front.png',
            'side' => 'assets/images/overlays/wavy_burst_fade/wavy_burst_left.png',
            'back' => 'assets/images/overlays/wavy_burst_fade/wavy_burst_right.png',
        ],
        'wavy fringe' => [
            'front' => 'assets/images/overlays/wavy_fringe/wavy_fringe_front.png',
            'side' => 'assets/images/overlays/wavy_fringe/wavy_fringe_left.png',
            'back' => 'assets/images/overlays/wavy_fringe/wavy_fringe_right.png',
        ],
        'wavy messy top' => [
            'front' => 'assets/images/overlays/wavy_messy_top/wavy_messy_front.png',
            'side' => 'assets/images/overlays/wavy_messy_top/wavy_messy_left.png',
            'back' => 'assets/images/overlays/wavy_messy_top/wavy_messy_right.png',
        ],
        'wavy mod cut' => [
            'front' => 'assets/images/overlays/wavy_mod_cut/wavy_mod_front.png',
            'side' => 'assets/images/overlays/wavy_mod_cut/wavy_mod_left.png',
            'back' => 'assets/images/overlays/wavy_mod_cut/wavy_mod_right.png',
        ],
        'wavy side sweep' => [
            'front' => 'assets/images/overlays/wavy_side_sweep/wavy_sweep_front.png',
            'side' => 'assets/images/overlays/wavy_side_sweep/wavy_sweep_left.png',
            'back' => 'assets/images/overlays/wavy_side_sweep/wavy_sweep_right.png',
        ],
    ];
}

function hairstyle_overlay_aliases(): array
{
    return [
        'curly top fade' => 'curly taper fade',
        'curly taper' => 'curly taper fade',
        'caesar' => 'caesar cut',
        'edgar' => 'edgar cut',
        'crew' => 'crew cut',
        'quiff' => 'messy quiff',
        'side sweep' => 'wavy side sweep',
        'wavy sweep' => 'wavy side sweep',
    ];
}

function resolve_hairstyle_overlay_key(string $styleName): ?string
{
    $normalized = strtolower(trim($styleName));
    if ($normalized === '') {
        return null;
    }

    $aliases = hairstyle_overlay_aliases();
    if (isset($aliases[$normalized])) {
        $normalized = $aliases[$normalized];
    }

    $paths = hairstyle_overlay_paths();
    if (isset($paths[$normalized])) {
        return $normalized;
    }

    foreach (array_keys($paths) as $key) {
        if (str_contains($normalized, $key) || str_contains($key, $normalized)) {
            return $key;
        }
    }

    return null;
}

function apply_hairstyle_overlay_paths(array $row): array
{
    $styleName = (string)($row['style_name'] ?? '');
    $key = resolve_hairstyle_overlay_key($styleName);
    if ($key === null) {
        return $row;
    }

    $paths = hairstyle_overlay_paths()[$key];
    $row['front_view_url'] = $paths['front'];
    $row['side_view_url'] = $paths['side'];
    $row['back_view_url'] = $paths['back'];
    $row['overlay_folder'] = overlay_folder_from_asset_path($paths['front']);

    return $row;
}

function overlay_folder_from_asset_path(string $assetPath): ?string
{
    if (preg_match('#assets/images/overlays/([^/]+)/#', $assetPath, $matches) === 1) {
        return $matches[1];
    }

    return null;
}

/**
 * @return array{front: string, side: string, back: string, folder: string}|null
 */
function overlay_paths_for_style_name(string $styleName): ?array
{
    $key = resolve_hairstyle_overlay_key($styleName);
    if ($key === null) {
        return null;
    }

    $paths = hairstyle_overlay_paths()[$key];
    $folder = overlay_folder_from_asset_path($paths['front']);
    if ($folder === null) {
        return null;
    }

    return [
        'front' => $paths['front'],
        'side' => $paths['side'],
        'back' => $paths['back'],
        'folder' => $folder,
    ];
}

/**
 * @return array{folder: string, filename: string}|null
 */
function overlay_target_for_view(string $styleName, string $view): ?array
{
    $paths = overlay_paths_for_style_name($styleName);
    if ($paths === null) {
        return null;
    }

    $viewKey = match (strtolower(trim($view))) {
        'front' => 'front',
        'left', 'side' => 'side',
        'right', 'back' => 'back',
        default => null,
    };
    if ($viewKey === null) {
        return null;
    }

    $assetPath = $paths[$viewKey];
    $filename = basename($assetPath);
    if ($filename === '') {
        return null;
    }

    return [
        'folder' => $paths['folder'],
        'filename' => $filename,
    ];
}

function mobile_app_overlay_root(): string
{
    return dirname(__DIR__) . '/mobile-app/assets/images/overlays';
}

function slugify_overlay_folder(string $value): string
{
    $slug = strtolower(trim($value));
    $slug = preg_replace('/[^a-z0-9]+/', '_', $slug) ?? '';
    $slug = trim((string)$slug, '_');

    return $slug !== '' ? $slug : 'custom_style';
}
