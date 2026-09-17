import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/services/face_scan_service.dart';

/// FaceScanQuotaExceededException used to keep only limit/used from the
/// server's 429 response and discard remaining/unlimited/hint, which meant
/// the quota dialog could only ever show the server's canned sentence.
void main() {
  group('FaceScanQuotaExceededException', () {
    test('carries remaining, unlimited and hint through', () {
      final e = FaceScanQuotaExceededException(
        message: "You've reached your free AI hairstyle generation limit (2 styles).",
        limit: 2,
        used: 2,
        remaining: 0,
        unlimited: false,
        hint: 'You can still view or regenerate a style you already tried.',
      );

      expect(e.limit, 2);
      expect(e.used, 2);
      expect(e.remaining, 0);
      expect(e.unlimited, isFalse);
      expect(e.hint, 'You can still view or regenerate a style you already tried.');
    });

    test('defaults remaining/unlimited/hint when the caller omits them', () {
      final e = FaceScanQuotaExceededException(
        message: 'Limit reached.',
        limit: 2,
        used: 2,
      );

      expect(e.remaining, 0);
      expect(e.unlimited, isFalse);
      expect(e.hint, isNull);
    });

    test('toString still returns the server message, unchanged behavior', () {
      final e = FaceScanQuotaExceededException(
        message: 'Limit reached.',
        limit: 2,
        used: 2,
      );
      expect(e.toString(), 'Limit reached.');
    });
  });
}
