import 'chatbot_faq_entry.dart';

class ChatbotFaqMatch {
  const ChatbotFaqMatch({
    required this.entry,
    required this.score,
  });

  final ChatbotFaqEntry entry;
  final double score;

  String get answer => entry.answer;
  String get id => entry.id;
}

class ChatbotFaqMatcher {
  static const double matchThreshold = 1.2;

  static const Set<String> _stopWords = {
    'a',
    'an',
    'the',
    'is',
    'are',
    'am',
    'be',
    'to',
    'do',
    'i',
    'you',
    'my',
    'me',
    'we',
    'it',
    'of',
    'in',
    'on',
    'at',
    'for',
    'and',
    'or',
    'can',
    'what',
    'how',
    'when',
    'where',
    'why',
    'who',
    'does',
    'did',
    'will',
    'would',
    'could',
    'should',
    'about',
    'tell',
    'please',
  };

  static ChatbotFaqMatch? match(String message, List<ChatbotFaqEntry> entries) {
    final normalized = _normalizeText(message);
    if (normalized.isEmpty || entries.isEmpty) {
      return null;
    }

    final tokens = _tokenize(normalized);
    ChatbotFaqEntry? bestEntry;
    var bestScore = 0.0;

    for (final entry in entries) {
      final score = _scoreEntry(normalized, tokens, entry);
      if (score > bestScore) {
        bestScore = score;
        bestEntry = entry;
      }
    }

    if (bestEntry == null || bestScore < matchThreshold) {
      return null;
    }

    final answer = bestEntry.answer.trim();
    if (answer.isEmpty) {
      return null;
    }

    return ChatbotFaqMatch(entry: bestEntry, score: bestScore);
  }

  static String _normalizeText(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<String> _tokenize(String normalized) {
    return normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length >= 2)
        .toList();
  }

  static double _scoreEntry(
    String normalized,
    List<String> tokens,
    ChatbotFaqEntry entry,
  ) {
    var score = 0.0;
    var keywordHits = 0;

    final question = _normalizeText(entry.question);
    if (question.isNotEmpty) {
      if (normalized == question) {
        score += 8;
      } else if (normalized.contains(question) || question.contains(normalized)) {
        score += 4;
      } else {
        final questionTokens = _tokenize(question)
            .where((token) => !_stopWords.contains(token))
            .toList();
        final meaningfulTokens =
            tokens.where((token) => !_stopWords.contains(token)).toList();
        final overlap =
            meaningfulTokens.toSet().intersection(questionTokens.toSet()).length;
        if (overlap >= 2) {
          score += overlap * 0.9;
          if (score > 3) {
            score = 3;
          }
        }
      }
    }

    for (final keyword in entry.keywords) {
      final kw = _normalizeText(keyword);
      if (kw.isEmpty) {
        continue;
      }

      final keywordMatched = _keywordMatches(normalized, tokens, kw);
      if (!keywordMatched) {
        continue;
      }

      keywordHits++;
      if (kw.contains(' ')) {
        score += 2.8;
      } else {
        score += kw.length >= 5 ? 2.0 : 1.2;
      }
    }

    if (keywordHits > 1) {
      score += (keywordHits - 1) * 0.75;
    }

    return score;
  }

  static bool _keywordMatches(
    String normalized,
    List<String> tokens,
    String keyword,
  ) {
    if (keyword.contains(' ')) {
      return normalized.contains(keyword);
    }

    if (tokens.contains(keyword)) {
      return true;
    }

    for (final token in tokens) {
      if (token.length >= 3 &&
          keyword.length >= 3 &&
          _levenshtein(token, keyword) <= 1) {
        return true;
      }
    }

    final pattern =
        RegExp(r'(^|[^a-z0-9])' + RegExp.escape(keyword) + r'([^a-z0-9]|$)');
    return pattern.hasMatch(normalized);
  }

  static int _levenshtein(String a, String b) {
    if (a == b) {
      return 0;
    }
    if (a.isEmpty) {
      return b.length;
    }
    if (b.isEmpty) {
      return a.length;
    }

    final rows = a.length + 1;
    final cols = b.length + 1;
    final matrix = List.generate(rows, (_) => List<int>.filled(cols, 0));

    for (var i = 0; i < rows; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j < cols; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i < rows; i++) {
      for (var j = 1; j < cols; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((left, right) => left < right ? left : right);
      }
    }

    return matrix[a.length][b.length];
  }
}
