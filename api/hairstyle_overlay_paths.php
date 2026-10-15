<?php
// Maps hairstyle style_name keys to mobile overlay asset paths.

declare(strict_types=1);

/**
 * Built-in HC-* codes with bundled overlay artwork. This is the *asset*
 * inventory, not the catalog: a style only reaches customers if it is also
 * active in the database and all three of its images exist. See
 * overlay_library_style_codes().
 *
 * @return list<string>
 */
function overlay_library_bundled_style_codes(): array
{
    return array_keys(overlay_library_code_keys());
}

/**
 * The haircut catalog, from the database, gated on artwork actually existing.
 *
 * It used to be this hardcoded list of 24 codes, so adding a haircut meant a
 * code change, and a style whose images were missing still appeared and then
 * failed to render. Styles are now included when they are active in
 * `hairstyles` and all three overlay images resolve -- either bundled artwork
 * or per-variant uploads.
 *
 * Without a PDO (callers that have no connection to hand) this falls back to
 * the bundled list, which is the old behaviour.
 *
 * @return list<string>
 */
function overlay_library_style_codes(?PDO $pdo = null): array
{
    if ($pdo === null) {
        return overlay_library_bundled_style_codes();
    }

    require_once __DIR__ . '/schema_cache.php';

    static $memo = null;
    static $memoStamp = 0;
    // Keyed on the cache file's timestamp, not just "have we computed this".
    // Publishing a style deletes that file, and a bare memo would otherwise
    // keep serving the pre-publish catalog for the life of the worker.
    $stamp = overlay_library_catalog_stamp();
    if ($memo !== null && $memoStamp === $stamp) {
        return $memo;
    }
    // Each style costs up to three existence checks, and under
    // STORAGE_DRIVER=supabase every check is an HTTP request -- far too slow
    // to redo on each catalog read.
    $cached = schema_cache_get_json('overlay_library_catalog', 300);
    if ($cached !== null && isset($cached['codes']) && is_array($cached['codes'])) {
        $memo = array_values(array_filter($cached['codes'], 'is_string'));
        $memoStamp = $stamp;

        return $memo;
    }

    try {
        $stmt = $pdo->query(
            "SELECT hs.style_code, hs.style_name, hs.ai_prompt,
                    hv.front_view_url, hv.side_view_url, hv.back_view_url
             FROM hairstyles hs
             LEFT JOIN hairstyle_variants hv ON hv.variant_id = (
                SELECT hv2.variant_id FROM hairstyle_variants hv2
                WHERE hv2.hairstyle_id = hs.hairstyle_id
                ORDER BY hv2.confidence_score DESC, hv2.variant_id ASC
                LIMIT 1
             )
             WHERE hs.is_active = TRUE
               AND COALESCE(hs.review_status, 'Published') = 'Published'"
        );
        $codes = [];
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $code = strtoupper(trim((string)($row['style_code'] ?? '')));
            if ($code === '') {
                continue;
            }
            if (!hairstyle_overlay_files_exist($row)
                && !hairstyle_is_previewable_without_artwork($row)) {
                continue;
            }
            $codes[] = $code;
        }
        sort($codes);
    } catch (PDOException $e) {
        error_log('Overlay catalog query failed, using bundled list: ' . $e->getMessage());

        return overlay_library_bundled_style_codes();
    }

    if ($codes === []) {
        // No style qualified. That is far more likely to be a broken asset
        // check than a shop with no haircuts, and caching it would keep the
        // library empty for everyone. Fall back, and do not cache.
        error_log('Overlay catalog resolved to zero styles; using bundled list.');

        return overlay_library_bundled_style_codes();
    }

    schema_cache_put_json('overlay_library_catalog', ['codes' => $codes]);
    $memo = $codes;
    $memoStamp = overlay_library_catalog_stamp();

    return $memo;
}

/** Mtime of the cached catalog, or 0 when there is none. */
function overlay_library_catalog_stamp(): int
{
    require_once __DIR__ . '/schema_cache.php';

    return (int)@filemtime(schema_cache_marker_path('overlay_library_catalog') . '.json');
}

/**
 * Whether a style can be shown even though it has no photographs.
 *
 * The catalog used to require three resolvable images, which is the right gate
 * for the live camera overlay and the wrong one for the library: a haircut the
 * barber has described well enough to generate is a haircut the shop can cut.
 * Demanding artwork meant a style added through the portal stayed invisible
 * until someone uploaded three files -- and the panel's own addition never
 * appeared at all. The app draws a placeholder tile for these; see
 * `has_artwork` on the rows returned by haircuts.php.
 */
function hairstyle_is_previewable_without_artwork(array $row): bool
{
    // Rows travel through several stages -- ranked, annotated, normalized --
    // and the prompt is dropped once the flag has been derived, because the
    // customer has no business reading what the image model is told. Trusting
    // the flag when it is there keeps every later stage honest; deriving it
    // from a row whose prompt was already stripped would silently say "no".
    if (array_key_exists('previewable', $row)) {
        return (bool)$row['previewable'];
    }

    // Resolved rather than read raw. A built-in style keeps its prompt in
    // replicate_style_prompts() with a NULL column, and testing the column
    // alone called it unpreviewable.
    require_once __DIR__ . '/hairstyle_authoring.php';

    return hairstyle_ai_prompt($row) !== '';
}

