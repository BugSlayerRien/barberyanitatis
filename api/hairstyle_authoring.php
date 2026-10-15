<?php
// Everything needed to make a hairstyle usable without a code change.
//
// A style added through the portal used to write one `hairstyles` row and stop
// there, while four separate gates -- the overlay catalog, the AI prompt table,
// a Dart registry and the Flutter asset bundle -- could only be satisfied by
// editing source and shipping a new API deploy and a new app build. Adding a
// haircut was therefore a developer task wearing an admin form.
//
// Two of those gates are removed here: the prompt becomes a column, and the
// readiness rules become something the portal can show and enforce. The other
// two (the Dart registry and the asset bundle) only govern the *bundled*
// artwork used for the live scanner overlay; uploaded photos go over the
// network instead, which is why a new style is catalog + AI preview and not a
// live camera overlay.

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * Columns the authoring flow needs. Lazy and idempotent, matching
 * ensure_top_pick_eligible_column() in variant_ranking.php.
 */
function ensure_hairstyle_authoring_columns(PDO $pdo): void
{
    $pdo->exec('ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS ai_prompt TEXT');
    $pdo->exec(
        'ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS ai_min_length_level INT'
    );
    // NULL has to mean "nobody chose", or the column cannot override anything.
    // Created NOT NULL DEFAULT 1, it made "unset" and "deliberately Short"
    // identical -- so the code table had to win, and a length set in the
    // portal or the barber app was quietly ignored. Wolf Cut was submitted as
    // Long and the app was told Short.
    $pdo->exec('ALTER TABLE hairstyles ALTER COLUMN ai_min_length_level DROP NOT NULL');
    $pdo->exec('ALTER TABLE hairstyles ALTER COLUMN ai_min_length_level DROP DEFAULT');
    $pdo->exec('ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS authored_by_barber_id BIGINT');
    // Which cut to offer a customer whose hair is too short for this one.
    // Nullable: a style with no pairing falls back to a heuristic rather than
    // refusing to suggest anything.
    $pdo->exec(
        'ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS transition_style_code VARCHAR(20)'
    );
    // Defaults to Published so every existing row stays visible: this column is
    // new, and the styles already in the catalog were never reviewed through a
    // workflow that did not exist.
    $pdo->exec(
        "ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS review_status VARCHAR(20) NOT NULL DEFAULT 'Published'"
    );
    // Once per deploy, not per request: it rewrites rows, and the guard keys
    // on the code stamp so a later change to the built-in table re-runs it.
    schema_ensure_once('hairstyles.min_length_backfill', static function () use ($pdo): void {
        backfill_hairstyle_min_length_defaults($pdo);
    });

    $pdo->exec('ALTER TABLE hairstyles DROP CONSTRAINT IF EXISTS hairstyles_review_status_check');
    try {
        $pdo->exec(
            "ALTER TABLE hairstyles ADD CONSTRAINT hairstyles_review_status_check
             CHECK (review_status IN ('Draft', 'PendingReview', 'Published', 'Rejected'))"
        );
    } catch (Throwable $e) {
        // Already present after a concurrent request.
    }
}

/**
 * Clears the leftover default so the built-in table governs built-in styles.
 *
 * Every row was created with 1 whether or not anyone chose it. Now that NULL
 * means "unset", those 1s would override the code table and tell the app that
 * a Pompadour needs only short hair. They are cleared, but only for styles the
 * code already describes and only where the code disagrees -- a deliberate
 * Short on a style with no built-in entry is left exactly as it is.
 *
 * Runs once per deploy via schema_ensure_once. Rows written after this point
 * carry a value only when someone actually picked one.
 */
function backfill_hairstyle_min_length_defaults(PDO $pdo): void
{
    require_once __DIR__ . '/replicate_helper.php';

    $rows = $pdo->query(
        'SELECT hairstyle_id, style_code, style_name
         FROM hairstyles WHERE ai_min_length_level = 1'
    )->fetchAll(PDO::FETCH_ASSOC);
    if ($rows === []) {
        return;
    }

    $builtIn = replicate_style_min_length();
    $clear = $pdo->prepare(
        'UPDATE hairstyles SET ai_min_length_level = NULL WHERE hairstyle_id = :id'
    );

    foreach ($rows as $row) {
        $key = replicate_resolve_style_key(
            (string)$row['style_name'],
            (string)$row['style_code']
        );
        if ($key === null || ($builtIn[$key] ?? 1) === 1) {
            continue;
        }
        $clear->execute([':id' => (int)$row['hairstyle_id']]);
    }
}

