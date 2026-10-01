<?php

declare(strict_types=1);

/**
 * Turning a walk-in row into something a human can act on.
 *
 * The kiosk records what the guest picked as one packed string in
 * `walkin_service_details.special_instructions`, shaped like:
 *
 *     Kiosk walk-in | Path: scan_face | Style: Edgar Cut | Scan: 3-angle capture
 *
 * That is fine for an audit trail and useless on a barber's card, so these
 * helpers pull the parts back out. Shared by the kiosk's own "Check my queue"
 * lookup, the receptionist queue and the barber app, which all have to show a
 * customer the same way.
 */

/** One labelled segment out of the packed instruction string. */
function walkin_instruction_part(string $instructions, string $label): string
{
    foreach (explode('|', $instructions) as $segment) {
        $segment = trim($segment);
        $prefix = $label . ':';
        if (stripos($segment, $prefix) === 0) {
            return trim(substr($segment, strlen($prefix)));
        }
    }

    return '';
}

/** The hairstyle the guest chose at the kiosk, or '' when they browsed past it. */
function kiosk_style_from_instructions(string $instructions): string
{
    return walkin_instruction_part($instructions, 'Style');
}

/** How the guest reached the queue: a face scan, the catalog, or a known style. */
function kiosk_entry_path_from_instructions(string $instructions): string
{
    $path = walkin_instruction_part($instructions, 'Path');

    return match (strtolower($path)) {
        'scan_face', 'scanface' => 'Face scan',
        'browse_catalog', 'catalog' => 'Browsed the catalog',
        'known_style', 'knownstyle' => 'Asked for a specific style',
        default => $path,
    };
}

/**
 * Anything the guest typed that is not one of the labelled segments.
 *
 * Kept separate so a real request ("shorter on the sides") is never buried in
 * the kiosk's own bookkeeping.
 */
function walkin_free_text_instructions(string $instructions): string
{
    $kept = [];
    foreach (explode('|', $instructions) as $segment) {
        $segment = trim($segment);
        if ($segment === '' || strcasecmp($segment, 'Kiosk walk-in') === 0) {
            continue;
        }
        foreach (['Path:', 'Style:', 'Scan:'] as $label) {
            if (stripos($segment, $label) === 0) {
                continue 2;
            }
        }
        $kept[] = $segment;
    }

    return implode(' · ', $kept);
}
