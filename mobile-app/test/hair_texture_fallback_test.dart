import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/user_session.dart';

/// Regression cover for the bug where a customer with visibly curly hair saw
/// "Hair: Straight".
///
/// The server was never the cause -- running the real pipeline over that
/// customer's captures returns Curly, with hair coverage ~0.17 against an
/// obstruction gate of 0.03, so nothing was suppressed. The label came from
/// client-side defaults that substituted 'Straight' whenever the texture field
/// was missing.
void main() {
  group('neutral hair texture fallback', () {
    test('is never Straight', () {
      // Straight asserts the absence of wave and curl, so it is the worst
      // possible stand-in for "we do not know".
      expect(UserSession.neutralHairTexture, isNot('Straight'));
      expect(UserSession.neutralHairTexture, 'Wavy');
    });

    test('a missing texture does not become Straight', () {
      expect(UserSession.normalizeHairTextureLabel(null), 'Wavy');
      expect(UserSession.normalizeHairTextureLabel(''), 'Wavy');
      expect(UserSession.normalizeHairTextureLabel('   '), 'Wavy');
    });

    test('an unrecognised label does not become Straight', () {
      // The server suppresses the texture by sending an empty string, and PHP
      // substitutes 'Wavy' -- but a future value we do not know about must not
      // silently land on Straight either.
      for (final raw in ['unknown', 'kinky', 'n/a', '???', 'null']) {
        expect(UserSession.normalizeHairTextureLabel(raw), 'Wavy',
            reason: 'unrecognised "$raw" should fall back to neutral');
      }
    });

    test('real server answers still pass through untouched', () {
      expect(UserSession.normalizeHairTextureLabel('Straight'), 'Straight');
      expect(UserSession.normalizeHairTextureLabel('Wavy'), 'Wavy');
      expect(UserSession.normalizeHairTextureLabel('Curly'), 'Curly');
    });

    test('casing and padding from the API are tolerated', () {
      expect(UserSession.normalizeHairTextureLabel('CURLY'), 'Curly');
      expect(UserSession.normalizeHairTextureLabel('  curly  '), 'Curly');
      expect(UserSession.normalizeHairTextureLabel('sTrAiGhT'), 'Straight');
    });

    test('coily folds into Curly rather than falling back', () {
      expect(UserSession.normalizeHairTextureLabel('coily'), 'Curly');
      expect(UserSession.normalizeHairTextureLabel('Coily'), 'Curly');
    });

    test('an explicit fallback is still honoured where a caller needs one', () {
      // _hairTextureFromAnalysis passes the current hint as the fallback so a
      // primed value survives a response with no texture field.
      expect(
        UserSession.normalizeHairTextureLabel(null, fallback: 'Curly'),
        'Curly',
      );
      expect(
        UserSession.normalizeHairTextureLabel('Wavy', fallback: 'Curly'),
        'Wavy',
      );
    });
  });
}
