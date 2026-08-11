import 'chatbot_faq_entry.dart';

/// Display labels for FAQ JSON [ChatbotFaqEntry.category] values.
class FaqCategoryLabels {
  FaqCategoryLabels._();

  static const Map<String, String> _labels = {
    'appointments': 'Appointments',
    'payment': 'Payments',
    'services': 'Haircuts & Services',
    'barbers': 'Barbers',
    'hours': 'Operating Hours',
    'walkins': 'Walk-ins',
    'ai_face_scan': 'AI Face Scan',
    'ai_recommendations': 'AI Recommendations',
    'ai_preview': 'AI Previews',
    'library': 'Library',
    'favorites': 'Saved Hairstyles',
    'notifications': 'Notifications',
    'account': 'Account',
    'general': 'General Help',
  };

  static String labelFor(String category) {
    final key = category.trim().toLowerCase();
    if (key.isEmpty) {
      return 'General Help';
    }
    return _labels[key] ?? _titleCase(key.replaceAll('_', ' '));
  }

  static String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class FaqLibrarySearch {
  FaqLibrarySearch._();

  static List<ChatbotFaqEntry> filter({
    required List<ChatbotFaqEntry> entries,
    required String query,
    String? categoryFilter,
  }) {
    final normalizedQuery = query.trim().toLowerCase();
    final categoryKey = categoryFilter?.trim().toLowerCase();

    return entries.where((entry) {
      if (categoryKey != null &&
          categoryKey.isNotEmpty &&
          entry.category.toLowerCase() != categoryKey) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      return _matchesQuery(entry, normalizedQuery);
    }).toList();
  }

  static bool _matchesQuery(ChatbotFaqEntry entry, String query) {
    if (entry.question.toLowerCase().contains(query)) {
      return true;
    }

    if (entry.answer.toLowerCase().contains(query)) {
      return true;
    }

    final categoryLabel = FaqCategoryLabels.labelFor(entry.category).toLowerCase();
    if (entry.category.toLowerCase().contains(query) || categoryLabel.contains(query)) {
      return true;
    }

    for (final keyword in entry.keywords) {
      final kw = keyword.toLowerCase();
      if (kw.contains(query) || query.contains(kw)) {
        return true;
      }
      for (final token in query.split(RegExp(r'\s+'))) {
        if (token.length >= 2 && (kw.contains(token) || token.contains(kw))) {
          return true;
        }
      }
    }

    return false;
  }

  static List<String> orderedCategories(List<ChatbotFaqEntry> entries) {
    const preferredOrder = [
      'appointments',
      'payment',
      'services',
      'barbers',
      'ai_face_scan',
      'ai_recommendations',
      'ai_preview',
      'library',
      'favorites',
      'notifications',
      'account',
      'hours',
      'walkins',
      'general',
    ];

    final present = entries.map((e) => e.category.toLowerCase()).toSet();
    final ordered = preferredOrder.where(present.contains).toList();
    for (final category in present) {
      if (!ordered.contains(category)) {
        ordered.add(category);
      }
    }
    return ordered;
  }
}
