import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tatis_barbershop/user/user_session.dart';

/// Pins the persisted-phone behaviour behind the cancel-appointment flow.
///
/// UserSession.phone used to be written only by the profile page, so a customer
/// who never opened Profile in that app run was asked to type a contact number
/// when cancelling a paid booking even though their account already had one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UserSession.phone = null;
  });

  group('hasUsablePhone', () {
    test('null and empty are not usable', () {
      UserSession.phone = null;
      expect(UserSession.hasUsablePhone, isFalse);
      UserSession.phone = '';
      expect(UserSession.hasUsablePhone, isFalse);
      UserSession.phone = '   ';
      expect(UserSession.hasUsablePhone, isFalse);
    });

    test('a too-short number is not usable', () {
      UserSession.phone = '12345';
      expect(UserSession.hasUsablePhone, isFalse);
    });

    test('a real PH mobile number is usable', () {
      UserSession.phone = '09171234567';
      expect(UserSession.hasUsablePhone, isTrue);
    });
  });

  group('setPhone / loadPhone', () {
    test('a saved phone survives losing the in-memory value', () async {
      await UserSession.setPhone('09171234567');
      // Simulates a fresh app run: memory is empty, storage is not.
      UserSession.phone = null;
      expect(UserSession.hasUsablePhone, isFalse);

      await UserSession.loadPhone();
      expect(UserSession.phone, '09171234567');
      expect(UserSession.hasUsablePhone, isTrue);
    });

    test('setPhone trims and stores', () async {
      await UserSession.setPhone('  09171234567  ');
      expect(UserSession.phone, '09171234567');
    });

    test('setPhone(null) clears memory and storage', () async {
      await UserSession.setPhone('09171234567');
      await UserSession.setPhone(null);
      expect(UserSession.phone, isNull);

      await UserSession.loadPhone();
      expect(UserSession.phone, isNull);
    });

    test('setPhone with blank input clears rather than storing whitespace', () async {
      await UserSession.setPhone('09171234567');
      await UserSession.setPhone('   ');
      expect(UserSession.phone, isNull);
    });

    test('loadPhone keeps a usable in-memory value', () async {
      await UserSession.setPhone('09171234567');
      UserSession.phone = '09998887777';
      await UserSession.loadPhone();
      expect(UserSession.phone, '09998887777');
    });

    test('loadPhone on a fresh install leaves the phone unknown', () async {
      await UserSession.loadPhone();
      expect(UserSession.phone, isNull);
      expect(UserSession.hasUsablePhone, isFalse);
    });
  });
}
