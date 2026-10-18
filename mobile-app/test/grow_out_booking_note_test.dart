import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/style_length_warning.dart';

/// The warning used to stop at the customer.
///
/// They were shown "this cut usually needs longer hair", they tapped "Book it
/// anyway", and the barber received an ordinary booking with no sign that the
/// hair could not carry the cut. Defending that with "the barber will talk it
/// through" assumed a conversation the system never started -- which is the
/// gap the app exists to close.
void main() {
  group('growOutBookingNote', () {
    test('names the haircut the customer actually wanted', () {
      expect(growOutBookingNote('Modern Mullet'), contains('Modern Mullet'));
    });

    test('says it is a goal, not today\'s cut', () {
      expect(growOutBookingNote('Wolf Cut').toLowerCase(),
          contains('grow-out goal'));
    });

    test('tells the barber what to do today', () {
      final note = growOutBookingNote('Two Block').toLowerCase();
      expect(note, contains('closest version'));
      expect(note, contains('today'));
    });

    test('asks them to answer the question the customer will have', () {
      expect(growOutBookingNote('Pompadour').toLowerCase(), contains('grow'));
    });

    // It travels in special_instructions, which the barber's appointment
    // detail renders as plain text in a 300-character field alongside the
    // customer's own note.
    test('fits beside a customer note without being truncated', () {
      expect(growOutBookingNote('Curly Modern Mullet').length, lessThan(300));
    });

    test('is plain prose, not a code the barber has to decipher', () {
      final note = growOutBookingNote('Pineapple');
      expect(note.contains('{'), isFalse);
      expect(note.contains('_'), isFalse);
      expect(note.endsWith('.'), isTrue);
    });
  });

  group('the caption the customer sees', () {
    test('agrees with what the barber is told', () {
      // Both must name the same haircut, or the customer reads one promise on
      // the preview and the barber another on the appointment.
      expect(growOutCaption('Modern Mullet'), contains('Modern Mullet'));
      expect(growOutBookingNote('Modern Mullet'), contains('Modern Mullet'));
    });

    test('and neither claims the cut can be given today', () {
      expect(growOutCaption('Wolf Cut').toLowerCase(), contains('cannot'));
      expect(growOutBookingNote('Wolf Cut').toLowerCase(),
          isNot(contains('as shown')));
    });
  });
}
