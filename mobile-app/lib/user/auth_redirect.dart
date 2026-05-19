import 'package:flutter/foundation.dart';

import 'api_config.dart';
import 'oauth_return_storage.dart';
import 'web_origin_fallback_stub.dart'
    if (dart.library.html) 'web_origin_fallback_web.dart' as web_origin_fb;

/// OAuth redirect targets for Supabase (must match Supabase Auth redirect URLs).
///
/// **Supabase dashboard (do not confuse these):**
/// - **Project URL** (`https://<ref>.supabase.co`) → only for `Supabase.initialize` / REST (already in code).
/// - **Site URL** → your Flutter web app (wildcards are not allowed). Use `http://localhost` or the exact
///   origin you see in the browser (any port each run). **Not** the `.supabase.co` URL.
/// - **Redirect URLs** → include `http://localhost:*` and the callback below with `**` so `?return_to=...` matches.
class AuthRedirect {
  AuthRedirect._();

  /// XAMPP-hosted callback page (no query). Add in Supabase with a wildcard suffix, e.g.
  /// `http://localhost/.../oauth-callback.html**` so `?return_to=` variants match.
  static String get oauthCallbackPageBaseUri {
    final root = ApiConfig.rootUrl.replaceAll(RegExp(r'/+$'), '');
    return '$root/mobile-app/web/oauth-callback.html';
  }

  /// Value passed to Supabase as `redirectTo`. On web, appends `return_to` because
  /// `sessionStorage` on the Flutter origin is invisible to this page (different origin).
  static String get oauthCallbackPageUri {
    final base = oauthCallbackPageBaseUri;
    if (kIsWeb) {
      return '$base?return_to=${Uri.encodeComponent(webAppReturnUri)}';
    }
    return base;
  }

  static String get supabaseRedirectUri {
    if (kIsWeb) {
      return oauthCallbackPageUri;
    }
    return 'io.supabase.flutter://login-callback';
  }

  /// Where the Flutter app is running (used before OAuth on web). Uses the **current** tab origin
  /// (host + port), so any `flutter run` port works — nothing hardcoded.
  static String get webAppReturnUri {
    if (!kIsWeb) {
      return supabaseRedirectUri;
    }

    final fromUriBase = _readWebOrigin();
    if (fromUriBase != null) {
      return fromUriBase.endsWith('/') ? fromUriBase : '$fromUriBase/';
    }

    final fromWindow = web_origin_fb.currentBrowserOrigin().trim();
    if (fromWindow.isNotEmpty && !fromWindow.contains('supabase.co')) {
      return fromWindow.endsWith('/') ? fromWindow : '$fromWindow/';
    }

    // Last resort (e.g. tests); real Flutter web should always have a usable origin above.
    return 'http://localhost/';
  }

  static void prepareWebOAuthReturn() {
    if (!kIsWeb) {
      return;
    }
    saveOAuthReturnTo(webAppReturnUri);
  }

  static String? _readWebOrigin() {
    final base = Uri.base;
    final origin = base.origin.trim();
    if (origin.isNotEmpty &&
        origin != 'null' &&
        !origin.contains('supabase.co')) {
      return origin;
    }
    return null;
  }
}
