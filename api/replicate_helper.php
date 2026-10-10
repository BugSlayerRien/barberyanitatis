<?php
declare(strict_types=1);

/**
 * Replicate Flux Kontext try-on for 3-angle face scan captures.
 * Ported from backend-replicate/api.py — server-side only (REPLICATE_API_TOKEN in .env).
 */

require_once __DIR__ . '/storage.php';
require_once __DIR__ . '/ai_service_client.php';

function replicate_curl_set($ch, array $options): void
{
    curl_setopt_array($ch, $options + api_curl_ssl_options());
}

function replicate_api_token(): string
{
    return trim((string)(getenv('REPLICATE_API_TOKEN') ?: ($_ENV['REPLICATE_API_TOKEN'] ?? '')));
}

function replicate_is_configured(): bool
{
    return replicate_api_token() !== '';
}

function replicate_flux_model(): string
{
    $model = trim((string)(getenv('REPLICATE_FLUX_MODEL') ?: ($_ENV['REPLICATE_FLUX_MODEL'] ?? '')));
    return $model !== '' ? $model : 'black-forest-labs/flux-kontext-pro';
}

/**
 * The haircut itself, described the way a barber would describe it.
 *
 * These were six to nine words each ("low fade hairstyle, gradual fade on
 * sides, natural top"), which is the entire visual specification the model
 * receives -- no reference image is sent, only the customer's own photo. Vague
 * input produced vague haircuts. Each entry now names the fade type and where
 * it starts, guard numbers, the length left on top, the fringe or part, the
 * texture treatment and the neckline, so the model has a shape to render
 * rather than a label to interpret.
 *
 * Keys are the normalised `hairstyles.style_name`; every catalog style must
 * have one. scripts/test_tryon_prompts.php fails the build if one is missing.
 *
 * @return array<string, string>
 */
function replicate_style_prompts(): array
{
    return [
        'buzz_cut' => 'buzz cut: the whole head clipped to one uniform #1 guard length with no '
            . 'graduation anywhere, scalp visible through the hair, a crisp straight edge line at '
            . 'the temples and a squared-off neckline, no fringe, the head shape fully revealed',
        'crew_cut' => 'crew cut: about 1 inch left at the front graduating shorter towards the '
            . 'crown, back and sides tapered with a #2 to #3 guard, a rounded natural silhouette '
            . 'with no fringe and a tapered neckline, neat and conservative',
        'french_crop' => 'french crop: a short blunt fringe cut straight across the forehead, '
            . 'about 1.5 inches of choppy textured length on top pushed forward, a high skin fade '
            . 'on the back and sides starting above the ear, a sharp disconnected line at the temple',
        'caesar_cut' => 'caesar cut: a short horizontal fringe about an inch long combed forward '
            . 'onto the forehead, a uniform 1.5 inches all over the top cut flat and even, '
            . 'tapered short sides and back, a level silhouette with no volume at the front',
        'edgar_cut' => 'edgar cut: a blunt horizontal fringe cut in a hard straight line across '
            . 'the forehead with a sharp right-angled corner at each temple, a flat short top, '
            . 'a high skin fade on the back and sides, no blending between the fringe and the sides',
        'low_fade' => 'low fade: the clipper fade begins just above the ear and finishes at the '
            . 'hairline, skin-bare at the bottom blending up to a #3 within two inches, about '
            . '2 inches left on top combed back naturally, a tapered neckline, the silhouette '
            . 'staying close to the skull',
        'mid_fade' => 'mid fade: the clipper fade starts level with the temples halfway up the '
            . 'side, skin-tight at the bottom blending smoothly to a #2 at the parietal ridge '
            . 'with no visible steps, about 2 inches left on top styled loosely back, a tapered '
            . 'neckline',
        'blowout_taper' => 'blowout taper: the top blown upward and outward into a rounded dome '
            . 'of volume roughly 3 inches tall, the sides tapered short and tight from the temple '
            . 'down in a soft gradient with no hard fade line, the front swept up and back off '
            . 'the forehead',
        'pompadour' => 'pompadour: the front swept dramatically up and back into a tall rounded '
            . 'volume about 3 inches high above the forehead, shortening gradually towards the '
            . 'crown, the sides tapered short and combed back flat, a glossy styled finish with '
            . 'a clean edge at the temple',
        'two_block' => 'two block cut: a clear disconnection between a long full top of 3 to 4 '
            . 'inches and the sides AND lower back clipped short underneath, the top sitting over '
            . 'them like a separate layer, nothing left long at the nape or over the collar, '
            . 'a straight heavy fringe falling to the eyebrows, korean style',
        'barbers_cut' => 'classic barbers cut: short back and sides tapered by hand with scissors, '
            . 'about 1.5 inches on top with a neat side part combed over, a natural tapered '
            . 'neckline, a traditional finish with no fade line anywhere',
        'modern_mullet' => 'modern mullet: a short textured top and fringe with tapered sides, '
            . 'the length deliberately kept long at the back and falling to the nape, a clear '
            . 'contrast between the cropped crown and the long back section',
        'modern_curtains' => 'modern curtains: the hair parted down the middle and falling to '
            . 'either side of the forehead in two soft sweeping sections about 4 inches long '
            . 'reaching the eyebrows, the sides and back tapered short above the collar',
        'messy_quiff' => 'messy quiff: the front lifted up and back into a loose tousled volume '
            . 'about 2.5 inches high, deliberately imperfect with separated pieces, the sides '
            . 'tapered short, no hard parting, a matte undone finish',
        'textured_crop' => 'textured crop: about 2 inches of choppy point-cut texture on top '
            . 'pushed forward into a soft irregular fringe, the sides and back faded short from '
            . 'the temple down, visible separation between the pieces rather than one solid block',
        'wavy_mod_cut' => 'wavy mod cut: a rounded bowl-shaped silhouette with wavy hair cut to '
            . 'one even length around the head, a full fringe sitting straight across the '
            . 'forehead, the sides curving over the ears and the back cut level above the collar',
        'wavy_fringe' => 'wavy fringe: natural waves left about 3 inches long on top falling '
            . 'forward into a soft wavy fringe across the forehead, the sides and back tapered '
            . 'short to a clean neckline, the wave pattern clearly visible and undefined by product',
        'wavy_burst_fade' => 'wavy burst fade: a semicircular fade curving around and behind the '
            . 'ear like a sunburst with the back length left untouched, wavy textured hair 2 to 3 '
            . 'inches long on top, the wave pattern clearly visible, no straight fade line anywhere',
        'wavy_side_sweep' => 'wavy side sweep: wavy hair about 3 inches long combed over to one '
            . 'side in a single sweeping motion from a soft side parting, the sides and back '
            . 'tapered short above the collar, the waves falling diagonally across the forehead',
        'wavy_messy_top' => 'wavy messy top: natural waves left about 3 inches long on top and '
            . 'tousled in no fixed direction, the sides and back tapered short to a clean '
            . 'neckline, a matte texture with clearly separated wavy strands and no product shine',
        'afro_taper' => 'afro taper: natural afro-textured hair left full and rounded on top '
            . 'about 3 inches deep, the sides and back tapered gradually shorter towards the '
            . 'hairline, a dense sponge-textured coil pattern throughout, a clean line-up at the '
            . 'forehead',
        'curly_taper' => 'curly taper: tight curls left full on top about 2 inches deep, the '
            . 'sides and back tapered gradually shorter from the temple down to the neckline, the '
            . 'curls kept intact on top with a soft blend rather than a hard fade line',
        'curly_taper_fade' => 'curly taper fade: curls left full on top about 2.5 inches deep '
            . 'with the coil pattern intact, the sides and back tapered down to skin at the '
            . 'neckline and around the ear, a smooth gradient with the curls blending into the '
            . 'taper rather than sitting on a hard line',
        'curly_low_fade' => 'curly low fade: the fade begins just above the ear and stays low on '
            . 'the head, the curls left full on top about 2.5 inches with the coil pattern intact, '
            . 'a soft blend into the curly crown, a clean neckline and temple line-up',
        'curly_mid_fade' => 'curly mid fade: the clipper fade starts level with the temples and '
            . 'wraps the back, blending from skin to a #2, the curls left 2 to 3 inches long on '
            . 'top with a defined coil pattern, a clean line-up along the forehead hairline',
        'curly_drop_fade' => 'curly drop fade: the fade line drops in a curve behind the ear and '
            . 'down towards the nape instead of running straight, the curls left full on top at '
            . 'about 2.5 inches in defined clumps, a sharp temple line-up',
        'curly_burst_fade' => 'curly burst fade: a semicircular fade arcing around the ear, tight '
            . 'curls left full and round on top about 3 inches deep with the curl pattern clearly '
            . 'defined, the back length left uncut behind the burst',
        'curly_top_fade' => 'curly top fade: the sides and back faded short while a thick round '
            . 'mass of curls is left standing on top 3 to 4 inches tall, a strong contrast between '
            . 'the bare sides and the full curly crown, a clean line-up at the forehead',
        'curly_undercut' => 'curly undercut: the sides and back clipped to one short length with '
            . 'a hard disconnected line and no blending at all, the full curly top left long at '
            . '3 to 4 inches and sitting over the shortened sides like a separate layer',
        'curly_fringe' => 'curly fringe: the curls left long enough at the front to fall forward '
            . 'onto the forehead as a defined curly fringe about 3 inches long, the sides and back '
            . 'tapered short above the collar, the curl pattern clearly visible through the fringe',
        'curly_modern_mullet' => 'curly modern mullet: the curls cropped short at the sides and '
            . 'crown with the curly length deliberately kept long at the back reaching the nape, '
            . 'a clear contrast between the tight sides and the full curly back section',
        'curly_short_crop' => 'curly short crop: tight curls cut short and even to about 1 inch '
            . 'all over the top, the sides and back tapered shorter, the curl pattern still '
            . 'visible as small defined coils, a rounded close-cut silhouette',
        'curly_crew_cut' => 'curly crew cut: the curls clipped to a short uniform length of about '
            . '1 inch on top, graduating shorter towards the sides and back, the curl texture '
            . 'still visible, a rounded even silhouette with a tapered neckline',
        'curly_edgar' => 'curly edgar: a blunt straight horizontal fringe line cut across the '
            . 'forehead through curly hair, a flat short curly top, a high skin fade on the back '
            . 'and sides, a hard contrast between the fringe line and the bare sides',
    ];
}

