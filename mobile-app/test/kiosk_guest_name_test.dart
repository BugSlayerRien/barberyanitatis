import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/kiosk/kiosk_session.dart';

void main() {
  group('KioskSession guest name length', () {
    final maxLength = KioskSession.guestNameMaxLength;

    test('accepts a name at exactly the limit', () {
      final name = 'a' * maxLength;
      expect(name.length, 70);
      expect(KioskSession.isValidGuestName(name), isTrue);
      expect(KioskSession.guestNameErrorFor(name), isNull);
    });

    test('rejects one character over the limit', () {
      final name = 'a' * (maxLength + 1);
      expect(KioskSession.isValidGuestName(name), isFalse);
      expect(
        KioskSession.guestNameErrorFor(name),
        KioskSession.guestNameTooLongError,
      );
    });

    test('rejects a pathologically long entry', () {
      expect(KioskSession.isValidGuestName('a' * 5000), isFalse);
    });

    test('measures the trimmed name, so padding does not consume the budget',
        () {
      final padded = '   ${'a' * maxLength}   ';
      expect(KioskSession.guestNameErrorFor(padded), isNull);
    });

    test('counts characters, not bytes, for accented names', () {
      // 'é' is two bytes in UTF-8; a byte-based cap would cut these names
      // roughly in half.
      final name = 'é' * maxLength;
      expect(KioskSession.guestNameErrorFor(name), isNull);
      expect(KioskSession.guestNameErrorFor('é' * (maxLength + 1)),
          KioskSession.guestNameTooLongError);
    });

    test('length failure reports the length message, not the format one', () {
      expect(
        KioskSession.guestNameErrorFor('a' * 200),
        isNot(KioskSession.guestNameError),
      );
    });

    test('still enforces the existing format rules', () {
      expect(KioskSession.guestNameErrorFor(''), KioskSession.guestNameError);
      expect(KioskSession.guestNameErrorFor('A'), KioskSession.guestNameError);
      expect(
          KioskSession.guestNameErrorFor('Juan123'), KioskSession.guestNameError);
      expect(KioskSession.guestNameErrorFor('Juan Dela Cruz'), isNull);
    });
  });
}
