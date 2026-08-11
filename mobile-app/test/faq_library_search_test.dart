import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/services/chatbot_faq_entry.dart';
import 'package:tatis_barbershop/user/services/faq_library_search.dart';

void main() {
  final sampleEntries = [
    const ChatbotFaqEntry(
      id: 'booking_001',
      category: 'appointments',
      question: 'How do I book an appointment?',
      keywords: ['book', 'booking', 'appointment'],
      answer: 'Open Appointments and choose a slot.',
    ),
    const ChatbotFaqEntry(
      id: 'payment_001',
      category: 'payment',
      question: 'How does payment work?',
      keywords: ['pay', 'payment', 'gcash'],
      answer: 'Complete payment after choosing your slot.',
    ),
    const ChatbotFaqEntry(
      id: 'ai_scan_001',
      category: 'ai_face_scan',
      question: 'How does AI Face Scan work?',
      keywords: ['face scan', 'ai scan', 'camera'],
      answer: 'Capture front and side photos.',
    ),
  ];

  group('FaqLibrarySearch', () {
    test('filters by category', () {
      final results = FaqLibrarySearch.filter(
        entries: sampleEntries,
        query: '',
        categoryFilter: 'payment',
      );
      expect(results.length, 1);
      expect(results.first.id, 'payment_001');
    });

    test('searches question and keywords', () {
      expect(
        FaqLibrarySearch.filter(entries: sampleEntries, query: 'book').first.id,
        'booking_001',
      );
      expect(
        FaqLibrarySearch.filter(entries: sampleEntries, query: 'gcash').first.id,
        'payment_001',
      );
      expect(
        FaqLibrarySearch.filter(entries: sampleEntries, query: 'AI scan').first.id,
        'ai_scan_001',
      );
    });

    test('returns empty list when nothing matches', () {
      final results = FaqLibrarySearch.filter(
        entries: sampleEntries,
        query: 'nonexistent topic',
      );
      expect(results, isEmpty);
    });
  });
}