/** @return array<int, string> */
function replicate_hair_length_labels(): array
{
    return [0 => 'very short', 1 => 'short', 2 => 'medium', 3 => 'long'];
}

/** @return array<int, string> */
function replicate_length_style_hints(): array
{
    return [
        0 => 'Keep the result very short (buzz/crop length). Do not add visible length.',
        1 => 'Keep hair short; do not extend past the ears or add long layers.',
        2 => 'Keep medium length; restyle only, do not add shoulder-length hair.',
        3 => 'You may reshape or shorten slightly, but do not remove all length if the style needs volume.',
    ];
}

/**
 * Shortest hair this style can actually be cut from today. Must cover every
 * key in replicate_style_prompts().
 *
 * @return array<string, int>
 */
function replicate_style_min_length(): array
{
    return [
        'buzz_cut' => 0, 'crew_cut' => 0, 'french_crop' => 0, 'caesar_cut' => 0,
        'edgar_cut' => 0, 'low_fade' => 0, 'mid_fade' => 0, 'barbers_cut' => 0,
        'curly_crew_cut' => 0, 'curly_short_crop' => 0, 'curly_edgar' => 0,
        'blowout_taper' => 1, 'textured_crop' => 1, 'messy_quiff' => 1,
        'wavy_fringe' => 1, 'wavy_burst_fade' => 1, 'wavy_side_sweep' => 1, 'wavy_messy_top' => 1,
        'afro_taper' => 1, 'curly_taper' => 1, 'curly_taper_fade' => 1, 'curly_low_fade' => 1,
        'curly_burst_fade' => 1, 'curly_mid_fade' => 1, 'curly_drop_fade' => 1,
        'curly_fringe' => 1,
        'two_block' => 2, 'modern_curtains' => 2, 'wavy_mod_cut' => 2, 'modern_mullet' => 2,
        'pompadour' => 2, 'curly_top_fade' => 2, 'curly_undercut' => 2,
        'curly_modern_mullet' => 3,
    ];
}

function replicate_normalize_style_key(string $raw): string
{
    $key = strtolower(trim($raw));
    $key = preg_replace('/[^a-z0-9]+/', '_', $key) ?? $key;
    $key = trim($key, '_');
    return $key;
}

/**
 * The prompt key for a catalog style, or null when there is none.
 *
 * This used to return 'barbers_cut' for anything it could not match, and seven
 * catalog styles matched nothing -- Afro Taper, Crew Cut, Curly Fringe, Curly
 * Top Fade, Curly Undercut, Mid Fade and Pompadour all silently rendered as a
 * generic barbers cut. Nobody saw an error; the customer just got the wrong
 * haircut. Returning null lets the caller say so out loud.
 *
 * The longest-label-first ordering of the fuzzy pass matters: 'Curly Low Fade'
 * contains 'low fade', so a shorter key would win and the curl would be lost.
 */
function replicate_resolve_style_key(string $styleName, ?string $styleCode = null): ?string
{
    $prompts = replicate_style_prompts();
    if ($styleCode !== null && $styleCode !== '') {
        $codeKey = replicate_normalize_style_key($styleCode);
        if (isset($prompts[$codeKey])) {
            return $codeKey;
        }
    }

    $nameKey = replicate_normalize_style_key($styleName);
    if (isset($prompts[$nameKey])) {
        return $nameKey;
    }

    $nameLower = strtolower(trim($styleName));
    if ($nameLower === '') {
        return null;
    }

    $keys = array_keys($prompts);
    usort($keys, static fn(string $a, string $b): int => strlen($b) <=> strlen($a));
    foreach ($keys as $key) {
        $label = str_replace('_', ' ', $key);
        if (str_contains($nameLower, $label)) {
            return $key;
        }
    }

    return null;
}

