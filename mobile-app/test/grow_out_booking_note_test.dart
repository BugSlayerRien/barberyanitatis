import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/style_length_warning.dart';

/// A cut the customer's hair cannot carry yet is no longer bookable.
///
/// It used to be: they were warned, they tapped "Book it anyway", and the shop
/// held an appointment for a haircut nobody could give that morning. The
/// defence -- "the barber will talk it through" -- assumed a conversation the
/// system never started, which is the gap the app exists to close.
void main() {
  group('growOutCaption', () {
    test('no longer tells the customer to ask their barber', () {
      final caption = growOutCaption('Pineapple').toLowerCase();
      expect(caption, isNot(contains('ask them')));
      expect(caption, isNot(contains('how long it would take')));
    });

    // An estimate shipped briefly and was removed: mapping four coarse
    // length levels to centimetres produced numbers wrong by months, which is
    // worse than saying nothing.
    test('promises no timeframe it cannot stand behind', () {
      final caption = growOutCaption('Wolf Cut').toLowerCase();
      expect(caption, contains('wolf cut'));
      expect(caption, isNot(contains('months')));
      expect(caption, isNot(contains('year')));
    });

    test('and never claims the cut is possible today', () {
      expect(growOutCaption('Two Block').toLowerCase(),
          contains('cannot be cut'));
    });
  });

  group('styleNeedsMoreLength', () {
    test('is what the booking block turns on', () {
      expect(styleNeedsMoreLength({'min_length_level': 3}, 1), isTrue);
      expect(styleNeedsMoreLength({'min_length_level': 1}, 1), isFalse);
      expect(styleNeedsMoreLength({'minLengthLevel': 2}, 3), isFalse);
    });

    test('a style with no stated length is never blocked', () {
      expect(styleNeedsMoreLength({'style_name': 'Buzz Cut'}, 0), isFalse);
    });
  });

  group('the note the barber gets', () {
    // The only route left to booking a cut that needs more length is to
    // correct the scan by hand. The barber is the one who finds out which
    // reading was right, so they are told that it was corrected.
    test('says the customer overruled the scan', () {
      final note = customerClaimedLengthNote('Modern Mullet').toLowerCase();
      expect(note, contains('modern mullet'));
      expect(note, contains('correct'));
      expect(note, contains('check the length'));
    });

    test('is plain prose that fits beside the customer\'s own note', () {
      final note = customerClaimedLengthNote('Curly Modern Mullet');
      expect(note.length, lessThan(300));
      expect(note.endsWith('.'), isTrue);
    });
  });
}