/**
 * The try-on prompt that will actually be used for this style.
 *
 * Prompts live in two places. A style added through the portal or the barber
 * app stores its own in `ai_prompt`. The styles that shipped with the app have
 * theirs in replicate_style_prompts(), and their column is NULL --
 * 32 of the 35 rows in the live catalogue.
 *
 * replicate_style_brief() has always resolved between the two, which is why
 * generation worked. Nothing else did: the portal read the column raw, found
 * nothing, and refused to save any edit to those 32 styles at all. The
 * readiness panel reported "No AI prompt" on every one of them.
 *
 * @param array<string, mixed> $row a hairstyles row
 */
function hairstyle_ai_prompt(array $row): string
{
    require_once __DIR__ . '/replicate_helper.php';

    $stored = trim((string)($row['ai_prompt'] ?? ''));
    if ($stored !== '') {
        return $stored;
    }

    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    if ($key === null) {
        return '';
    }

    return (string)(replicate_style_prompts()[$key] ?? '');
}

/**
 * Where [hairstyle_ai_prompt] got its answer: 'stored', 'builtin' or 'none'.
 *
 * The portal needs the distinction to say whose words are in the box, and the
 * save needs it to leave the column NULL when nothing was actually edited.
 *
 * @param array<string, mixed> $row a hairstyles row
 */
function hairstyle_ai_prompt_source(array $row): string
{
    if (trim((string)($row['ai_prompt'] ?? '')) !== '') {
        return 'stored';
    }

    return hairstyle_ai_prompt($row) !== '' ? 'builtin' : 'none';
}

/**
 * The built-in minimum length for this style, or null when it has none.
 *
 * Separate from [hairstyle_min_length_level] because the save needs to know
 * whether a submitted value matches the default -- storing it would fork the
 * style from the code table for no reason.
 *
 * @param array<string, mixed> $row a hairstyles row
 */
function hairstyle_builtin_min_length_level(array $row): ?int
{
    require_once __DIR__ . '/replicate_helper.php';

    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    if ($key === null) {
        return null;
    }

    $table = replicate_style_min_length();

    return isset($table[$key]) ? (int)$table[$key] : null;
}

/**
 * The shortest hair this style can be cut from.
 *
 * The stored value wins when someone set one; otherwise the built-in table
 * describes it; otherwise short. One resolver, because the ranking, the
 * library and the generator each used to answer this differently -- and the
 * ranking ignored the column entirely, which is why a style submitted as Long
 * produced no warning at all.
 *
 * @param array<string, mixed> $row a hairstyles row
 */
function hairstyle_min_length_level(array $row): int
{
    require_once __DIR__ . '/replicate_helper.php';

    $stored = $row['ai_min_length_level'] ?? null;
    if ($stored !== null && $stored !== '') {
        return max(0, min(3, (int)$stored));
    }

    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    if ($key === null) {
        return 1;
    }

    return (int)(replicate_style_min_length()[$key] ?? 1);
}

/**
 * The style_code to suggest instead of this one, or '' when there is none.
 *
 * One resolver for three callers -- the ranking, the library and the portal --
 * so they cannot disagree about what a style pairs with. The stored column
 * wins over the built-in default, which is what lets the portal override a
 * pairing without a code change.
 *
 * A style pointing at itself is treated as unset: it would make the lookup
 * loop, and it is never what anyone meant.
 *
 * @param array<string, mixed> $row a hairstyles row
 */