/**
 * Everything the three providers need to describe one style, resolved once.
 *
 * The same twelve lines were copy-pasted into the Replicate, Grok and Gemini
 * entry points, which is how Gemini ended up without the eyeglasses clause.
 *
 * The old "aspirational" branch is gone for good: it swapped the full
 * identity-locked prompt for a much weaker one whenever the measured length
 * fell short, and the measurement defaults to 1 on failure, so a failed scan
 * silently degraded the prompt. $achievableToday is the opposite trade -- the
 * full prompt is kept and a clause is ADDED telling the model to render the
 * cut at the length the customer actually has, rather than imagining more.
 *
 * @return array{ok: bool, error: string, styleKey: string, styleDesc: string,
 *                basePrompt: string, needsMoreLength: bool, minLengthLevel: int}
 */
function replicate_style_brief(
    string $styleName,
    ?string $styleCode,
    int $hairLengthLevel,
    string $hairColorLabel,
    bool $achievableToday = false,
    ?string $dbPrompt = null,
    ?int $dbMinLengthLevel = null
): array {
    $blank = [
        'ok' => false,
        'error' => '',
        'styleKey' => '',
        'styleDesc' => '',
        'basePrompt' => '',
        'needsMoreLength' => false,
        'minLengthLevel' => 1,
    ];

    // A prompt stored with the style wins. This is what makes a hairstyle
    // added through the portal usable: without it, a style absent from the
    // built-in table could never be previewed, no matter how complete its
    // database row was.
    $authored = $dbPrompt !== null ? trim($dbPrompt) : '';
    if ($authored !== '') {
        $styleKey = replicate_resolve_style_key($styleName, $styleCode)
            ?? replicate_normalize_style_key($styleName);
        $styleDesc = $authored;
        $minLevel = $dbMinLengthLevel ?? 1;
    } else {
        $styleKey = replicate_resolve_style_key($styleName, $styleCode);
        if ($styleKey === null) {
            $blank['error'] = 'No try-on prompt is defined for "' . $styleName . '". '
                . 'Add one to this style in the admin portal, or to '
                . 'replicate_style_prompts(), before it can be previewed.';

            return $blank;
        }

        $prompts = replicate_style_prompts();
        $styleDesc = $prompts[$styleKey];
        $minLevel = $dbMinLengthLevel ?? (replicate_style_min_length()[$styleKey] ?? 1);
    }
    $needsMoreLength = $minLevel > $hairLengthLevel;

    $profileNote = ' Use the same haircut design on all three photos, but each output must keep '
        . "that photo's original head turn and camera angle — do not make every frame face the camera.";

    // Swap the description before the prompt is built, rather than appending a
    // contradiction after it. The old order left "the length deliberately kept
    // long at the back" in the prompt and then asked the model not to add
    // length -- and the model, reasonably, drew the mullet it had been
    // described.
    $renderDesc = ($achievableToday && $needsMoreLength)
        ? replicate_short_hair_style_desc($styleKey, $styleDesc, $styleName)
        : $styleDesc;

    $basePrompt = replicate_build_hair_only_prompt(
        $renderDesc,
        $hairLengthLevel,
        $hairColorLabel,
        $achievableToday && $needsMoreLength
    ) . $profileNote;

    if ($achievableToday && $needsMoreLength) {
        $basePrompt .= replicate_achievable_today_clause();
    }

    return [
        'ok' => true,
        'error' => '',
        'styleKey' => $styleKey,
        'styleDesc' => $renderDesc,
        'adaptedToCurrentLength' => $achievableToday && $needsMoreLength,
        'basePrompt' => $basePrompt,
        'needsMoreLength' => $needsMoreLength,
        'minLengthLevel' => $minLevel,
    ];
}

/**
 * Shared hair-only, identity-locked edit prompt used by every image-generation provider
 * (Gemini and the Replicate fallback) so results stay consistent regardless of which
 * provider actually renders the image.
 */
/**
 * Render the cut at the hair the customer has, not the hair the style wants.
 *
 * The customer has already been told this style usually needs more length and
 * chosen to continue, so the honest result is the closest version their barber
 * could cut today -- not a picture of longer hair they do not have. The back is
 * called out specifically because that is where an unconstrained model adds
 * length first: a mullet or a two block on short hair grew a long back.
 */
/**
 * The cutting to perform, for a style that wants more hair than the customer has.
 *
 * Deliberately nameless. "Modern mullet" is a famous haircut and the model has
 * a strong learned picture of one -- a picture whose whole point is a long
 * back. Four rounds of constraints failed to outvote those two words, because
 * the name was still sitting in the instruction doing its work. These say only
 * what the barber's hands do, so there is no style concept to pull against.
 *
 * Written as imperatives for the same reason: "taper the sides" is an action,
 * where "a cut with tapered sides" is a thing to reproduce.
 *
 *
 * Only the styles replicate_style_min_length() marks as needing more than
 * short hair need an entry; everything else already renders honestly.
 *
 * @return array<string, string>
 */
function replicate_style_short_variant(): array
{
    return [
        'two_block' => 'clip the sides and the lower back short in a clean disconnected line, '
            . 'leave the hair on top at exactly its current length and square it off above '
            . 'the disconnection, nothing reaching the collar',
        'modern_curtains' => 'part the hair on top down the middle and sweep it to either '
            . 'side as far as its existing length reaches, falling short of the eyebrows, '
            . 'taper the sides and back close with nothing over the collar',
        'wavy_mod_cut' => 'comb the natural wave forward across the forehead at its current '
            . 'length into a short blunt fringe line, taper the sides and back close to the '
            . 'nape with nothing over the collar',
        'modern_mullet' => 'taper the sides from the temple down and tighten them around the '
            . 'ear, crop and texture the hair on top into a short fringe. The back of the '
            . 'head and the nape are not part of this cut -- leave that area exactly as it '
            . 'appears in the photo, untouched and uncut',
        'pompadour' => 'lift the front up and sweep it back into a modest volume built only '
            . 'from the length already present, fade the sides short, taper the back clean '
            . 'to the nape with nothing over the collar',
        'curly_top_fade' => 'keep the existing curls at exactly their current length on top '
            . 'with no curl length added, taper the sides into a clean fade and cut the back '
            . 'short to the nape',
        'curly_undercut' => 'clip the sides and back short in a disconnected line, leave the '
            . 'curls on top exactly as long as they already are, no length added, the back '
            . 'short to the nape',
        'curly_modern_mullet' => 'crop the curls close at the sides and around the crown, '
            . 'keeping the curl pattern on top. The back of the head and the nape are not '
            . 'part of this cut -- leave that area exactly as it appears in the photo, '
            . 'untouched and uncut',
    ];
}

