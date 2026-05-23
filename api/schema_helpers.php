<?php

declare(strict_types=1);

/**
 * Add a CHECK constraint only when it is missing (avoids duplicate-object errors under concurrency).
 */
function ensure_check_constraint(PDO $pdo, string $table, string $constraintName, string $checkExpression): void
{
    $lookup = $pdo->prepare(
        'SELECT 1 FROM pg_constraint WHERE conname = :name LIMIT 1'
    );
    $lookup->execute([':name' => $constraintName]);
    if ($lookup->fetchColumn()) {
        return;
    }

    try {
        $pdo->exec(
            "ALTER TABLE {$table} ADD CONSTRAINT {$constraintName} CHECK ({$checkExpression})"
        );
    } catch (PDOException $e) {
        // Another request may have created it between SELECT and ADD.
        if (str_contains($e->getMessage(), 'already exists')) {
            return;
        }
        throw $e;
    }
}