function overlay_library_catalog_size(?PDO $pdo = null): int
{
    return count(overlay_library_style_codes($pdo));
}

/**
 * HC-* style_code → overlay catalog key (must match hairstyle_overlay_paths()).
 *
 * @return array<string, string>
 */
function overlay_library_code_keys(): array
{
    return [
        'HC-BLOWOUT-TAPER' => 'blowout taper',
        'HC-BUZZ-CUT' => 'buzz cut',
        'HC-CAESAR' => 'caesar cut',
        'HC-CREW' => 'crew cut',
        'HC-CURLY-BURST' => 'curly burst fade',
        'HC-CURLY-CREW' => 'curly crew cut',
        'HC-CURLY-DROP' => 'curly drop fade',
        'HC-CURLY-MID' => 'curly mid fade',
        'HC-CURLY-MULLET' => 'curly modern mullet',
        'HC-CURLY-TAPER' => 'curly taper fade',
        'HC-EDGAR' => 'edgar cut',
        'HC-FRENCH-CROP' => 'french crop',
        'HC-LOW-FADE' => 'low fade',
        'HC-MESSY-QUIFF' => 'messy quiff',
        'HC-MODERN-CURTAINS' => 'modern curtains',
        'HC-MODERN-MULLET' => 'modern mullet',
        'HC-POMPADOUR' => 'pompadour',
        'HC-TEXTURED-CROP' => 'textured crop',
        'HC-TWO-BLOCK' => 'two block',
        'HC-WAVY-BURST' => 'wavy burst fade',
        'HC-WAVY-FRINGE' => 'wavy fringe',
        'HC-WAVY-MESSY' => 'wavy messy top',
        'HC-WAVY-MOD' => 'wavy mod cut',
        'HC-WAVY-SWEEP' => 'wavy side sweep',
    ];
}

function overlay_key_for_style_code(string $styleCode): ?string
{
    $code = strtoupper(trim($styleCode));
    if ($code === '') {
        return null;
    }

    return overlay_library_code_keys()[$code] ?? null;
}

/**
 * Whether all three overlay images for a style are actually present. Lives
 * here, not in admin_hairstyles.php, because the customer-facing catalog
 * (haircuts.php, variant_ranking.php) needs the same gate -- it used to be
 * an admin-only display flag.
 */
function overlay_asset_is_present(string $relativePath): bool
{
    static $cache = [];
    $relativePath = ltrim(str_replace('\\', '/', trim($relativePath)), '/');
    if ($relativePath === '') {
        return false;
    }
    if (array_key_exists($relativePath, $cache)) {
        return $cache[$relativePath];
    }

    $present = overlay_library_local_exists($relativePath);
    if (!$present && function_exists('storage_exists')) {
        $present = storage_exists($relativePath);
    }

    $cache[$relativePath] = $present;

    return $present;
}

function hairstyle_overlay_files_exist(array $hairstyle): bool
{
    // Bundled artwork ships inside the Flutter app, not the API image. The
    // deployed API is built from api/ alone (render.yaml rootDir: api), so
    // mobile-app/assets never exists there and probing for it failed for every
    // style -- which emptied the customer library completely. A style that
    // maps to a bundled overlay key is present by definition; the app has the
    // files even when the server cannot see them.
    if (overlay_paths_for_hairstyle($hairstyle) !== null) {
        return true;
    }

    // Uploaded artwork is the case this gate is actually for: those files live
    // in storage the server CAN check.
    $paths = array_values(array_filter([
        (string)($hairstyle['front_view_url'] ?? ''),
        (string)($hairstyle['side_view_url'] ?? ''),
        (string)($hairstyle['back_view_url'] ?? ''),
    ]));

    if (count($paths) < 3) {
        return false;
    }

    foreach ($paths as $path) {
        if (!overlay_asset_is_present((string)$path)) {
            return false;
        }
    }

    return true;
}

/**
 * @param list<string>|null $allowedCodes Catalog from the database, when the
 *        caller has one. Without it this falls back to the bundled codes,
 *        which would reject a DB style whose artwork was uploaded rather than
 *        shipped in the app.
 */