/**
 * The description to render when the customer has less hair than the cut wants.
 *
 * Falls back to hedging the original description when no short variant is
 * authored -- weaker than a written variant, but still better than a prompt
 * that asserts length the customer does not have.
 */
/**
 * Derive the short-hair version of a prompt that nobody wrote one for.
 *
 * The eight built-in styles that need length have hand-written short variants.
 * Anything added through the barber app or the admin portal does not, and the
 * old fallback simply appended "without adding length anywhere" to a
 * description that had just asked for a long back -- the same self-contradiction
 * that drew a long-backed mullet on short hair. An image model follows the
 * vivid description and ignores the denial that trails it.
 *
 * So the length claims are removed rather than argued with. The work is done
 * clause by clause, because that is how these prompts are actually written: a
 * barber's answers are joined with commas, and so are the built-in ones.
 *
 * Shape is preserved wherever possible. "the top left about 4 inches long and
 * gathered upward into a tall rounded pineapple shape" keeps the pineapple and
 * loses only the four inches -- dropping the whole clause would throw away the
 * part that makes it that haircut.
 */
function replicate_derive_short_variant(string $styleName, string $prompt): string
{
    $prompt = trim($prompt);
    if ($prompt === '') {
        return $prompt;
    }

    // The prompts begin "style name: first clause". Strip the label so it is
    // not treated as a clause, and so the rewritten text can carry its own.
    $body = $prompt;
    if (preg_match('/^([^:]{1,60}):\s*(.+)$/s', $prompt, $m) === 1) {
        $body = $m[2];
    }

    $clauses = array_map('trim', explode(',', $body));
    $kept = [];

    foreach ($clauses as $clause) {
        if ($clause === '') {
            continue;
        }

        $rewritten = replicate_shorten_prompt_clause($clause);
        if ($rewritten !== '') {
            $kept[] = $rewritten;
        }
    }

    // Say one thing about the back, not two.
    //
    // Clauses asking for length at the back were stripped above. Anything
    // still standing is a cutting instruction -- "lower back clipped short
    // underneath" -- which is achievable on short hair and should be kept.
    // Adding the freeze on top of it would contradict it, which is the whole
    // failure mode being fixed here. The freeze is for the case where nothing
    // about the back survived: then the region is genuinely out of scope.
    $mentionsBack = false;
    foreach ($kept as $clause) {
        if (preg_match('/\b(?:back|nape|collar)\b/i', $clause) === 1) {
            $mentionsBack = true;
            break;
        }
    }

    if (!$mentionsBack) {
        $kept[] = 'the back of the head and the nape are not part of this cut, left exactly '
            . 'as they appear in the photo, untouched and uncut';
    }

    // No style name, for the same reason the hand-written variants carry none:
    // naming the haircut hands the model a picture to reproduce, and that
    // picture is exactly the one the customer does not have the hair for.
    // $styleName is still taken so callers need not know that.
    unset($styleName);

    return implode(', ', $kept);
}

/**
 * One clause of a prompt, with any claim to length the customer does not have
 * taken out of it.
 *
 * Returns '' when nothing worth keeping is left.
 */
function replicate_shorten_prompt_clause(string $clause): string
{
    // Clauses that already say hair is NOT long are exactly the phrasing we
    // want ("nothing left over the collar", "tapered short above the collar").
    // A blunter rule would delete them for containing the word "collar".
    if (preg_match('/\b(?:nothing|without|no)\b[^.]*\b(?:long|length|collar|nape|shoulder)\b/i', $clause) === 1) {
        return $clause;
    }

    $out = $clause;

    // 1. Measurements -> current length, keeping whatever shape follows.
    $out = (string)preg_replace(
        '/(?:\b(?:about|around|roughly)\s+)?'
        . '\b(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten)'
        . '(?:\s*(?:to|-|–)\s*(?:\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten))?'
        . '\s*(?:inch|inches|in\.?|cm)\b(?:\s+(?:long|tall|high|in\s+length))?/i',
        'at its current length',
        $out
    );

    // 2. Bare assertions of length.
    $out = (string)preg_replace(
        '/\b(?:deliberately\s+)?(?:kept|left|worn|grown)\s+(?:deliberately\s+)?long(?:est|er)?\b/i',
        'kept at its current length',
        $out
    );
    $out = (string)preg_replace(
        '/\blong(?:er)?\s+(full\s+)?(top|back|length|layers?|section|hair|fringe)\b/i',
        '$1$2',
        $out
    );
    $out = (string)preg_replace('/\bfull\s+curly\s+back\s+section\b/i', 'curly back section', $out);
    // The rules above name the nouns they expect, so an adjective slipped in
    // between defeated them: "long flowing layers" sailed through. Anything
    // still calling itself long after this point is a claim to length, and
    // this clause is not a negated one -- those returned at the top.
    $out = (string)preg_replace('/\blong(?:er|est)?\b(?!\s+as\b)(?!-)/i', '', $out);
    $out = (string)preg_replace('/\bthe\s+length\s+(?=kept|at its current)/i', 'the back ', $out);

    // 3. Length measured against a landmark on the body. Dropped outright,
    //    not softened: "kept clear of the collar" still describes the back,
    //    and describing the back is what invites the model to re-draw it.
    $out = (string)preg_replace(
        '/\b(?:falling|reaching|hanging|extending|coming|flowing)\s+'
        . '(?:down\s+)?(?:just\s+)?(?:(?:to|past|below|over|onto|beyond|towards?)\s+)?'
        . '(?:the\s+)?(?:nape|collar|shoulders?|neck)\b(?:\s+(?:and|onto|over|to)\s+(?:the\s+)?(?:nape|collar|shoulders?|neck)\b)*/i',
        '',
        $out
    );
    $out = (string)preg_replace(
        '/\b(?:just\s+)?(?:past|below|beyond|over)\s+(?:the\s+)?(?:nape|collar|shoulders?)\b'
        . '(?:\s+(?:onto|over|to)\s+(?:the\s+)?(?:nape|collar|shoulders?)\b)*/i',
        '',
        $out
    );

    // 4. Whatever the substitutions left behind.
    //
    // Several rules can land on the same phrase -- "a long full top of 3 to 4
    // inches" is rewritten by two of them -- so the repeats and the dangling
    // prepositions they leave are cleaned up once, here, rather than each rule
    // trying to predict the others.
    $out = (string)preg_replace(
        '/\bat its current length\b(?:\s+(?:of|at|to|in))*(?:\s+at its current length\b)+/i',
        'at its current length',
        $out
    );
    $out = (string)preg_replace('/\b(?:of|at|to|in)\s+at its current length\b/i',
        'at its current length', $out);
    $out = (string)preg_replace('/\bthe back\b(.{0,40}?)\s+at the back\b/i', 'the back$1', $out);
    $out = (string)preg_replace('/\s+([,.])/', '$1', $out);
    $out = (string)preg_replace('/\s{2,}/', ' ', $out);
    $out = trim($out, " \t\n\r-–");

    // A clause reduced to a connective carries nothing.
    if (preg_match('/^(?:and|with|the|a|an|in|of|to)?$/i', $out) === 1) {
        return '';
    }

    // "the back left longest" became "the back kept at its current length",
    // which says nothing the closing freeze does not say better -- and saying
    // anything at all about the back invites the model to re-draw it. Drop it.
    if (preg_match('/^(?:the\s+)?(?:back|nape)\b[^,]{0,40}current length\.?$/i', $out) === 1) {
        return '';
    }

    // Dropping the landmark out of "in soft tapered layers just past the nape"
    // leaves "in soft tapered layers" dangling with nothing to attach to, and
    // a reader -- or a model -- attaches it to whatever came before.
    if (preg_match('/^(?:in|at|with|to|onto|over)\s+(?:\S+\s+){0,3}\S+$/i', $out) === 1) {
        return '';
    }

    return $out;
}

