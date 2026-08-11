<?php
// Local FAQ loading and matching for the barber chatbot.

declare(strict_types=1);

/**
 * @return list<array<string, mixed>>
 */
function chatbot_faq_load_entries(string $faqPath): array
{
    if (!is_readable($faqPath)) {
        return [];
    }

    $decoded = json_decode((string)file_get_contents($faqPath), true);
    if (!is_array($decoded)) {
        return [];
    }

    if (isset($decoded['faqs']) && is_array($decoded['faqs'])) {
        return array_values(array_filter($decoded['faqs'], 'is_array'));
    }

    return array_values(array_filter($decoded, 'is_array'));
}

/**
 * @param list<array<string, mixed>> $faqEntries
 * @return array{answer: string, score: float, id: string}|null
 */
function chatbot_match_faq(string $message, array $faqEntries): ?array
{
    $normalized = chatbot_normalize_text($message);
    if ($normalized === '') {
        return null;
    }

    $tokens = chatbot_tokenize($normalized);
    $best = null;
    $bestScore = 0.0;

    foreach ($faqEntries as $entry) {
        $score = chatbot_score_faq_entry($normalized, $tokens, $entry);
        if ($score > $bestScore) {
            $bestScore = $score;
            $best = $entry;
        }
    }

    if ($best === null || $bestScore < 1.2) {
        return null;
    }

    $answer = trim((string)($best['answer'] ?? ''));
    if ($answer === '') {
        return null;
    }

    return [
        'answer' => $answer,
        'score' => $bestScore,
        'id' => (string)($best['id'] ?? 'faq'),
    ];
}

function chatbot_normalize_text(string $text): string
{
    $text = strtolower(trim($text));
    $text = preg_replace('/\s+/', ' ', $text) ?? $text;
    return $text;
}

/**
 * @return list<string>
 */
function chatbot_tokenize(string $normalized): array
{
    $tokens = preg_split('/[^a-z0-9]+/', $normalized) ?: [];
    $tokens = array_values(array_filter(
        $tokens,
        static fn(string $token): bool => strlen($token) >= 2
    ));

    return $tokens;
}

/**
 * @param list<string> $tokens
 * @param array<string, mixed> $entry
 */
function chatbot_score_faq_entry(string $normalized, array $tokens, array $entry): float
{
    $score = 0.0;
    $keywordHits = 0;
    $stopWords = chatbot_stop_words();

    $question = chatbot_normalize_text((string)($entry['question'] ?? ''));
    if ($question !== '') {
        if ($normalized === $question) {
            $score += 8.0;
        } elseif (str_contains($normalized, $question) || str_contains($question, $normalized)) {
            $score += 4.0;
        } else {
            $questionTokens = array_values(array_filter(
                chatbot_tokenize($question),
                static fn(string $token): bool => !isset($stopWords[$token])
            ));
            $meaningfulTokens = array_values(array_filter(
                $tokens,
                static fn(string $token): bool => !isset($stopWords[$token])
            ));
            $overlap = count(array_intersect($meaningfulTokens, $questionTokens));
            if ($overlap >= 2) {
                $score += min(3.0, $overlap * 0.9);
            }
        }
    }

    $keywords = $entry['keywords'] ?? [];
    if (!is_array($keywords)) {
        return $score;
    }

    foreach ($keywords as $keyword) {
        $kw = chatbot_normalize_text((string)$keyword);
        if ($kw === '') {
            continue;
        }

        if (!chatbot_keyword_matches($normalized, $tokens, $kw)) {
            continue;
        }

        $keywordHits++;
        if (str_contains($kw, ' ')) {
            $score += 2.8;
        } else {
            $score += strlen($kw) >= 5 ? 2.0 : 1.2;
        }
    }

    if ($keywordHits > 1) {
        $score += ($keywordHits - 1) * 0.75;
    }

    return $score;
}

/**
 * @param list<string> $tokens
 */
function chatbot_keyword_matches(string $normalized, array $tokens, string $keyword): bool
{
    if (str_contains($keyword, ' ')) {
        return str_contains($normalized, $keyword);
    }

    if (in_array($keyword, $tokens, true)) {
        return true;
    }

    foreach ($tokens as $token) {
        if (strlen($token) >= 3 && strlen($keyword) >= 3 && levenshtein($token, $keyword) <= 1) {
            return true;
        }
    }

    return preg_match('/(^|[^a-z0-9])' . preg_quote($keyword, '/') . '([^a-z0-9]|$)/', $normalized) === 1;
}

/** @return array<string, true> */
function chatbot_stop_words(): array
{
    return array_fill_keys([
        'a', 'an', 'the', 'is', 'are', 'am', 'be', 'to', 'do', 'i', 'you', 'my', 'me', 'we', 'it',
        'of', 'in', 'on', 'at', 'for', 'and', 'or', 'can', 'what', 'how', 'when', 'where', 'why',
        'who', 'does', 'did', 'will', 'would', 'could', 'should', 'about', 'tell', 'please',
    ], true);
}
