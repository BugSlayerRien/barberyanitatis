import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/services/chatbot_faq_entry.dart';
import 'package:tatis_barbershop/user/services/chatbot_faq_matcher.dart';

void main() {
  late List<ChatbotFaqEntry> faqs;

  setUpAll(() {
    final file = File('assets/data/chatbot_faq.json');
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    faqs = (decoded['faqs'] as List)
        .map((item) => ChatbotFaqEntry.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  });

  ChatbotFaqMatch? match(String message) => ChatbotFaqMatcher.match(message, faqs);

  group('ChatbotFaqMatcher', () {
    test('matches exact FAQ question for booking', () {
      final hit = match('How do I book an appointment?');
      expect(hit, isNotNull);
      expect(hit!.id, 'booking_001');
      expect(hit.answer, contains('Appointments'));
    });

    test('matches natural booking variations', () {
      final variations = [
        'How can I book?',
        'I want to make an appointment',
        'How do I schedule a haircut?',
        'Can I book a barber?',
      ];

      for (final message in variations) {
        final hit = match(message);
        expect(hit, isNotNull, reason: 'Expected match for: $message');
        expect(hit!.id, 'booking_001', reason: 'Wrong FAQ for: $message');
      }
    });

    test('matches cancel and reschedule separately', () {
      expect(match('How do I cancel my appointment?')?.id, 'booking_002');
      expect(match('Can I reschedule to another day?')?.id, 'booking_003');
    });

    test('matches keyword-based payment question', () {
      expect(match('How much does a fade cost?')?.id, 'payment_001');
    });

    test('matches AI face scan topics', () {
      expect(match('Tell me about the face scan')?.id, 'ai_scan_001');
      expect(match('How many AI previews can I generate?')?.id, 'ai_preview_002');
    });

    test('matches saved hairstyles and library', () {
      expect(match('Where are my saved haircuts?')?.id, 'favorites_001');
      expect(match('Show me the style library')?.id, 'library_001');
    });

    test('returns null for empty message', () {
      expect(match(''), isNull);
      expect(match('   '), isNull);
    });

    test('returns null for unrelated question without keywords', () {
      expect(match('What is the capital of France?'), isNull);
    });

    test('covers multiple categories in knowledge file', () {
      final categories = faqs.map((entry) => entry.category).toSet();
      expect(categories, contains('appointments'));
      expect(categories, contains('payment'));
      expect(categories, contains('ai_face_scan'));
      expect(categories, contains('favorites'));
      expect(categories, contains('account'));
    });
  });
}
