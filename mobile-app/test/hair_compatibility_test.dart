import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/hair_compatibility.dart';
import 'package:tatis_barbershop/user/user_session.dart';

void main() {
  tearDown(() {
    UserSession.lastScan = null;
    UserSession.userId = null;
  });

  void setScan({
    required String texture,
    int userId = 1,
    bool succeeded = true,
    String provider = 'ai-service',
  }) {
    UserSession.userId = userId;
    UserSession.lastScan = {
      'userId': userId,
      'hairTexture': texture,
      'analysisProvider': provider,
      'scanSucceeded': succeeded,
    };
  }

  group('HairCompatibility', () {
    test('no claim without successful scan', () {
      UserSession.userId = 1;
      expect(HairCompatibility.evaluateStyle(styleHairTexture: 'Straight'), isNull);

      setScan(texture: 'Straight', succeeded: false, provider: 'fallback');
      expect(HairCompatibility.evaluateStyle(styleHairTexture: 'Straight'), isNull);
    });

    test('ignores scan from another user', () {
      setScan(texture: 'Straight', userId: 99);
      UserSession.userId = 1;
      expect(HairCompatibility.evaluateStyle(styleHairTexture: 'Straight'), isNull);
    });

    test('Straight user levels', () {
      setScan(texture: 'Straight');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Straight')?.level,
        HairCompatibilityLevel.recommended,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Wavy')?.level,
        HairCompatibilityLevel.possible,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Curly')?.level,
        HairCompatibilityLevel.notRecommended,
      );
    });

    test('Wavy user levels', () {
      setScan(texture: 'Wavy');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Wavy')?.level,
        HairCompatibilityLevel.recommended,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Straight')?.level,
        HairCompatibilityLevel.possible,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Curly')?.level,
        HairCompatibilityLevel.possible,
      );
    });

    test('Curly user levels', () {
      setScan(texture: 'Curly');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Curly')?.level,
        HairCompatibilityLevel.recommended,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Wavy')?.level,
        HairCompatibilityLevel.possible,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Straight')?.level,
        HairCompatibilityLevel.notRecommended,
      );
    });

    test('untagged style is possible', () {
      setScan(texture: 'Straight');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Mixed')?.level,
        HairCompatibilityLevel.possible,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: null)?.level,
        HairCompatibilityLevel.possible,
      );
    });

    test('hard style names for non-curly', () {
      setScan(texture: 'Straight');
      expect(
        HairCompatibility.evaluateStyle(
          styleHairTexture: 'Straight',
          styleName: 'Afro Classic',
        )?.level,
        HairCompatibilityLevel.notRecommended,
      );
    });

    test('newer scan replaces older texture for claims', () {
      setScan(texture: 'Straight');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Straight')?.level,
        HairCompatibilityLevel.recommended,
      );
      setScan(texture: 'Curly');
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Straight')?.level,
        HairCompatibilityLevel.notRecommended,
      );
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Curly')?.level,
        HairCompatibilityLevel.recommended,
      );
    });

    test('manual override after successful scan remains usable', () {
      setScan(texture: 'Wavy', succeeded: true, provider: 'ai-service');
      UserSession.lastScan = {
        ...?UserSession.lastScan,
        'hairTexture': 'Curly',
        'analysisProvider': 'manual',
        'scanSucceeded': true,
      };
      expect(HairCompatibility.hasUsableScanTexture(), isTrue);
      expect(
        HairCompatibility.evaluateStyle(styleHairTexture: 'Curly')?.level,
        HairCompatibilityLevel.recommended,
      );
    });
  });
}
