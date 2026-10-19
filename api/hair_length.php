<?php

declare(strict_types=1);

/**
 * Hair length: one place that turns the stored label into the level the
 * length check compares against.
 *
 * user_profiles.hair_length has always held a label, because that is what the
 * scan writes. The app's warnings work in levels 0-3. Keeping the translation
 * here means the endpoint and anything else that needs it cannot drift, and
 * it can be tested without running a request.
 */

/**
 * Hair length as the catalogue states it: Very short, Short, Medium, Long.
 *
 * Stored as a label in user_profiles.hair_length because that is what the
 * scan writes, and read back as a level because that is what the length
 * check compares against. One place does the translation so the two cannot
 * drift.
 */
function normalize_hair_length(?string $value): ?string
{
    $normalized = strtolower(trim((string)$value));
    if ($normalized === '') {
        return null;
    }

    return match ($normalized) {
        'very short', 'veryshort', 'buzzed', 'shaved' => 'Very short',
        'short' => 'Short',
        'medium', 'mid' => 'Medium',
        'long' => 'Long',
        default => null,
    };
}

/** The 0-3 level the app's length check uses, or null when unknown. */
function hair_length_label_to_level(?string $label): ?int
{
    return match (normalize_hair_length($label)) {
        'Very short' => 0,
        'Short' => 1,
        'Medium' => 2,
        'Long' => 3,
        default => null,
    };
}