function replicate_short_hair_style_desc(
    ?string $styleKey,
    string $styleDesc,
    string $styleName = ''
): string {
    // A hand-written variant beats a derived one and there are eight of them,
    // for the built-in styles that need length. Everything else -- including
    // every haircut added from the barber app or the portal from now on -- is
    // derived, so nobody has to write a second description.
    $variants = replicate_style_short_variant();
    if ($styleKey !== null && isset($variants[$styleKey])) {
        return $variants[$styleKey];
    }

    return replicate_derive_short_variant($styleName, $styleDesc);
}

function replicate_achievable_today_clause(): string
{
    // Deliberately one sentence. It used to be a paragraph at the very end,
    // competing with everything above it; now that the same rule opens the
    // prompt, this is here for recency, not explanation.
    return ' FINAL CHECK BEFORE YOU RENDER: compare the back of the head against the '
        . 'source photo — it must be identical. If a part of this style needs hair that '
        . 'is not in the photo, leave that part uncut rather than drawing the hair in.';
}

function replicate_build_hair_only_prompt(
    string $styleDescription,
    int $hairLengthLevel = 1,
    string $hairColorLabel = '',
    bool $achievableToday = false
): string {
    $hints = replicate_length_style_hints();
    $labels = replicate_hair_length_labels();
    $lengthHint = $hints[$hairLengthLevel] ?? $hints[1];
    $currentLabel = $labels[$hairLengthLevel] ?? 'short';
    $colorClause = '';
    if (trim($hairColorLabel) !== '') {
        $colorClause = ' Preserve the person\'s natural ' . trim($hairColorLabel)
            . ' hair color exactly. Do not lighten, darken, redden, or recolor the hair.';
    }

    // Swapping the description for an honest one was not enough on its own.
    // This prompt runs to roughly 290 words, and the rule about length used to
    // be its last sentence -- behind identity lock, glasses, clothing,
    // background, lighting and output format. The model read "modern mullet",
    // treated it as the target, and drew one. So the rule now comes first,
    // before the style is named, and the sentence that names the style asks
    // for the closest achievable version rather than the haircut itself.
    $opening = 'Photo-realistic HAIR-ONLY edit of the attached photo. ';
    $target = 'to this exact haircut';
    if ($achievableToday) {
        // "Shape and outline may change; length may not" licensed exactly the
        // wrong thing: reshaping the back of a mullet IS lengthening it, there
        // being nothing else a mullet's back can be. The rule is subtractive
        // now -- cutting is allowed, adding never is, and any part of the
        // style that would need hair the person does not have is left undone
        // rather than invented.
        $opening .= 'HARD CONSTRAINT, APPLIES TO EVERYTHING BELOW: this is a CUT. You may '
            . 'only REMOVE hair. You may never add, extend, lengthen, thicken or draw in '
            . 'hair that is not already in the photo. This person\'s hair is '
            . $currentLabel . '. If any part of the style below would need more hair than '
            . 'they have, DO NOT DO THAT PART — leave that area exactly as photographed, '
            . 'uncut and unchanged. This applies above all to the back of the head and the '
            . 'nape, where there is the least hair to work with. ';
        // Phrased as work to perform, not a result to reproduce. "The closest
        // version of this haircut" still asks for a haircut; the descriptions
        // are now imperatives, and the sentence introducing them should be too.
        $target = 'by performing exactly this cutting and nothing more, using only hair '
            . 'already present';
    }

    // The editable region and the "make it look different" push both have to
    // stand down when the cut is only partly achievable. Listing the back
    // hairline as fair game, and demanding a clearly different silhouette,
    // are instructions to redraw the back -- and a redrawn mullet back is a
    // tail. On the normal path both are correct and stay as they were.
    $region = $achievableToday
        ? 'crown, top, sides, temples and sideburns'
        : 'crown, top, sides, temples, sideburns, and back hairline';
    $thoroughness = $achievableToday
        ? 'Recut every area the style actually reaches, not just the tips or one side. Areas '
            . 'the style cannot reach at this length are left alone — an unchanged back is the '
            . 'correct result here, not a failure. '
        : 'Completely remove the old hairstyle everywhere, not just the tips or one side; the '
            . 'new cut silhouette must look clearly different from the original. ';

    return $opening
        . 'Change ONLY the hair on this '
        . "exact person — {$region} — "
        . "{$target}: \"{$styleDescription}\". Current length: {$currentLabel}. {$lengthHint} "
        . $thoroughness
        . 'Do not paste extra hair onto forehead skin, cheeks, or neck. '
        . replicate_glasses_preservation_clause()
        . 'STRICT IDENTITY LOCK — do not change: face shape, facial features, facial expression, '
        . 'skin tone and texture, blemishes or marks, eyebrows, eyes, eyeglasses if present, ears, '
        . 'neck, body proportions, age, or gender. This must remain the exact same person, not a '
        . 'different or idealized person. '
        . 'Keep the same shirt/clothing and the same room background unchanged. '
        . 'Preserve the original head pose, camera angle, framing, perspective, and lighting '
        . 'direction/intensity exactly as captured in the source photo. '
        . 'Output one single photo-realistic image — not an illustration, sketch, or cartoon.'
        . $colorClause;
}

/**
 * Stated as its own leading sentence rather than left as one item inside the long
 * "STRICT IDENTITY LOCK" list (still kept there too, for reinforcement). A hair edit
 * naturally repaints the temple/sideburn area where glasses arms sit, and a
 * mid-13-item list clause was not enough to reliably stop the model from dropping
 * eyeglasses in that region. Unconditional and harmless when the person has none.
 */
