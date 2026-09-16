<?php
/**
 * Cover for tryon_views_are_duplicated().
 *
 * Run: php scripts/test_view_duplication.php
 *
 * This repo has no PHPUnit, so it follows the existing hand-run CLI convention
 * (see scripts/test_kiosk_guest_name.php). The function under test is pure by
 * design — the surrounding tryon_enforce_view_orientation() calls the sidecar
 * inline and cannot be tested without a live service.
 *
 * Context: a correct pair of profiles turns opposite ways, so their yaws have
 * opposite signs. The SHA-256 guards this replaces never fired, because a
 * duplicated pose still differs by a few hundred bytes.
 */

declare(strict_types=1);

require_once dirname(__DIR__) . '/api/replicate_helper.php';

$failures = 0;
$checks = 0;

function check(string $label, bool $actual, bool $expected): void
{
    global $failures, $checks;
    $checks++;
    if ($actual === $expected) {
        echo "  ok    {$label}\n";
        return;
    }
    $failures++;
    printf("  FAIL  %s (expected %s, got %s)\n",
        $label,
        $expected ? 'duplicate' : 'distinct',
        $actual ? 'duplicate' : 'distinct');
}

echo "tryon_views_are_duplicated()\n";

// --- the good case: a real pair turns opposite ways ----------------------
check('opposite signs, well separated', tryon_views_are_duplicated(-0.42, 0.39), false);
check('opposite signs, hard profiles', tryon_views_are_duplicated(-0.85, 0.91), false);
check('opposite signs, barely past threshold', tryon_views_are_duplicated(-0.13, 0.14), false);

// --- duplication by shared sign -----------------------------------------
check('both turned right', tryon_views_are_duplicated(0.41, 0.38), true);
check('both turned left', tryon_views_are_duplicated(-0.44, -0.51), true);
check('both right, far apart', tryon_views_are_duplicated(0.20, 0.80), true);

// --- duplication by near-identical yaw -----------------------------------
// Two almost-frontal outputs: neither turned far enough for a sign to mean
// anything, so sign alone would call them distinct.
check('near-zero pair straddling zero', tryon_views_are_duplicated(-0.02, 0.03), true);
check('identical yaw', tryon_views_are_duplicated(0.33, 0.33), true);
check('just inside separation band', tryon_views_are_duplicated(-0.04, 0.05), true);

// --- boundary ------------------------------------------------------------
check('exactly at separation, opposite signs', tryon_views_are_duplicated(-0.05, 0.05), false);
check('custom separation honoured', tryon_views_are_duplicated(-0.20, 0.20, 0.50), true);

// --- unknown readings are not evidence -----------------------------------
// Sidecar down or no face found: skip the check rather than guess.
check('left unknown', tryon_views_are_duplicated(null, 0.40), false);
check('right unknown', tryon_views_are_duplicated(-0.40, null), false);
check('both unknown', tryon_views_are_duplicated(null, null), false);

// --- zero is not special -------------------------------------------------
check('both exactly zero', tryon_views_are_duplicated(0.0, 0.0), true);

echo "\n";
if ($failures > 0) {
    echo "FAILED: {$failures} of {$checks} checks\n";
    exit(1);
}
echo "PASSED: all {$checks} checks\n";
exit(0);
