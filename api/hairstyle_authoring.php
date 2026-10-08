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
        'ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS ai_min_length_level INT NOT NULL DEFAULT 1'
    );
    $pdo->exec('ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS authored_by_barber_id BIGINT');
    // Defaults to Published so every existing row stays visible: this column is
    // new, and the styles already in the catalog were never reviewed through a
    // workflow that did not exist.
    $pdo->exec(
        "ALTER TABLE hairstyles ADD COLUMN IF NOT EXISTS review_status VARCHAR(20) NOT NULL DEFAULT 'Published'"
    );
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
 * Why a style would not appear in the app, in the words the admin needs.
 *
 * The portal already flagged "Missing PNGs" but gave no way to see the rest,
 * so a style could be saved, look fine in the list, and silently never reach a
 * customer. Publishing is blocked on this list being empty.
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

    if (trim((string)($hairstyle['ai_prompt'] ?? '')) === '') {
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

        foreach (['front_view_url', 'side_view_url', 'back_view_url'] as $column) {
            if (trim((string)($variant[$column] ?? '')) === '') {
                $problems[] = 'A variant is missing its ' . str_replace('_view_url', '', $column) . ' image.';
                break;
            }
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