function hairstyle_transition_code(array $row): string
{
    $own = strtoupper(trim((string)($row['style_code'] ?? '')));

    $stored = strtoupper(trim((string)($row['transition_style_code'] ?? '')));
    if ($stored !== '' && $stored !== $own) {
        return $stored;
    }

    require_once __DIR__ . '/replicate_helper.php';
    $key = replicate_resolve_style_key(
        (string)($row['style_name'] ?? ''),
        (string)($row['style_code'] ?? '')
    );
    if ($key === null) {
        return '';
    }

    $fallback = strtoupper(trim(hairstyle_transition_defaults()[$key] ?? ''));

    return $fallback !== '' && $fallback !== $own ? $fallback : '';
}

/**
 * Turns a style name into a code, in the one shape the catalogue uses.
 *
 * Both the portal and the barber app generated this independently with the
 * same expression copied twice. Uppercase has to happen before the
 * substitution: run the other way round, the negated class [^A-Z0-9] eats
 * every lowercase letter, so "Mid Fade" became HC-M-F- and "Taper Fade" and
 * "Textured Fringe" both became HC-T-F- -- a collision on a UNIQUE column
 * that surfaced as a bare 500.
 */
function hairstyle_code_from_name(string $styleName): string
{
    $slug = preg_replace('/[^A-Z0-9]+/', '-', strtoupper(trim($styleName))) ?? '';
    $code = 'HC-' . trim($slug, '-');

    return substr($code, 0, 20) === 'HC-' ? 'HC-STYLE' : substr($code, 0, 20);
}

/**
 * The same code with a number appended until nothing else is using it.
 *
 * Codes are generated from the name, so two barbers submitting "Wolf Cut"
 * produced the same code and the second one saw a raw Postgres uniqueness
 * error. Suffixing is friendlier than refusing: the barber did nothing wrong,
 * and the name is still theirs to tell apart.
 */
function hairstyle_unique_code(PDO $pdo, string $base, ?int $ignoreId = null): string
{
    $base = strtoupper(trim($base));
    if ($base === '') {
        $base = 'HC-STYLE';
    }

    $sql = 'SELECT 1 FROM hairstyles WHERE UPPER(style_code) = :code';
    if ($ignoreId !== null) {
        $sql .= ' AND hairstyle_id <> :id';
    }
    $stmt = $pdo->prepare($sql . ' LIMIT 1');

    $candidate = $base;
    for ($suffix = 2; $suffix < 100; $suffix++) {
        $params = [':code' => $candidate];
        if ($ignoreId !== null) {
            $params[':id'] = $ignoreId;
        }
        $stmt->execute($params);
        if ($stmt->fetchColumn() === false) {
            return $candidate;
        }
        // Room for the suffix, so the result still fits the column.
        $candidate = substr($base, 0, 20 - strlen((string)$suffix) - 1) . '-' . $suffix;
    }

    return substr($base, 0, 13) . '-' . substr((string)time(), -6);
}

/**
 * Why this style code cannot be used, or '' when it can.
 *
 * Only for codes a person typed. Generated ones are already well formed and
 * made unique above.
 */
function hairstyle_code_problem(PDO $pdo, string $styleCode, ?int $ignoreId = null): string
{
    $code = strtoupper(trim($styleCode));
    if ($code === '') {
        return '';
    }

    if (strlen($code) > 20) {
        return 'Style code is too long — 20 characters at most.';
    }
    // Spaces and punctuation silently produced codes that no lookup matched.
    if (preg_match('/^[A-Z0-9][A-Z0-9-]*$/', $code) !== 1) {
        return 'Style code can only use letters, numbers and hyphens, '
            . 'for example HC-TWO-BLOCK.';
    }

    $sql = 'SELECT style_name FROM hairstyles WHERE UPPER(style_code) = :code';
    if ($ignoreId !== null) {
        $sql .= ' AND hairstyle_id <> :id';
    }
    $stmt = $pdo->prepare($sql . ' LIMIT 1');
    $params = [':code' => $code];
    if ($ignoreId !== null) {
        $params[':id'] = $ignoreId;
    }
    $stmt->execute($params);

    $taken = $stmt->fetchColumn();
    if ($taken !== false) {
        return 'Style code ' . $code . ' is already used by "' . $taken . '".';
    }

    return '';
}

/**
 * Why this style name cannot be used, or '' when it can.
 *
 * Two haircuts with the same name are indistinguishable to a customer
 * browsing the library, however different their codes are.
 */
