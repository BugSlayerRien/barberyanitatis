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
      // SignOutScope.global, not the default .local.
      //
      // .local only drops the session from this device. The GoTrue session
      // stays alive server-side, and the browser keeps its
      // sb-<project>-auth-token cookie for <project>.supabase.co. Custom Tabs
      // share Chrome's cookie jar, so the NEXT /authorize request arrives
      // already authenticated to GoTrue, which short-circuits and returns an
      // authorization code bound to that existing session instead of creating
      // a PKCE flow state for the new code_challenge. The exchange then fails
      // with flow_state_not_found even though the client generated and stored
      // a fresh verifier -- which is exactly what device logs showed: attempt 1
      // succeeds, attempt 2 gets 404 with a valid, different verifier present.
      //
      // Signing out globally revokes the session so the next authorize starts
      // a genuine new PKCE transaction. It is also simply the correct scope for
      // a shared-device app: "sign out" should end the session everywhere.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    } catch (_) {
      // Offline or already-invalid token: fall back to a local sign-out so the
      // user is still signed out on this device rather than stuck.
      try {
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Continue clearing local session even if remote sign-out fails.
      }
    }

    await UserSession.clear();
    await AuthBootstrap.onSignedOut();

    if (!context.mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthPage()),
      (route) => false,
    );
  }
}