function is_overlay_library_row(array $row, ?array $allowedCodes = null): bool
{
    $code = strtoupper(trim((string)($row['style_code'] ?? '')));
    // An empty catalog means the catalog could not be determined, not that
    // nothing qualifies. Treating [] as "allow nothing" rejected every row and
    // emptied the library; fall back to the bundled list instead.
    $codes = ($allowedCodes === null || $allowedCodes === [])
        ? overlay_library_style_codes()
        : $allowedCodes;
    if ($code !== '' && in_array($code, $codes, true)) {
        return true;
    }

    // Not in the catalog: admit it if its own artwork is there, or if it can
    // at least be generated -- a described style with no photos yet shows as a
    // placeholder rather than not at all.
    if (hairstyle_overlay_files_exist($row) || hairstyle_is_previewable_without_artwork($row)) {
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

    // Deliberately NOT a bidirectional str_contains any more. That matched a
    // shorter name inside a longer key, so a new DB style called "Mid Fade"
    // resolved to "curly mid fade" and silently wore the curly artwork. Only a
    // longer name containing a full key still matches (e.g. "Classic Buzz Cut"
    // -> "buzz cut"), and it must land on a word boundary.
    foreach (array_keys($paths) as $key) {
        if (preg_match('/(^|\s)' . preg_quote($key, '/') . '($|\s)/', $normalized) === 1) {
            return $key;
        }
    }

    return null;
}

function resolve_hairstyle_overlay_key_for_row(array $row): ?string
{
    $fromCode = overlay_key_for_style_code((string)($row['style_code'] ?? ''));
    if ($fromCode !== null) {
        return $fromCode;
    }

    return resolve_hairstyle_overlay_key((string)($row['style_name'] ?? ''));
}

/**
 * Fill in bundled artwork for styles that ship with it.
 *
 * Only for styles with no artwork of their own. This used to overwrite the row
 * unconditionally, so a style whose photos an admin had uploaded lost them to
 * whichever bundled key its name happened to fuzzy-match -- the upload appeared
 * to work and the customer saw someone else's haircut.
 */
function apply_hairstyle_overlay_paths(array $row): array
{
    if (hairstyle_row_has_uploaded_artwork($row)) {
        return $row;
    }

    $key = resolve_hairstyle_overlay_key_for_row($row);
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

/**
 * True when the row carries its own images rather than bundled assets.
 *
 * Bundled artwork is addressed as an `assets/...` Flutter path; anything else
 * is an upload that must be served over the network and left alone.
 */
function hairstyle_row_has_uploaded_artwork(array $row): bool
{
    foreach (['front_view_url', 'side_view_url', 'back_view_url'] as $column) {
        $value = trim((string)($row[$column] ?? ''));
        if ($value === '' || str_starts_with($value, 'assets/')) {
            return false;
        }
    }

    return true;
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
    return overlay_paths_for_overlay_key(resolve_hairstyle_overlay_key($styleName));
}

/**
 * @param array<string, mixed> $row
 * @return array{front: string, side: string, back: string, folder: string}|null
 */
function overlay_paths_for_hairstyle(array $row): ?array
{
    return overlay_paths_for_overlay_key(resolve_hairstyle_overlay_key_for_row($row));
}

/**
 * @return array{front: string, side: string, back: string, folder: string}|null
 */
function overlay_paths_for_overlay_key(?string $key): ?array
{
    if ($key === null) {
        return null;
    }

    $catalog = hairstyle_overlay_paths();
    if (!isset($catalog[$key])) {
        return null;
    }

    $paths = $catalog[$key];
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

function overlay_library_local_path(string $relativePath): string
{
    $rel = ltrim(str_replace('\\', '/', $relativePath), '/');
    $prefix = 'assets/images/overlays/';
    if (str_starts_with($rel, $prefix)) {
        $rel = substr($rel, strlen($prefix));
    }

    return mobile_app_overlay_root() . DIRECTORY_SEPARATOR
        . str_replace('/', DIRECTORY_SEPARATOR, $rel);
}

function overlay_library_local_exists(string $relativePath): bool
{
    $full = overlay_library_local_path($relativePath);

    return is_file($full) && filesize($full) > 0;
}

/**
 * @return array{folder: string, filename: string}|null
 */
function overlay_target_for_view(string $styleName, string $view, string $styleCode = ''): ?array
{
    $paths = overlay_paths_for_hairstyle([
        'style_name' => $styleName,
        'style_code' => $styleCode,
    ]);
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
    static $resolved = null;
    if ($resolved !== null) {
        return $resolved;
    }

    // Repo layout (api/ sits beside mobile-app/) vs a flat docroot deploy.
    // Neither exists on Render, where only api/ is copied into the image --
    // hairstyle_overlay_files_exist() no longer depends on this being found.
    foreach ([
        dirname(__DIR__) . '/mobile-app/assets/images/overlays',
        __DIR__ . '/mobile-app/assets/images/overlays',
        __DIR__ . '/assets/images/overlays',
    ] as $candidate) {
        if (is_dir($candidate)) {
            return $resolved = $candidate;
        }
    }

    return $resolved = dirname(__DIR__) . '/mobile-app/assets/images/overlays';
}

function slugify_overlay_folder(string $value): string
{
    $slug = strtolower(trim($value));
    $slug = preg_replace('/[^a-z0-9]+/', '_', $slug) ?? '';
    $slug = trim((string)$slug, '_');

    return $slug !== '' ? $slug : 'custom_style';
}