function replicate_glasses_preservation_clause(): string
{
    return 'If the person in the photo is wearing eyeglasses, KEEP THE EXACT SAME '
        . 'EYEGLASSES in the output — same frame shape, color, lens tint, and '
        . 'position on the face. Do not remove them, change their style, or generate '
        . 'the person without glasses. ';
}

/**
 * Per-angle instructions for the three-view try-on. These state what the OUTPUT
 * pose must be, not just what the input is — a reported failure mode was the model
 * defaulting the left/right outputs toward a front-facing pose (sometimes producing
 * two visually similar "front-ish" results instead of three distinct angles), which
 * a hint that only describes the input does nothing to prevent.
 *
 * @return array<string, string>
 */
/**
 * Horizontally mirror JPEG/PNG bytes. Returns null if GD is unavailable or the
 * bytes are not a decodable image.
 */
function tryon_mirror_image_bytes(string $bytes): ?string
{
    if (!function_exists('imagecreatefromstring') || !function_exists('imageflip')) {
        return null;
    }
    $img = @imagecreatefromstring($bytes);
    if ($img === false) {
        return null;
    }
    try {
        if (!@imageflip($img, IMG_FLIP_HORIZONTAL)) {
            return null;
        }
        ob_start();
        $ok = @imagejpeg($img, null, 92);
        $out = (string)ob_get_clean();
        return ($ok && $out !== '') ? $out : null;
    } finally {
        imagedestroy($img);
    }
}

/**
 * Deterministic left/right correctness check for generated try-on views.
 *
 * The generator does not reliably preserve the input head turn: on real scans
 * the LEFT view came back turned the same way as the RIGHT one, so the customer
 * saw two identical-looking profiles. The previous guard only compared SHA-256
 * of the bytes, which never fired because the two images differed by a few
 * hundred bytes while showing the same pose.
 *
 * This instead asks the sidecar which way each face is actually turned and
 * compares the generated view against its own input. A mismatch is corrected by
 * mirroring the output, which is exact, instant and free -- a regeneration costs
 * another paid call and can fail the same way again.
 *
 * @param array<string, string> $resultImages front/left/right bytes, mutated in place
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array<string, string> per-view diagnostics
 */
/**
 * Do the two generated profiles show the same pose?
 *
 * Pure function of two signed yaws so it can be tested without a sidecar — see
 * scripts/test_view_duplication.php. The existing SHA-256 guards never fire
 * because a duplicated pose still differs by a few hundred bytes; yaw sign
 * survives re-encoding, rescaling and lighting changes.
 *
 * A correct pair turns opposite ways, so their yaws have opposite signs. Same
 * sign means both views face the same direction. The near-zero band catches the
 * other duplication shape: two almost-frontal outputs where neither turned far
 * enough for a sign to mean anything.
 */
function tryon_views_are_duplicated(?float $yawLeft, ?float $yawRight, float $minSeparation = 0.10): bool
{
    if ($yawLeft === null || $yawRight === null) {
        return false; // Unknown is not evidence of duplication.
    }

    if (abs($yawLeft - $yawRight) < $minSeparation) {
        return true;
    }

    return ($yawLeft <= 0 && $yawRight <= 0) || ($yawLeft >= 0 && $yawRight >= 0);
}

function tryon_enforce_view_orientation(array &$resultImages, array $capturePaths): array
{
    $report = [];
    // Yaw of each generated profile as finally returned, for the cross-view
    // duplicate check below. Null means we never got a reading for that angle.
    $finalYaw = ['left' => null, 'right' => null];

    foreach (['left', 'right'] as $angle) {
        if (!isset($resultImages[$angle]) || empty($capturePaths[$angle])) {
            continue;
        }

        $inputPath = replicate_absolute_path_from_relative((string)$capturePaths[$angle]);
        $expected = ai_service_face_orientation($inputPath);
        if ($expected === null || $expected === 'front') {
            // Unknown, or the capture is not actually a profile: nothing to enforce.
            $report[$angle] = 'skipped:' . ($expected ?? 'unknown-input');
            continue;
        }

        $tmp = tempnam(sys_get_temp_dir(), 'tryon_');
        if ($tmp === false) {
            $report[$angle] = 'skipped:no-tmp';
            continue;
        }
        file_put_contents($tmp, $resultImages[$angle]);

        // One round trip: the sidecar measures the generated view's head turn
        // and returns mirrored bytes only when it disagrees with the input.
        $corrected = ai_service_enforce_view_orientation($tmp, $expected);

        if ($corrected !== null) {
            @unlink($tmp);
            $resultImages[$angle] = $corrected;
            $report[$angle] = "corrected:mirrored-to-{$expected}";
            // The sidecar mirrored it to match $expected, so the pose is now
            // known-good for this angle even though we have no fresh reading.
            $finalYaw[$angle] = ($expected === 'left') ? -1.0 : 1.0;
            error_log("tryon: {$angle} view was facing the wrong way; mirrored to {$expected}.");
            continue;
        }

        // Local GD fallback for deployments where the sidecar is unreachable.
        $probe = ai_service_face_yaw($tmp);
        $actual = $probe['direction'] ?? null;
        @unlink($tmp);
        if ($actual === null || $actual === $expected) {
            $finalYaw[$angle] = $probe['yaw'] ?? null;
            $report[$angle] = 'ok:' . ($actual ?? 'unverified');
            continue;
        }
        $mirrored = tryon_mirror_image_bytes($resultImages[$angle]);
        if ($mirrored === null) {
            $finalYaw[$angle] = $probe['yaw'] ?? null;
            $report[$angle] = "mismatch:{$actual}!={$expected}:mirror-unavailable";
            continue;
        }
        $resultImages[$angle] = $mirrored;
        // Mirroring flips the head turn, so the yaw sign inverts with it.
        $finalYaw[$angle] = isset($probe['yaw']) ? -$probe['yaw'] : null;
        $report[$angle] = "corrected:{$actual}->{$expected}";
    }

    // Cross-view check. Everything above compares a view against its OWN input,
    // so two outputs showing the same pose pass individually. Comparing them to
    // each other is what catches angle duplication.
    if (tryon_views_are_duplicated($finalYaw['left'], $finalYaw['right'])) {
        foreach (['left', 'right'] as $angle) {
            $report[$angle] = sprintf(
                'duplicate:yaw=%.2f',
                $finalYaw[$angle]
            );
        }
        error_log(sprintf(
            'tryon: left and right previews show the same pose (yaw %.2f vs %.2f); flagged for regeneration.',
            $finalYaw['left'],
            $finalYaw['right']
        ));
    }

    return $report;
}

function replicate_view_angle_hints(): array
{
    return [
        'front' => 'This is the FRONT view. Output must show the subject facing the '
            . 'camera directly, matching the input framing exactly.',
        'left' => 'This is the LEFT-profile view: a side/turned head shot, NOT a '
            . 'front-facing photo. The output MUST keep this same left head turn. Do '
            . 'not straighten the head to face the camera and do not output a '
            . 'front-facing result for this angle.',
        'right' => 'This is the RIGHT-profile view: a side/turned head shot, NOT a '
            . 'front-facing photo, and its head turn is the OPPOSITE direction from '
            . 'the left-profile photo. The output MUST keep this same right head turn '
            . 'and must look visibly different from the left-profile result — do not '
            . 'straighten the head to face the camera and do not reuse or copy the '
            . 'left-profile output.',
    ];
}

