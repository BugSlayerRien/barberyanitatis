<?php

// Presentation helpers for audit log entries. Separate from admin_audit.php so
// they can be unit-tested: that file is an endpoint and authenticates on
// include.

declare(strict_types=1);

/** Which part of the business an entry belongs to, decided here rather than by
 *  keyword-guessing on the client (which could only ever match one bucket). */
function audit_event_category(string $actionType, ?string $tableName): string
{
    $haystack = strtolower($actionType . ' ' . (string)$tableName);

    foreach ([
        'money' => ['payment', 'refund', 'intent', 'capture', 'paid', 'revenue'],
        'appointments' => ['appointment', 'booking', 'walkin', 'queue', 'reschedule', 'slot'],
        'users' => ['user', 'customer', 'staff', 'barber', 'receptionist', 'admin', 'account', 'login'],
        'services' => ['service', 'hairstyle', 'haircut', 'catalog', 'overlay', 'variant'],
    ] as $category => $needles) {
        foreach ($needles as $needle) {
            if (str_contains($haystack, $needle)) {
                return $category;
            }
        }
    }

    return 'system';
}

/** "COMPLETE_REFUND" -> "Complete refund". */
function audit_event_title(string $actionType): string
{
    $words = trim(str_replace(['_', '-'], ' ', $actionType));
    if ($words === '') {
        return 'Audit event';
    }

    return ucfirst(strtolower($words));
}

/**
 * Field-level before/after, so a reader can see what actually changed instead
 * of just that something did.
 *
 * @return list<array{field: string, from: mixed, to: mixed}>
 */
function audit_event_changes(?array $old, ?array $new): array
{
    if ($old === null && $new === null) {
        return [];
    }

    $fields = array_unique(array_merge(array_keys($old ?? []), array_keys($new ?? [])));
    sort($fields);

    $changes = [];
    foreach ($fields as $field) {
        $from = $old[$field] ?? null;
        $to = $new[$field] ?? null;
        if ($from === $to) {
            continue;
        }
        $changes[] = [
            'field' => (string)$field,
            'from' => $from,
            'to' => $to,
        ];
    }

    return $changes;
}

function audit_decode_values(?string $raw): ?array
{
    if ($raw === null || trim($raw) === '') {
        return null;
    }
    $decoded = json_decode($raw, true);

    return is_array($decoded) ? $decoded : null;
}
