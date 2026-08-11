<?php
// FAQ-first barber chatbot: local FAQ JSON, Gemini fallback only when no match.

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/ai_gemini_helper.php';
require_once __DIR__ . '/chatbot_faq_helper.php';

require_method('POST');

$input = get_json_input();
$message = trim((string)($input['message'] ?? ''));
$history = $input['history'] ?? [];
$skipFaq = !empty($input['skipFaq']);

if ($message === '') {
    json_response(['error' => 'message is required'], 422);
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

function chatbot_gemini_reply(string $message, string $historyBlock, ?string &$error = null): ?string
{
    if (!ai_gemini_enabled()) {
        $error = 'Gemini API key is not configured on the server';
        return null;
    }

    $prompt = <<<PROMPT
You are Tati AI Barber, a friendly skilled barber assistant for Tati's Barbershop in the Philippines.
Reply in 2-4 short sentences. Be warm and practical.
You can answer greetings, small talk, mood, and general questions — then gently steer toward haircuts, styling, face-shape fit, maintenance, booking, walk-ins, or shop hours when relevant.
If you are unsure about shop-specific facts, suggest booking with a barber or asking staff at the shop.

Conversation so far:
{$historyBlock}

Customer: {$message}
Barber AI:
PROMPT;

    return ai_gemini_generate_plain_text($prompt, 0.65, 700, $error);
}

function chatbot_safe_fallback_reply(): string
{
    return "I'm sorry, I don't have an answer for that yet. You can ask me about appointments, haircuts, barbers, AI recommendations, payments, or other app features.";
}

if (!$skipFaq) {
    $faqPath = __DIR__ . '/data/chatbot_faq.json';
    $faqEntries = chatbot_faq_load_entries($faqPath);
    $faqHit = chatbot_match_faq($message, $faqEntries);
    if ($faqHit !== null && $faqHit['answer'] !== '') {
        json_response([
            'reply' => $faqHit['answer'],
            'source' => 'faq',
            'faqId' => $faqHit['id'],
        ]);
    }
}

$historyBlock = chatbot_format_history($history);
$geminiError = null;
$aiReply = chatbot_gemini_reply($message, $historyBlock, $geminiError);

if ($aiReply !== null && $aiReply !== '') {
    json_response([
        'reply' => $aiReply,
        'source' => 'gemini',
    ]);
}

$fallbackPayload = [
    'reply' => chatbot_safe_fallback_reply(),
    'source' => 'fallback',
];
if ($geminiError !== null && $geminiError !== '') {
    error_log('chatbot.php Gemini fallback: ' . $geminiError);
    $debug = strtolower(trim((string)(getenv('APP_DEBUG') ?: '')));
    if (in_array($debug, ['1', 'true', 'yes'], true)) {
        $fallbackPayload['geminiError'] = $geminiError;
    }
}

json_response($fallbackPayload);
