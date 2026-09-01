import 'dart:math';

/// Pure helpers for one-PKCE-flow-per-OAuth-attempt.
///
/// Each [start] writes one code verifier and one unique redirect. Callbacks
/// from an older attempt must not be exchanged against the current verifier.
class OAuthPkceCoordinator {
  OAuthPkceCoordinator._();

  static const attemptQueryKey = 'oauth_attempt';
  static const attemptPathPrefix = 'oauth';

  static String? _activeAttemptId;
  static String? _activeProvider;
  static final Set<String> _finishedAuthCodes = <String>{};

  static String? get activeAttemptId => _activeAttemptId;
  static String? get activeProvider => _activeProvider;

  static String newAttemptId() {
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-$random';
  }

  static void beginAttempt({
    required String attemptId,
    required String provider,
  }) {
    _activeAttemptId = attemptId;
    _activeProvider = provider;
  }

  static void completeAttempt() {
    _activeAttemptId = null;
    _activeProvider = null;
  }

  static void clearOnLogout() {
    _activeAttemptId = null;
    _activeProvider = null;
    _finishedAuthCodes.clear();
  }

  static String nativeRedirectTo(String attemptId) {
    // Same scheme/host as the working first login. Extra query is preserved
    // on return so a later attempt can ignore a stale code= from an old tab.
    return 'io.supabase.flutter://login-callback?$attemptQueryKey=$attemptId';
  }

  static String? attemptIdFromUri(Uri uri) {
    final fromQuery = uri.queryParameters[attemptQueryKey]?.trim();
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && segments.first == attemptPathPrefix) {
      final id = segments[1].trim();
      if (id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }

  static String? authCodeFromUri(Uri uri) {
    final code = uri.queryParameters['code']?.trim();
    if (code != null && code.isNotEmpty) {
      return code;
    }
    return null;
  }

  static bool alreadyFinishedAuthCode(String? code) {
    if (code == null || code.isEmpty) {
      return false;
    }
    return _finishedAuthCodes.contains(code);
  }

  static void markAuthCodeFinished(String? code) {
    if (code == null || code.isEmpty) {
      return;
    }
    _finishedAuthCodes.add(code);
  }

  /// Recovery callbacks are never treated as stale OAuth.
  ///
  /// A callback with a different attempt id is stale (old Custom Tab / intent).
  /// An untagged callback while an attempt is active is also treated as stale
  /// so it cannot overwrite/exchange against the new verifier. If Supabase
  /// strips the attempt from a *current* redirect, [untaggedWhileActive] is
  /// true and the caller may still try exchange once.
  static OAuthCallbackDisposition dispositionFor({
    required Uri uri,
    required bool recoveryIntent,
    required bool expectingOAuth,
  }) {
    if (recoveryIntent) {
      return OAuthCallbackDisposition.process;
    }
    if (!expectingOAuth || _activeAttemptId == null) {
      return OAuthCallbackDisposition.process;
    }

    final incoming = attemptIdFromUri(uri);
    if (incoming == _activeAttemptId) {
      return OAuthCallbackDisposition.process;
    }
    if (incoming != null && incoming != _activeAttemptId) {
      return OAuthCallbackDisposition.ignoreStale;
    }
    return OAuthCallbackDisposition.untaggedWhileActive;
  }
}

enum OAuthCallbackDisposition {
  process,
  ignoreStale,
  untaggedWhileActive,
}
