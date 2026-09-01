import 'package:shared_preferences/shared_preferences.dart';

/// Hint that a recovery email was requested. This is NOT authorization.
/// Password changes require a recovery session from the clicked link.
class AuthIntentStore {
  AuthIntentStore._();

  static const _recoveryEmailKey = 'auth_pending_password_recovery_email';
  static const _legacyBoolKey = 'auth_pending_password_recovery';

  static Future<void> markRecoveryRequested(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recoveryEmailKey, email.trim().toLowerCase());
    await prefs.remove(_legacyBoolKey);
  }

  static Future<String?> requestedRecoveryEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_recoveryEmailKey)?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static Future<bool> isRecoveryPending() async {
    final email = await requestedRecoveryEmail();
    if (email != null) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_legacyBoolKey) == true;
  }

  static Future<void> clearRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recoveryEmailKey);
    await prefs.remove(_legacyBoolKey);
  }
}
