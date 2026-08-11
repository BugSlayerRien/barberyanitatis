class ChatbotFaqEntry {
  const ChatbotFaqEntry({
    required this.id,
    required this.category,
    required this.question,
    required this.keywords,
    required this.answer,
  });

  final String id;
  final String category;
  final String question;
  final List<String> keywords;
  final String answer;

  factory ChatbotFaqEntry.fromJson(Map<String, dynamic> json) {
    final rawKeywords = json['keywords'];
    final keywords = rawKeywords is List
        ? rawKeywords.map((item) => item.toString()).toList()
        : <String>[];

    return ChatbotFaqEntry(
      id: json['id']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      question: json['question']?.toString() ?? '',
      keywords: keywords,
      answer: json['answer']?.toString() ?? '',
    );
  }
}