function replicate_absolute_path_from_relative(string $relativePath): string
{
    $relativePath = trim($relativePath);
    if ($relativePath === '') {
        return '';
    }

    try {
        return storage_ensure_readable_file($relativePath);
    } catch (Throwable $e) {
        return api_project_root() . DIRECTORY_SEPARATOR . str_replace(['/', '\\'], DIRECTORY_SEPARATOR, ltrim($relativePath, '/'));
    }
}

/**
 * @return array{ok: bool, dataUri: string, error: string}
 */
function replicate_image_to_data_uri(string $absolutePath, int $maxSide = 1280): array
{
    if (!is_readable($absolutePath)) {
        return ['ok' => false, 'dataUri' => '', 'error' => 'Image file not readable'];
    }

    $bytes = file_get_contents($absolutePath);
    if ($bytes === false || $bytes === '') {
        return ['ok' => false, 'dataUri' => '', 'error' => 'Image file is empty'];
    }

    $mime = 'image/jpeg';
    if (function_exists('imagecreatefromstring') && function_exists('imagescale')) {
        $source = @imagecreatefromstring($bytes);
        if ($source !== false) {
            $width = imagesx($source);
            $height = imagesy($source);
            if ($width > 0 && $height > 0 && max($width, $height) > $maxSide) {
                $scale = $maxSide / max($width, $height);
                $newW = max(1, (int)round($width * $scale));
                $newH = max(1, (int)round($height * $scale));
                $scaled = imagescale($source, $newW, $newH);
                if ($scaled !== false) {
                    ob_start();
                    imagejpeg($scaled, null, 90);
                    $jpeg = ob_get_clean();
                    imagedestroy($scaled);
                    if (is_string($jpeg) && $jpeg !== '') {
                        $bytes = $jpeg;
                    }
                }
            }
            imagedestroy($source);
        }
    }

    return [
        'ok' => true,
        'dataUri' => 'data:' . $mime . ';base64,' . base64_encode($bytes),
        'error' => '',
    ];
}

/**
 * @return array{ok: bool, bytes: string, error: string}
 */
function replicate_poll_prediction(string $predictionId, int $maxAttempts = 120, int $sleepSeconds = 2): array
{
    $token = replicate_api_token();
    $url = 'https://api.replicate.com/v1/predictions/' . rawurlencode($predictionId);

    for ($i = 0; $i < $maxAttempts; $i++) {
        if ($i > 0) {
            sleep($sleepSeconds);
        }

        $ch = curl_init($url);
        replicate_curl_set($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => [
                'Authorization: Bearer ' . $token,
                'Content-Type: application/json',
            ],
            CURLOPT_TIMEOUT => 60,
        ]);
        $raw = curl_exec($ch);
        $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        curl_close($ch);

        if (!is_string($raw)) {
            return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'Poll failed'];
        }

        $decoded = json_decode($raw, true);
        if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
            return ['ok' => false, 'bytes' => '', 'error' => 'Replicate poll HTTP error'];
        }

        $status = strtolower((string)($decoded['status'] ?? ''));
        if ($status === 'succeeded') {
            $output = $decoded['output'] ?? null;
            $outputUrl = is_array($output) ? ($output[0] ?? '') : $output;
            if (!is_string($outputUrl) || $outputUrl === '') {
                return ['ok' => false, 'bytes' => '', 'error' => 'Replicate succeeded but returned no image URL'];
            }

            $imgCh = curl_init($outputUrl);
            replicate_curl_set($imgCh, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 120,
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            $imgBytes = curl_exec($imgCh);
            curl_close($imgCh);
            if (!is_string($imgBytes) || $imgBytes === '') {
                return ['ok' => false, 'bytes' => '', 'error' => 'Failed to download generated image'];
            }

            return ['ok' => true, 'bytes' => $imgBytes, 'error' => ''];
        }

        if ($status === 'failed' || $status === 'canceled') {
            $err = (string)($decoded['error'] ?? $status);
            return ['ok' => false, 'bytes' => '', 'error' => 'Replicate job ' . $status . ': ' . $err];
        }
    }

    return ['ok' => false, 'bytes' => '', 'error' => 'Replicate timed out waiting for the result'];
}

/**
 * @return array{ok: bool, bytes: string, error: string}
 */
function replicate_generate_view_image(string $absolutePath, string $basePrompt, string $viewKey, string $extra = ''): array
{
    $token = replicate_api_token();
    if ($token === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'REPLICATE_API_TOKEN is not configured'];
    }

    $data = replicate_image_to_data_uri($absolutePath);
    if (!$data['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => $data['error']];
    }

    $hints = replicate_view_angle_hints();
    $viewPrompt = $basePrompt . ' ' . ($hints[$viewKey] ?? '') . $extra;

    $model = replicate_flux_model();
    $endpoint = 'https://api.replicate.com/v1/models/' . $model . '/predictions';

    $payload = json_encode([
        'input' => [
            'prompt' => $viewPrompt,
            'input_image' => $data['dataUri'],
            'aspect_ratio' => 'match_input_image',
            'prompt_upsampling' => false,
            'output_format' => 'png',
            'safety_tolerance' => 2,
        ],
    ]);
    if ($payload === false) {
        return ['ok' => false, 'bytes' => '', 'error' => 'Failed to encode Replicate payload'];
    }

    $ch = curl_init($endpoint);
    replicate_curl_set($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $token,
            'Content-Type: application/json',
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 120,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $curlError = curl_error($ch);
    curl_close($ch);

    if (!is_string($raw)) {
        return ['ok' => false, 'bytes' => '', 'error' => $curlError !== '' ? $curlError : 'No Replicate response'];
    }

    $decoded = json_decode($raw, true);
    if ($httpCode < 200 || $httpCode >= 300 || !is_array($decoded)) {
        $detail = is_array($decoded)
            ? (string)($decoded['detail'] ?? $decoded['error'] ?? substr($raw, 0, 400))
            : substr($raw, 0, 400);
        return ['ok' => false, 'bytes' => '', 'error' => "Replicate error ({$httpCode}): {$detail}"];
    }

    $status = strtolower((string)($decoded['status'] ?? ''));
    if ($status === 'succeeded') {
        $output = $decoded['output'] ?? null;
        $outputUrl = is_array($output) ? ($output[0] ?? '') : $output;
        if (is_string($outputUrl) && $outputUrl !== '') {
            $imgCh = curl_init($outputUrl);
            replicate_curl_set($imgCh, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 120,
                CURLOPT_FOLLOWLOCATION => true,
            ]);
            $imgBytes = curl_exec($imgCh);
            curl_close($imgCh);
            if (is_string($imgBytes) && $imgBytes !== '') {
                return ['ok' => true, 'bytes' => $imgBytes, 'error' => ''];
            }
        }
    }

    $predictionId = (string)($decoded['id'] ?? '');
    if ($predictionId === '') {
        return ['ok' => false, 'bytes' => '', 'error' => 'Replicate did not return a prediction id'];
    }

    $polled = replicate_poll_prediction($predictionId);
    if (!$polled['ok']) {
        return ['ok' => false, 'bytes' => '', 'error' => ($viewKey . ' view: ' . $polled['error'])];
    }

    return ['ok' => true, 'bytes' => $polled['bytes'], 'error' => ''];
}

