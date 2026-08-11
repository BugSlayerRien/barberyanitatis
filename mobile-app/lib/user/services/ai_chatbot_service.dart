import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_config.dart';
import 'chatbot_faq_matcher.dart';
import 'chatbot_faq_repository.dart';

class AiChatbotService {
  static const String safeFallbackReply =
      "I'm sorry, I don't have an answer for that yet. You can ask me about appointments, haircuts, barbers, AI recommendations, payments, or other app features.";

  static Future<void> ensureFaqLoaded() => ChatbotFaqRepository.load();

  static bool get isFaqLoaded => ChatbotFaqRepository.hasLoaded;

  static ChatbotFaqMatch? matchLocalFaq(String message) {
    return ChatbotFaqMatcher.match(message, ChatbotFaqRepository.cachedEntries);
  }

  /// FAQ-first orchestration: local match when possible, Gemini API only as fallback.
  static Future<Map<String, dynamic>> sendMessage({
    required String message,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      throw Exception('message is required');
    }

    await ensureFaqLoaded();
    final faqHit = matchLocalFaq(trimmed);
    if (faqHit != null) {
      return {
        'reply': faqHit.answer,
        'source': 'faq',
        'faqId': faqHit.id,
      };
    }

    return requestGeminiFallback(message: trimmed, history: history);
  }

  static Future<Map<String, dynamic>> requestGeminiFallback({
    required String message,
    List<Map<String, dynamic>> history = const [],
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/chatbot.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'history': history,
          'skipFaq': true,
        }),
      );

      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        throw Exception(data['error']?.toString() ?? 'Chatbot request failed');
      }

      final reply = data['reply']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        return {
          'reply': safeFallbackReply,
          'source': 'fallback',
        };
      }

      return data;
    } catch (_) {
      return {
        'reply': safeFallbackReply,
        'source': 'fallback',
      };
    }
  }
}