function hairstyle_name_problem(PDO $pdo, string $styleName, ?int $ignoreId = null): string
{
    $name = trim($styleName);
    if ($name === '') {
        return 'A style name is required.';
    }
    if (mb_strlen($name) > 80) {
        return 'Style name is too long — 80 characters at most.';
    }

    // Active styles only. Two deactivated rows already share names with live
    // ones (old STYLE-* seeds), and blocking on a row that is not in the
    // catalogue would be baffling to whoever hit it.
    $sql = 'SELECT style_code FROM hairstyles
            WHERE LOWER(TRIM(style_name)) = LOWER(:name) AND is_active = TRUE';
    if ($ignoreId !== null) {
        $sql .= ' AND hairstyle_id <> :id';
    }
    $stmt = $pdo->prepare($sql . ' LIMIT 1');
    $params = [':name' => $name];
    if ($ignoreId !== null) {
        $params[':id'] = $ignoreId;
    }
    $stmt->execute($params);

    $taken = $stmt->fetchColumn();
    if ($taken !== false) {
        return 'A haircut called "' . $name . '" already exists (' . $taken . ').';
    }

    return '';
}

/**
 * A database failure in words the person who hit it can act on.
 *
 * Postgres messages name tables, columns and constraints. Those belong in the
 * log, not in a browser -- and "duplicate key value violates unique constraint
 * hairstyles_style_code_key" tells an admin nothing about what to change.
 */
function hairstyle_friendly_db_error(Throwable $e): string
{
    $message = $e->getMessage();

    if (stripos($message, 'hairstyles_style_code_key') !== false
        || stripos($message, 'duplicate key') !== false) {
        return 'That style code is already in use. Pick a different one, or '
            . 'leave the code blank and one will be made for you.';
    }
    if (stripos($message, 'violates foreign key') !== false) {
        return 'That haircut is still linked to other records and cannot be '
            . 'changed this way.';
    }
    if (stripos($message, 'violates check constraint') !== false) {
        return 'One of the values is outside what this field accepts.';
    }

    return 'The database rejected that change. Please try again.';
}

/** SQL fragment restricting a query to styles customers may see. */
function hairstyle_published_sql(string $alias = 'hs'): string
{
    return " AND COALESCE({$alias}.review_status, 'Published') = 'Published' ";
}

/**
 * Turns the barber's answers into the prompt the image model receives.
 *
 * This is the point of letting a barber author a style: they are describing a
 * haircut in the terms they already use at the chair -- fade height, guard
 * numbers, length on top, what happens at the back -- and those terms are
 * exactly what the model needs. Nobody has to write a prompt.
 *
 * The field order and phrasing mirror replicate_style_prompts() so a composed
 * prompt reads like a built-in one and passes the same checks in
 * scripts/test_tryon_prompts.php.
 *
 * @param array<string, string> $fields
 */
function compose_hairstyle_prompt(string $styleName, array $fields): string
{
    $clean = static function (string $key) use ($fields): string {
        return trim((string)($fields[$key] ?? ''));
    };

    $parts = [];

    $sides = $clean('sides');
    if ($sides !== '') {
        $parts[] = $sides;
    }

    $guards = $clean('guards');
    if ($guards !== '') {
        $parts[] = 'clipper guards ' . $guards;
    }

    $top = $clean('top');
    if ($top !== '') {
        $parts[] = $top;
    }

    $fringe = $clean('fringe');
    if ($fringe !== '') {
        $parts[] = $fringe;
    }

    // Always stated, and the reason is specific: a prompt that describes the
    // top and the sides but leaves the back unsaid lets the model invent
    // length there. That is how Two Block grew long hair at the back.
    $back = $clean('back');
    $parts[] = $back !== '' ? $back : 'the back cut to match the sides, nothing left over the collar';

    $neckline = $clean('neckline');
    if ($neckline !== '') {
        $parts[] = $neckline;
    }

    $finish = $clean('finish');
    if ($finish !== '') {
        $parts[] = $finish;
    }

    return strtolower(trim($styleName)) . ': ' . implode(', ', $parts);
}

