<?php
// Hybrid barber chatbot: FAQ JSON first, Gemini fallback.

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/ai_gemini_helper.php';

require_method('POST');

$input = get_json_input();
$message = trim((string)($input['message'] ?? ''));
$history = $input['history'] ?? [];

if ($message === '') {
    json_response(['error' => 'message is required'], 422);
}

$faqPath = __DIR__ . '/data/chatbot_faq.json';
$faqEntries = [];
if (is_readable($faqPath)) {
    $decoded = json_decode((string)file_get_contents($faqPath), true);
    if (is_array($decoded)) {
        $faqEntries = $decoded;
    }
}

/**
 * @return array{answer: string, score: float, id: string}|null
 */
function chatbot_match_faq(string $message, array $faqEntries): ?array
{
    $normalized = strtolower($message);
    $tokens = preg_split('/[^a-z0-9]+/', $normalized) ?: [];
    $tokens = array_values(array_filter($tokens, static fn(string $t): bool => strlen($t) >= 2));

    $best = null;
    $bestScore = 0.0;

    foreach ($faqEntries as $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $keywords = $entry['keywords'] ?? [];
        if (!is_array($keywords)) {
            continue;
        }

        $score = 0.0;
        foreach ($keywords as $keyword) {
            $kw = strtolower(trim((string)$keyword));
            if ($kw === '') {
                continue;
            }
            if (str_contains($normalized, $kw)) {
                $score += strlen($kw) >= 5 ? 2.0 : 1.2;
            }
            foreach ($tokens as $token) {
                if ($token === $kw || levenshtein($token, $kw) <= 1) {
                    $score += 0.8;
                }
            }
        }

        if ($score > $bestScore) {
            $bestScore = $score;
            $best = $entry;
        }
    }

    if ($best === null || $bestScore < 1.5) {
        return null;
    }

    return [
        'answer' => trim((string)($best['answer'] ?? '')),
        'score' => $bestScore,
        'id' => (string)($best['id'] ?? 'faq'),
    ];
}

function chatbot_format_history($history): string
{
    if (!is_array($history)) {
        return '';
    }

    $lines = [];
    foreach (array_slice($history, -8) as $row) {
        if (!is_array($row)) {
            continue;
        }
        $role = !empty($row['isUser']) ? 'Customer' : 'Barber AI';
        $text = trim((string)($row['text'] ?? ''));
        if ($text !== '') {
            $lines[] = "{$role}: {$text}";
        }
    }

    return implode("\n", $lines);
}

function chatbot_gemini_reply(string $message, string $historyBlock): ?string
{
    if (!ai_gemini_enabled()) {
        return null;
    }

    $prompt = <<<PROMPT
You are Tati AI Barber, a friendly skilled barber assistant for Tati's Barbershop in the Philippines.
Give practical, concise advice about haircuts, face shape fit, styling, maintenance, booking, and walk-ins.
If you are unsure, suggest booking with a barber or asking staff at the shop.

Conversation so far:
{$historyBlock}

Customer: {$message}
Barber AI:
PROMPT;

    return ai_gemini_generate_plain_text($prompt, 0.65, 700);
}

$faqHit = chatbot_match_faq($message, $faqEntries);
if ($faqHit !== null && $faqHit['answer'] !== '') {
    json_response([
        'reply' => $faqHit['answer'],
        'source' => 'faq',
        'faqId' => $faqHit['id'],
    ]);
}

$historyBlock = chatbot_format_history($history);
$aiReply = chatbot_gemini_reply($message, $historyBlock);

if ($aiReply !== null && $aiReply !== '') {
    json_response([
        'reply' => $aiReply,
        'source' => 'gemini',
    ]);
}

json_response([
    'reply' => 'I could not find a quick answer. Please ask the front desk or try rephrasing your question about hours, booking, walk-ins, or haircuts.',
    'source' => 'fallback',
]);
