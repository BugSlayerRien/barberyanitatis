import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_bootstrap.dart';
import 'auth_page.dart';
import 'user_session.dart';

/// Clears local + Supabase auth and returns to [AuthPage] with no back stack.
class SessionLogout {
  SessionLogout._();

  static Future<void> perform(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Continue clearing local session even if remote sign-out fails.
    }

    await UserSession.clear();
    AuthBootstrap.resetNavigationLock();

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }
}