/**
 * Why a style could not work at all, in the words the admin needs.
 *
 * The portal already flagged "Missing PNGs" but gave no way to see the rest,
 * so a style could be saved, look fine in the list, and silently never reach a
 * customer. Publishing is blocked on this list being empty.
 *
 * Missing photographs are deliberately NOT here -- they are a warning, see
 * hairstyle_readiness_warnings(). The app draws a placeholder tile for a style
 * with no artwork and the AI preview works from the description, so blocking
 * publication on photos would hold back a perfectly usable haircut.
 *
 * @param array<string, mixed> $hairstyle a hairstyles row
 * @param list<array<string, mixed>> $variants its hairstyle_variants rows
 * @return list<string> blocking reasons, empty when the style is usable
 */
function hairstyle_readiness_problems(array $hairstyle, array $variants): array
{
    $problems = [];

    $code = trim((string)($hairstyle['style_code'] ?? ''));
    if ($code === '' || preg_match('/^HC(-[A-Z0-9]+)*-$/', $code) === 1) {
        $problems[] = 'Style code is missing or malformed.';
    }

    // Resolved, not read raw: the 32 built-in styles carry their prompt in
    // replicate_style_prompts() and this panel declared every one of them
    // broken.
    if (hairstyle_ai_prompt($hairstyle) === '') {
        $problems[] = 'No AI prompt, so a preview cannot be generated.';
    }

    if ($variants === []) {
        $problems[] = 'No variants, so the style can never be recommended or booked.';

        return $problems;
    }

    $textures = [];
    foreach ($variants as $variant) {
        $texture = trim((string)($variant['hair_texture'] ?? ''));
        if ($texture !== '') {
            $textures[$texture] = true;
        }

        if (trim((string)($variant['barber_instructions'] ?? '')) === '') {
            $problems[] = 'A variant has no barber instructions.';
        }
    }

    // The ranking applies an exact texture match, so a style with only one
    // texture is invisible to every customer with a different one.
    if ($textures === []) {
        $problems[] = 'No hair texture set on any variant.';
    }

    return array_values(array_unique($problems));
}

/**
 * Things worth fixing that do not stop the style working.
 *
 * Kept apart from the blockers on purpose. Mixing the two is what made the
 * portal's old "Missing PNGs" flag useless: it looked like a fault when the
 * style was perfectly usable, and it sat beside real faults with no way to
 * tell them apart.
 *
 * @param array<string, mixed> $hairstyle a hairstyles row
 * @param list<array<string, mixed>> $variants its hairstyle_variants rows
 * @return list<string>
 */
function hairstyle_readiness_warnings(array $hairstyle, array $variants): array
{
    $warnings = [];

    $missingViews = [];
    foreach (['front_view_url' => 'front', 'side_view_url' => 'side', 'back_view_url' => 'back'] as $column => $label) {
        foreach ($variants as $variant) {
            if (trim((string)($variant[$column] ?? '')) === '') {
                $missingViews[$label] = true;
                break;
            }
        }
    }
    if ($missingViews !== []) {
        $warnings[] = 'No ' . implode(', ', array_keys($missingViews))
            . ' photo yet — customers see a placeholder tile until one is uploaded.';
    }

    $textures = [];
    $faces = [];
    foreach ($variants as $variant) {
        $texture = trim((string)($variant['hair_texture'] ?? ''));
        if ($texture !== '') {
            $textures[$texture] = true;
        }
        $face = trim((string)($variant['face_shape'] ?? ''));
        if ($face !== '') {
            $faces[$face] = true;
        }
    }

    // Recommendations match face shape and texture exactly, so thin coverage
    // does not hide a style from the library but does keep it out of most
    // customers' recommendations. Worth saying, not worth blocking.
    if (count($textures) === 1) {
        $warnings[] = 'Only suits ' . implode('', array_keys($textures))
            . ' hair, so it is rarely recommended. Add variants for other textures to widen it.';
    }
    if (count($faces) > 0 && count($faces) < 3) {
        $warnings[] = 'Only set up for ' . implode(', ', array_keys($faces))
            . ' face shapes, so other customers will not be recommended it.';
    }

    return array_values(array_unique($warnings));
}