/**
 * Generate front/left/right try-on images from stored captures.
 *
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 * @return array{ok: bool, images: array<string, string>, error: string}
 */
function replicate_generate_three_view_previews(
    array $capturePaths,
    string $styleName,
    ?string $styleCode = null,
    int $hairLengthLevel = 1,
    string $hairColorLabel = '',
    bool $achievableToday = false,
    ?string $dbPrompt = null,
    ?int $dbMinLengthLevel = null
): array {
    foreach (['front', 'left', 'right'] as $angle) {
        if (empty($capturePaths[$angle])) {
            return ['ok' => false, 'images' => [], 'error' => "Missing capture: {$angle}"];
        }
    }

    $brief = replicate_style_brief($styleName, $styleCode, $hairLengthLevel,
        $hairColorLabel, $achievableToday, $dbPrompt, $dbMinLengthLevel);
    if (!$brief['ok']) {
        return ['ok' => false, 'images' => [], 'error' => $brief['error']];
    }
    $basePrompt = $brief['basePrompt'];

    $resultImages = [];
    foreach (['front', 'left', 'right'] as $viewKey) {
        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$viewKey]);
        $generated = replicate_generate_view_image($absolute, $basePrompt, $viewKey);
        if (!$generated['ok']) {
            return [
                'ok' => false,
                'images' => [],
                'error' => $generated['error'],
            ];
        }
        $resultImages[$viewKey] = $generated['bytes'];
    }

    replicate_retry_duplicate_views($resultImages, $capturePaths, $basePrompt);
    // Same deterministic left/right guarantee as the Grok path.
    tryon_enforce_view_orientation($resultImages, $capturePaths);

    return [
        'ok' => true,
        'images' => $resultImages,
        'error' => '',
    ];
}

/**
 * Detects an angle whose bytes are byte-identical to another angle's — e.g. left
 * and right both coming back the same, or a profile output identical to front — and
 * retries just that one angle with an explicit anti-duplicate instruction.
 *
 * This only catches an exact byte match. It is a safety net for a genuinely
 * duplicated response, not a general pose-correctness check — two independent
 * stochastic generations that are both wrongly front-facing will usually differ at
 * the pixel level even though they show the same wrong pose, so most of what fixes
 * that class of failure is the anti-front-facing wording in
 * replicate_view_angle_hints(), not this retry.
 *
 * @param array<string, string> $resultImages front/left/right bytes, mutated in place
 * @param array{front: string, left: string, right: string} $capturePaths relative paths
 */
function replicate_retry_duplicate_views(array &$resultImages, array $capturePaths, string $basePrompt): void
{
    $pairs = [
        'left' => ['front', 'right'],
        'right' => ['front', 'left'],
    ];

    foreach ($pairs as $angle => $others) {
        if (!isset($resultImages[$angle])) {
            continue;
        }
        $duplicateOf = null;
        foreach ($others as $other) {
            if (isset($resultImages[$other])
                && hash('sha256', $resultImages[$angle]) === hash('sha256', $resultImages[$other])) {
                $duplicateOf = $other;
                break;
            }
        }
        if ($duplicateOf === null) {
            continue;
        }

        $absolute = replicate_absolute_path_from_relative((string)$capturePaths[$angle]);
        $side = $angle === 'left' ? 'LEFT' : 'RIGHT';
        $oppositeSide = $angle === 'left' ? 'right (nose toward the right)' : 'left (nose toward the left)';
        $retryExtra = " CRITICAL: This output was a duplicate of the {$duplicateOf} view — that is WRONG. "
            . "This input is {$side} profile only: the head must be turned, nose pointing away from "
            . "the {$oppositeSide} side of the frame, clearly different from a straight-on or "
            . 'opposite-side photo.';
        $retry = replicate_generate_view_image($absolute, $basePrompt, $angle, $retryExtra);
        if ($retry['ok']) {
            $resultImages[$angle] = $retry['bytes'];
        }
    }
}

/**
 * Legacy single-image helper (InstantID version path) — kept for compatibility.
 *
 * @return array{ok: bool, imageUrl: string, error: string}
 */
function replicate_tryon_from_face_image(string $imageDataUrl, string $styleName, string $promptExtra = ''): array
{
    $styleKey = replicate_resolve_style_key($styleName);
    $prompts = replicate_style_prompts();
    $styleDesc = $prompts[$styleKey] ?? $styleName;
    $prompt = replicate_build_hair_only_prompt($styleDesc, 1) . ' ' . $promptExtra;

    $version = trim((string)(getenv('REPLICATE_TRYON_VERSION') ?: ''));
    if ($version === '') {
        $version = 'c4c54e3c8c97cd50c2d2fec9bea5b12250426ee87b563a86d917279794976753';
    }

    $token = replicate_api_token();
    if ($token === '') {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'REPLICATE_API_TOKEN is not configured'];
    }

    $payload = json_encode([
        'version' => $version,
        'input' => [
            'image' => $imageDataUrl,
            'prompt' => $prompt,
            'negative_prompt' => 'cartoon, anime, blurry, distorted face, extra limbs',
            'ip_adapter_scale' => 0.8,
            'controlnet_conditioning_scale' => 0.8,
        ],
    ]);

    $ch = curl_init('https://api.replicate.com/v1/predictions');
    replicate_curl_set($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Authorization: Bearer ' . $token,
            'Content-Type: application/json',
            'Prefer: wait',
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_TIMEOUT => 180,
    ]);
    $raw = curl_exec($ch);
    $httpCode = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if (!is_string($raw) || $httpCode < 200 || $httpCode >= 300) {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'Replicate request failed'];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'imageUrl' => '', 'error' => 'Invalid Replicate response'];
    }

    $output = $decoded['output'] ?? null;
    if (is_string($output) && $output !== '') {
        return ['ok' => true, 'imageUrl' => $output, 'error' => ''];
    }
    if (is_array($output) && isset($output[0]) && is_string($output[0])) {
        return ['ok' => true, 'imageUrl' => $output[0], 'error' => ''];
    }

    return ['ok' => false, 'imageUrl' => '', 'error' => 'Replicate returned no image URL'];
}
