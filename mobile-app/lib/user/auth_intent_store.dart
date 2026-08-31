import 'package:shared_preferences/shared_preferences.dart';

/// Survives process death so a Gmail recovery tap after force-stop still
/// opens Change Password even when the PKCE URL has no type=recovery.
class AuthIntentStore {
  AuthIntentStore._();

  static const _recoveryKey = 'auth_pending_password_recovery';

  static Future<void> markRecoveryRequested() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_recoveryKey, true);
  }

  static Future<bool> isRecoveryPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_recoveryKey) ?? false;
  }

  static Future<void> clearRecovery() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recoveryKey);
  }
}
