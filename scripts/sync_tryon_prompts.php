<?php

declare(strict_types=1);

/**
 * Regenerates the Python sidecar's style tables from the PHP ones.
 *
 * ai-service/api.py used to carry a hand-kept copy of replicate_style_prompts()
 * and it had already drifted: the two tables disagreed on which styles existed,
 * so the same haircut was described differently depending on which path served
 * the request. One table is now the source and the other is generated.
 *
 * Run after editing replicate_style_prompts() or replicate_style_min_length():
 *
 *     php scripts/sync_tryon_prompts.php          # rewrite ai-service/api.py
 *     php scripts/sync_tryon_prompts.php --check  # fail if out of date
 *
 * scripts/test_tryon_prompts.php runs the --check form.
 */

require_once __DIR__ . '/../api/replicate_helper.php';

$checkOnly = in_array('--check', $argv, true);
$target = __DIR__ . '/../ai-service/api.py';

if (!is_file($target)) {
    fwrite(STDERR, "ai-service/api.py not found\n");
    exit(1);
}

/** Python literal for a string, single-quoted-safe. */
function py_str(string $value): string
{
    return '"' . str_replace(['\\', '"'], ['\\\\', '\\"'], $value) . '"';
}

/** 'curly_taper_fade' -> 'Curly Taper Fade' */
function style_display_name(string $key): string
{
    return ucwords(str_replace('_', ' ', $key));
}

$prompts = replicate_style_prompts();
$minLengths = replicate_style_min_length();

$generatedBy = '# GENERATED from api/replicate_helper.php by scripts/sync_tryon_prompts.php.'
    . "\n# Edit the PHP table, then re-run that script. Do not edit by hand.\n";

$blocks = [];

$lines = [$generatedBy . 'STYLE_PROMPTS = {'];
foreach ($prompts as $key => $text) {
    $lines[] = '    ' . py_str($key) . ': ' . py_str($text) . ',';
}
$lines[] = '}';
$blocks['STYLE_PROMPTS'] = implode("\n", $lines);

$lines = [$generatedBy . 'STYLE_NAMES = {'];
foreach (array_keys($prompts) as $key) {
    $lines[] = '    ' . py_str($key) . ': ' . py_str(style_display_name($key)) . ',';
}
$lines[] = '}';
$blocks['STYLE_NAMES'] = implode("\n", $lines);

$lines = [$generatedBy . 'STYLE_MIN_LENGTH = {'];
foreach ($prompts as $key => $_) {
    $lines[] = '    ' . py_str($key) . ': ' . (int)($minLengths[$key] ?? 1) . ',';
}
$lines[] = '}';
$blocks['STYLE_MIN_LENGTH'] = implode("\n", $lines);

$source = (string)file_get_contents($target);
$updated = $source;

foreach ($blocks as $name => $block) {
    // Match the assignment through to the closing brace at column 0, plus any
    // generated header already sitting above it.
    $pattern = '/(?:^# GENERATED from[^\n]*\n# Edit the PHP table[^\n]*\n)?^' . preg_quote($name, '/')
        . ' = \{.*?^\}/ms';
    if (preg_match($pattern, $updated) !== 1) {
        fwrite(STDERR, "Could not locate {$name} in ai-service/api.py\n");
        exit(1);
    }
    $updated = (string)preg_replace($pattern, str_replace('$', '\\$', $block), $updated, 1);
}

if ($updated === $source) {
    echo "ai-service/api.py already in sync (" . count($prompts) . " styles)\n";
    exit(0);
}

if ($checkOnly) {
    fwrite(STDERR, "ai-service/api.py is OUT OF SYNC with replicate_style_prompts().\n"
        . "Run: php scripts/sync_tryon_prompts.php\n");
    exit(1);
}

file_put_contents($target, $updated);
echo 'ai-service/api.py updated (' . count($prompts) . " styles)\n";
