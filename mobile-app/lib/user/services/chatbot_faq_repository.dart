import 'dart:convert';

import 'package:flutter/services.dart';

import 'chatbot_faq_entry.dart';

class ChatbotFaqRepository {
  static List<ChatbotFaqEntry>? _cache;
  static bool _loadAttempted = false;

  static List<ChatbotFaqEntry> get cachedEntries =>
      List<ChatbotFaqEntry>.unmodifiable(_cache ?? const []);

  static bool get hasLoaded => _loadAttempted;

  static Future<List<ChatbotFaqEntry>> load() async {
    if (_cache != null) {
      return _cache!;
    }

    _loadAttempted = true;
    try {
      final raw = await rootBundle.loadString('assets/data/chatbot_faq.json');
      final decoded = jsonDecode(raw);
      _cache = _parseEntries(decoded);
    } catch (_) {
      _cache = const [];
    }

    return _cache!;
  }

  static List<ChatbotFaqEntry> _parseEntries(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return const [];
    }

    final faqs = decoded['faqs'];
    if (faqs is! List) {
      return const [];
    }

    return faqs
        .whereType<Map>()
        .map((item) => ChatbotFaqEntry.fromJson(Map<String, dynamic>.from(item)))
        .where((entry) => entry.answer.trim().isNotEmpty)
        .toList();
  }
}
