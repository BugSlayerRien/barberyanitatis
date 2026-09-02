import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:url_launcher/url_launcher.dart';

import '../app_navigator.dart';
import '../barber/barber_dashboard_page.dart';
import 'api_config.dart';
import 'auth_flow_state.dart';
import 'auth_intent_store.dart';
import 'auth_redirect.dart';
import 'dashboard_page.dart';
import 'oauth_pkce_coordinator.dart';
import 'reset_password_page.dart';
import 'staff_web_portal_page.dart';
import 'supabase_password_identity.dart';
import 'user_session.dart';
import 'web_utils.dart';

/// Central OAuth / recovery / session bootstrap. Navigation is driven only by
/// explicit [AuthArrival] values — never by a leftover session + keyboard/resume.
class AuthBootstrap {
  AuthBootstrap._();

  static final AuthFlowEngine flow = AuthFlowEngine();
  static Future<void>? _applyLock;
  static String? _lastProcessedAuthCallbackUri;
  static VoidCallback? _pendingNavigation;
  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<Uri>? _oauthDeepLinkSubscription;
  static _AuthLifecycleObserver? _lifecycleObserver;
  static bool _handlingAuthCallback = false;
  static Uri? _startupLink;
  static bool _exchangingAuthCode = false;
  static String? _recoveryBoundEmail;
  static String? _recoveryBoundUserId;
  static bool _recoverySessionVerified = false;

  static bool get hasVerifiedRecoverySession =>
      _recoverySessionVerified &&
      (_recoveryBoundEmail ?? '').isNotEmpty &&
      Supabase.instance.client.auth.currentSession != null &&
      _emailsMatch(
        Supabase.instance.client.auth.currentUser?.email,
        _recoveryBoundEmail,
      ) &&
      (_recoveryBoundUserId == null ||
          _recoveryBoundUserId ==
              Supabase.instance.client.auth.currentUser?.id);

  static void _authLog(String message) {
    debugPrint('[AuthBootstrap] $message');
  }

  static bool _emailsMatch(String? a, String? b) {
    final left = (a ?? '').trim().toLowerCase();
    final right = (b ?? '').trim().toLowerCase();
    return left.isNotEmpty && left == right;
  }

  static void _clearRecoveryBinding() {
    _recoveryBoundEmail = null;
    _recoveryBoundUserId = null;
    _recoverySessionVerified = false;
  }

  static void _bindRecoverySession(Session session, {required String source}) {
    final email = (session.user.email ?? '').trim().toLowerCase();
    _recoveryBoundEmail = email;
    _recoveryBoundUserId = session.user.id;
    _recoverySessionVerified = email.isNotEmpty;
    _authLog(
      'recovery session bound source=$source email=$email authUser=${session.user.id}',
    );
  }

  static bool get didNavigateAfterSignIn => flow.state.didNavigate;
  static bool get isHandlingAuthCallback => _handlingAuthCallback;
  static bool get passwordRecoveryActive =>
      flow.state.recoveryActive || flow.state.onRecoveryRoute;

  static void resetNavigationLock() {
    flow.state = flow.state.copyWith(
      didNavigate: false,
      onRecoveryRoute: false,
    );
    _lastProcessedAuthCallbackUri = null;
  }

  static void clearPasswordRecovery() {
    flow.markRecoveryCompleted();
    unawaited(AuthIntentStore.clearRecovery());
  }

  static Future<void> markRecoveryRequested({String? email}) async {
    flow.markRecoveryRequested();
    final value = (email ?? '').trim();
    if (value.isNotEmpty) {
      await AuthIntentStore.markRecoveryRequested(value);
    }
  }

  static void markExpectingOAuth() {
    flow.markExpectingOAuth();
  }

  /// Recovery established by an emailed OTP code instead of a recovery link.
  ///
  /// [session] must come from a successful `verifyOTP(type: OtpType.recovery)`
  /// call, which is itself proof the user controls that mailbox. Binding it
  /// here goes through the same [_bindRecoverySession] path a exchanged
  /// recovery link uses, so [hasVerifiedRecoverySession] gates Change Password
  /// identically — without a deep link, a browser round trip, or a PKCE
  /// exchange. Returns false if the session did not bind (caller should keep
  /// the user on the OTP screen rather than assuming success).
  static Future<bool> completeOtpRecovery(Session session) async {
    // A previously signed-in account's app state must not survive into a
    // recovery for a different email. Mirrors the link flow's
    // _clearBlockingSessionForRecoveryExchange protection.
    await UserSession.clear();

    flow.markRecoveryActive();
    _bindRecoverySession(session, source: 'email_otp');
    await applySupabaseSession(session);

    if (!hasVerifiedRecoverySession) {
      _authLog(
        'otp recovery rejected: session did not bind '
        'email=${session.user.email}',
      );
      return false;
    }

    _authLog('otp recovery verified email=${session.user.email}');
    _queueDestination(AuthDestination.changePassword);
    return true;
  }

  /// Starts one Google/Facebook PKCE authorize + browser session.
  /// A new attempt id is bound to the verifier written by [getOAuthSignInUrl].
  static Future<void> startProviderOAuth(OAuthProvider provider) async {
    markExpectingOAuth();
    _lastProcessedAuthCallbackUri = null;
    _pendingNavigation = null;

    final attemptId = OAuthPkceCoordinator.newAttemptId();
    OAuthPkceCoordinator.beginAttempt(
      attemptId: attemptId,
      provider: provider.name,
    );

    // Must be the exact allowlisted deep link. Extra query (oauth_attempt)
    // is not in Redirect URLs, so GoTrue substitutes Site URL (localhost).
    final redirectTo = AuthRedirect.supabaseRedirectUri;

    AuthRedirect.prepareWebOAuthReturn();

    // 'prompt=select_account' makes Google show its account chooser instead of
    // silently continuing with the last account, which is what allows the user
    // to switch Google accounts from the sign-in screen.
    //
    // This was briefly removed while investigating repeat-sign-in failures, on
    // the theory that the extra screen delayed the round trip past a
    // server-side flow-state window. That theory was disproven (a succeeding
    // and a failing attempt both took exactly 7s), and the app no longer uses
    // the PKCE code exchange at all, so round-trip duration is irrelevant here.
    final queryParams = <String, String>{
      if (provider == OAuthProvider.google) 'prompt': 'select_account',
    };

    _authLog(
      'oauth start provider=${provider.name} attempt=$attemptId '
      'redirectTo=$redirectTo',
    );

    final response = await Supabase.instance.client.auth.getOAuthSignInUrl(
      provider: provider,
      redirectTo: redirectTo,
      queryParams: queryParams.isEmpty ? null : queryParams,
    );

    final authorizeUri = Uri.parse(response.url);
    final encodedRedirect = authorizeUri.queryParameters['redirect_to'];
    _authLog(
      'oauth authorize host=${authorizeUri.host} path=${authorizeUri.path} '
      'queryKeys=${authorizeUri.queryParameters.keys.toList()} '
      'redirect_to=${encodedRedirect ?? "(missing)"}',
    );
    if (!kIsWeb &&
        (encodedRedirect == null ||
            encodedRedirect.contains('localhost') ||
            !encodedRedirect.startsWith(
                'io.supabase.flutter://login-callback'))) {
      _authLog(
        'oauth authorize redirect_to is not the app deep link; refusing to launch',
      );
      OAuthPkceCoordinator.completeAttempt();
      throw StateError(
        'OAuth redirect_to was not io.supabase.flutter://login-callback '
        '(got ${encodedRedirect ?? "none"}). Check Supabase Auth URL config.',
      );
    }

    await _launchOAuthAuthorizeUrl(authorizeUri);
  }

  static Future<void> _launchOAuthAuthorizeUrl(Uri uri) async {
    if (kIsWeb) {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      return;
    }

    // Chrome Custom Tabs load the *current* authorize URL. External Chrome
    // often resumes the previous supabase.co tab and returns a code that does
    // not match this attempt's PKCE verifier (flow_state_not_found).
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        _authLog('browser launch: inAppBrowserView opened=$opened');
        if (opened) {
          return;
        }
        _authLog(
          'browser launch: inAppBrowserView returned opened=false; '
          'falling back to externalApplication (stale-tab-reuse risk)',
        );
      } catch (e) {
        _authLog(
          'inAppBrowserView launch failed: $e; '
          'falling back to externalApplication (stale-tab-reuse risk)',
        );
      }
    }

    final externalOpened =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    _authLog('browser launch: externalApplication opened=$externalOpened');
  }

  static void markPasswordLogin() {
    flow.markPasswordLogin();
  }

  static Future<void> onSignedOut() async {
    if (_exchangingAuthCode) {
      await UserSession.clear();
      _authLog('signedOut during auth-code exchange; keeping recovery/oauth flags');
      return;
    }
    flow.markSignedOut();
    _pendingNavigation = null;
    _lastProcessedAuthCallbackUri = null;
    _handlingAuthCallback = false;
    _clearRecoveryBinding();
    OAuthPkceCoordinator.clearOnLogout();
    await UserSession.clear();
  }

  static void applyPhpAuthUser(Map<String, dynamic> user) {
    final userId = user['userID'] is int
        ? user['userID'] as int
        : int.tryParse('${user['userID']}');
    if (userId != null && userId > 0) {
      UserSession.userId = userId;
    }

    final fullName = user['fullName']?.toString().trim();
    if (fullName != null && fullName.isNotEmpty) {
      UserSession.fullName = fullName;
    }

    final email = user['email']?.toString().trim();
    if (email != null && email.isNotEmpty) {
      UserSession.email = email;
    }

    final roles = (user['roles'] as List<dynamic>? ?? const ['customer'])
        .map((role) => role.toString().toLowerCase())
        .where((role) => role.isNotEmpty)
        .toList();
    UserSession.roles = roles.isNotEmpty ? roles : ['customer'];
    flow.markPasswordLogin();
    resetNavigationLock();
  }

  static Future<void> initialize({Uri? startupLink}) async {
    await _authSubscription?.cancel();
    await _oauthDeepLinkSubscription?.cancel();

    _startupLink = startupLink;
    if (await AuthIntentStore.isRecoveryPending()) {
      flow.markRecoveryRequested();
    }

    _lifecycleObserver ??= _AuthLifecycleObserver();
    WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      await _onAuthStateChange(data);
    });

    final appLinks = AppLinks();
    _oauthDeepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) => unawaited(handleAuthCallbackUri(uri)),
      onError: (_) {},
    );

    Uri? initial = startupLink;
    if (kIsWeb) {
      await handleAuthCallbackUri(Uri.base);
    } else {
      initial ??= await appLinks.getInitialAppLink();
      if (initial != null) {
        await handleAuthCallbackUri(initial);
      }
    }
  }

  static Future<void> _onAuthStateChange(AuthState data) async {
    final eventName = data.event.name;
    final session = data.session;
    _authLog(
      'auth event=$eventName hasSession=${session != null} '
      'email=${session?.user.email ?? "(none)"} '
      'expectingOAuth=${flow.state.expectingOAuth} '
      'recoveryPending=${flow.state.recoveryPending} '
      'userId=${UserSession.userId ?? 0} '
      'exchanging=$_exchangingAuthCode',
    );

    if (session == null || data.event == AuthChangeEvent.signedOut) {
      if (data.event == AuthChangeEvent.signedOut) {
        await onSignedOut();
      }
      return;
    }

    if (data.event == AuthChangeEvent.tokenRefreshed ||
        data.event == AuthChangeEvent.userUpdated) {
      return;
    }

    if (data.event == AuthChangeEvent.initialSession) {
      return;
    }

    final isRecoverySession = sessionLooksLikePasswordRecovery(session);

    if (data.event == AuthChangeEvent.passwordRecovery ||
        (isRecoverySession && !flow.state.expectingOAuth)) {
      flow.markRecoveryActive();
      _bindRecoverySession(session, source: 'auth_event:$eventName');
      await applySupabaseSession(session);
      _queueDestination(AuthDestination.changePassword);
      return;
    }

    AuthArrival arrival = AuthArrival.none;
    if (flow.state.expectingOAuth) {
      arrival = AuthArrival.oauthCallback;
    }

    // Apply the authenticated profile BEFORE decide(). Repeat OAuth often
    // arrives as signedIn with an empty UserSession.userId; staying first
    // left the user on Sign In even though Supabase had a session.
    var ready = (UserSession.userId ?? 0) > 0;
    if (arrival == AuthArrival.oauthCallback) {
      ready = await applySupabaseSession(session);
    }

    final destination = flow.decide(
      event: eventName,
      arrival: arrival,
      sessionIsRecovery: isRecoverySession,
      redirectTypeRecovery: false,
      hasSession: true,
      hasUserId: ready,
    );

    _authLog(
      'auth decide arrival=$arrival dest=$destination ready=$ready '
      'userId=${UserSession.userId ?? 0}',
    );

    if (destination == AuthDestination.changePassword) {
      _queueDestination(AuthDestination.changePassword);
      return;
    }
    if (destination == AuthDestination.dashboard && ready) {
      _queueDestination(AuthDestination.dashboard);
    }
  }

  /// Cold-start only. Never call from AuthPage.
  static Future<bool> restoreSessionOnColdStart() async {
    if (flow.state.didNavigate) {
      return true;
    }

    if (kIsWeb && isSupabaseAuthCallbackUri(Uri.base)) {
      final handled = await handleAuthCallbackUri(Uri.base);
      if (handled || flow.state.didNavigate) {
        return true;
      }
    }

    if (!kIsWeb) {
      try {
        final link = _startupLink ?? await AppLinks().getInitialAppLink();
        if (link != null && isSupabaseAuthCallbackUri(link)) {
          final handled = await handleAuthCallbackUri(link);
          if (handled || flow.state.didNavigate) {
            return true;
          }
        }
      } catch (_) {}
    }

    if (flow.state.signedOutIdle) {
      return false;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return flow.state.didNavigate;
    }

    // A leftover recovery-requested flag is not a recovery session.
    // Only AMR recovery (from an exchanged link) may open Change Password.
    final isRecoverySession = sessionLooksLikePasswordRecovery(session);
    if (isRecoverySession) {
      _bindRecoverySession(session, source: 'cold_start_persisted');
    }
    final ready = await applySupabaseSession(session);
    final destination = flow.decide(
      event: 'signedIn',
      arrival: isRecoverySession
          ? AuthArrival.recoveryCallback
          : AuthArrival.splashRestore,
      sessionIsRecovery: isRecoverySession,
      redirectTypeRecovery: false,
      hasSession: true,
      hasUserId: ready,
    );

    _authLog(
      'cold-start restore dest=$destination recoveryAmr=$isRecoverySession '
      'recoveryPending=${flow.state.recoveryPending} ready=$ready '
      'email=${session.user.email}',
    );

    if (destination == AuthDestination.changePassword) {
      _goToRecoveryPassword();
      return true;
    }
    if (destination == AuthDestination.dashboard && ready) {
      navigateToSignedInHome();
      return true;
    }
    return flow.state.didNavigate;
  }

  static bool isSupabaseAuthCallbackUri(Uri uri) {
    if (uri.scheme == 'io.supabase.flutter' && uri.host == 'login-callback') {
      return true;
    }
    if (!kIsWeb) {
      return false;
    }
    final fragmentParameters = _readAuthCallbackParameters(uri);
    final hasOAuthFragment = fragmentParameters.containsKey('access_token') ||
        fragmentParameters.containsKey('refresh_token') ||
        fragmentParameters.containsKey('error') ||
        fragmentParameters.containsKey('error_description');
    final hasOAuthQuery = uri.queryParameters.containsKey('code');
    return hasOAuthFragment || hasOAuthQuery;
  }

  static Future<bool> handleAuthCallbackUri(Uri uri) async {
    if (!isSupabaseAuthCallbackUri(uri)) {
      return false;
    }

    final coldStart = _startupLink != null &&
        _startupLink.toString() == uri.toString();
    _authLog(
      'callback received coldStart=$coldStart ${_uriDebug(uri)} '
      'expectingOAuth=${flow.state.expectingOAuth} '
      'recoveryPending=${flow.state.recoveryPending} '
      'oauthAttempt=${OAuthPkceCoordinator.attemptIdFromUri(uri) ?? "(none)"} '
      'activeAttempt=${OAuthPkceCoordinator.activeAttemptId ?? "(none)"}',
    );

    final uriRecovery = _uriLooksLikeRecovery(uri);
    final recoveryIntent = uriRecovery ||
        (flow.state.recoveryPending && !flow.state.expectingOAuth);

    final disposition = OAuthPkceCoordinator.dispositionFor(
      uri: uri,
      recoveryIntent: recoveryIntent,
      expectingOAuth: flow.state.expectingOAuth,
    );
    if (disposition == OAuthCallbackDisposition.ignoreStale) {
      _authLog(
        'callback ignored: stale oauth attempt '
        '(does not match active PKCE flow)',
      );
      return false;
    }
    if (disposition == OAuthCallbackDisposition.untaggedWhileActive) {
      _authLog(
        'callback untagged while oauth attempt is active; '
        'will exchange once (redirect may have stripped oauth_attempt)',
      );
    }

    final authCode = OAuthPkceCoordinator.authCodeFromUri(uri);
    if (OAuthPkceCoordinator.alreadyFinishedAuthCode(authCode)) {
      _authLog('callback ignored: auth code already finished');
      return false;
    }

    final uriKey = uri.toString();
    if (_lastProcessedAuthCallbackUri == uriKey) {
      _authLog('callback ignored: already exchanged this URI; flushing navigation');
      if (hasVerifiedRecoverySession) {
        _queueDestination(AuthDestination.changePassword);
      } else if ((UserSession.userId ?? 0) > 0) {
        _queueDestination(AuthDestination.dashboard);
      } else {
        flushPendingNavigation();
      }
      return true;
    }
    _handlingAuthCallback = true;

    try {
      final fragmentParameters = _readAuthCallbackParameters(uri);
      final hasCode = uri.queryParameters.containsKey('code') ||
          fragmentParameters.containsKey('code');
      // Implicit flow returns the session itself in the fragment
      // (#access_token=...&refresh_token=...) rather than a code to exchange.
      // getSessionFromUrl handles that shape directly: it builds the session
      // from the access token. Without this, such a callback fell through to
      // _recoverSessionFromFragment, which discards the valid access token and
      // tries to redeem the refresh token instead — that grant fails with
      // refresh_token_not_found and a good session was thrown away.
      final hasAccessToken = uri.queryParameters.containsKey('access_token') ||
          fragmentParameters.containsKey('access_token');

      var redirectTypeRecovery = false;
      var exchangedFromUrl = false;
      Session? session;

      if (recoveryIntent) {
        await _clearBlockingSessionForRecoveryExchange();
      }

      // detectSessionInUri is true, so the SDK's own deep-link observer is
      // also handling this callback and has usually already exchanged the
      // code by the time we get here. An authorization code is single-use:
      // whichever consumer runs second gets flow_state_not_found. So adopt
      // the session the SDK just created instead of racing it for a code
      // that is already spent.
      //
      // Gated to the OAuth path only. A recovery callback must never adopt an
      // ambient session — it has to bind to the account the link was issued
      // for, which _bindRecoverySession enforces after a real exchange.
      // expectingOAuth is only true between tapping a provider button and its
      // callback, and logout nulls currentSession, so this cannot pick up a
      // previously signed-in account.
      if (!recoveryIntent && flow.state.expectingOAuth) {
        final sdkSession = Supabase.instance.client.auth.currentSession;
        if (sdkSession != null) {
          session = sdkSession;
          _authLog(
            'oauth adopting session already established by the SDK observer '
            'email=${sdkSession.user.email}',
          );
        }
      }

      if (session == null && (hasCode || hasAccessToken || uriRecovery)) {
        _exchangingAuthCode = true;
        try {
          final response = await _exchangeAuthCallbackUrl(
            _normalizeAuthCallbackUri(uri),
          );
          session = response.session;
          exchangedFromUrl = true;
          if (response.redirectType == 'recovery') {
            redirectTypeRecovery = true;
          }
          _authLog(
            'getSessionFromUrl ok redirectType=${response.redirectType} '
            'email=${session.user.email}',
          );
        } catch (e) {
          _authLog('getSessionFromUrl failed: $e');
          OAuthPkceCoordinator.markAuthCodeFinished(authCode);
        } finally {
          _exchangingAuthCode = false;
        }
      }

      session ??= await _recoverSessionFromFragment(uri);

      // Never fall back to a leftover currentSession when the code exchange
      // for *this* callback failed — that would silently sign the user into
      // whatever account happened to be cached instead of surfacing the
      // failure. Duplicate delivery of an already-exchanged code is already
      // handled above via _lastProcessedAuthCallbackUri / alreadyFinishedAuthCode.
      if (session == null) {
        _authLog('no session recovered from auth callback');
        return false;
      }

      final isRecoverySession = sessionLooksLikePasswordRecovery(session);
      final recovery = uriRecovery ||
          redirectTypeRecovery ||
          isRecoverySession ||
          (recoveryIntent && exchangedFromUrl);

      if (recoveryIntent && !recovery) {
        _authLog(
          'rejecting recovery: callback did not establish a recovery session '
          'email=${session.user.email} amrRecovery=$isRecoverySession '
          'redirectTypeRecovery=$redirectTypeRecovery exchanged=$exchangedFromUrl',
        );
        return false;
      }

      if (recovery) {
        flow.markRecoveryActive();
        _bindRecoverySession(
          session,
          source: exchangedFromUrl ? 'callback_exchange' : 'callback_fragment',
        );
      } else {
        flow.markExpectingOAuth();
        _clearRecoveryBinding();
      }

      final ready = await applySupabaseSession(session);
      _lastProcessedAuthCallbackUri = uriKey;
      OAuthPkceCoordinator.markAuthCodeFinished(authCode);
      if (!recovery) {
        OAuthPkceCoordinator.completeAttempt();
      }
      if (kIsWeb) {
        try {
          clearUrlFragment();
        } catch (_) {}
      }

      final destination = flow.decide(
        event: recovery ? 'passwordRecovery' : 'signedIn',
        arrival: recovery
            ? AuthArrival.recoveryCallback
            : AuthArrival.oauthCallback,
        sessionIsRecovery: isRecoverySession,
        redirectTypeRecovery: redirectTypeRecovery,
        hasSession: true,
        hasUserId: ready,
      );

      _authLog(
        'callback decide dest=$destination recovery=$recovery ready=$ready '
        'userId=${UserSession.userId ?? 0} email=${session.user.email}',
      );

      if (destination == AuthDestination.changePassword) {
        _queueDestination(AuthDestination.changePassword);
        return true;
      }
      if (destination == AuthDestination.dashboard) {
        if (ready) {
          _queueDestination(AuthDestination.dashboard);
          return true;
        }
        _pendingNavigation = () {
          if ((UserSession.userId ?? 0) > 0) {
            navigateToSignedInHome();
          }
        };
        return false;
      }
      return false;
    } catch (e, stack) {
      _authLog('OAuth/recovery callback failed: $e\n$stack');
      _lastProcessedAuthCallbackUri = null;
      return false;
    } finally {
      _exchangingAuthCode = false;
      _handlingAuthCallback = false;
    }
  }

  /// Exchanges the callback URL for a session. `flow_state_not_found` (404)
  /// means GoTrue's server has no PKCE flow state for this code.
  ///
  /// Root cause is UNRESOLVED and is believed to be server-side, not a client
  /// bug. Ruled out by testing against Supabase Auth logs: elapsed time (a
  /// succeeding and a failing attempt both took exactly 7s authorize→callback),
  /// Custom Tabs vs. external browser (`inAppBrowserView opened=true` on both),
  /// stale browser cookies (cleared, still failed), and client-side verifier
  /// storage (verified against gotrue SDK source — a fresh verifier is written
  /// and read on every attempt). The observed pattern is that the first OAuth
  /// sign-in of an app session succeeds and the next one fails deterministically.
  ///
  /// This retry does not fix that pattern. It is kept only as a cheap safety
  /// net for a genuinely transient failure: one retry after a short pause,
  /// nothing more. Every other error fails immediately, and a repeat of the
  /// same error is not retried again.
  static Future<AuthSessionUrlResponse> _exchangeAuthCallbackUrl(
    Uri uri,
  ) async {
    try {
      return await Supabase.instance.client.auth.getSessionFromUrl(uri);
    } on AuthException catch (e) {
      if (e.code != 'flow_state_not_found') {
        rethrow;
      }
      _authLog(
        'getSessionFromUrl flow_state_not_found on first try; '
        'retrying once in case of a server-side propagation delay',
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return await Supabase.instance.client.auth.getSessionFromUrl(uri);
    }
  }

  static Future<void> _clearBlockingSessionForRecoveryExchange() async {
    final current = Supabase.instance.client.auth.currentSession;
    if (current == null) {
      return;
    }
    // Do NOT Supabase.signOut() here: signOut deletes the PKCE code verifier
    // required to exchange the recovery/OAuth authorization code.
    _authLog(
      'clearing app UserSession before recovery exchange; '
      'supabase session remains until getSessionFromUrl replaces it '
      'email=${current.user.email}',
    );
    await UserSession.clear();
  }

  static String _uriDebug(Uri uri) {
    final fragment = _readAuthCallbackParameters(uri);
    final type = uri.queryParameters['type'] ?? fragment['type'] ?? '(none)';
    final hasCode = uri.queryParameters.containsKey('code') ||
        fragment.containsKey('code');
    return 'scheme=${uri.scheme} host=${uri.host} path=${uri.path} '
        'queryKeys=${uri.queryParameters.keys.toList()} '
        'fragmentKeys=${fragment.keys.toList()} type=$type code=$hasCode';
  }

  static Future<Session?> _recoverSessionFromFragment(Uri uri) async {
    final fragmentParameters = _readAuthCallbackParameters(uri);
    final accessToken = fragmentParameters['access_token'];
    final refreshToken = fragmentParameters['refresh_token'];
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      return null;
    }

    try {
      final response =
          await Supabase.instance.client.auth.setSession(refreshToken);
      return response.session;
    } catch (e) {
      debugPrint('[AuthBootstrap] setSession from fragment failed: $e');
      return null;
    }
  }

  /// Returns true when [UserSession.userId] is usable for customer/barber APIs.
  static Future<bool> applySupabaseSession(Session session) async {
    while (_applyLock != null) {
      await _applyLock;
    }
    final gate = Completer<void>();
    _applyLock = gate.future;
    try {
      return await _applySupabaseSessionBody(session);
    } finally {
      gate.complete();
      _applyLock = null;
    }
  }

  static Future<bool> _applySupabaseSessionBody(Session session) async {
    final user = session.user;
    final metadata = user.userMetadata ?? <String, dynamic>{};
    final appMetadata = user.appMetadata;
    final rawRole = '${appMetadata['role'] ?? metadata['role']}'.trim();
    final role = rawRole.isEmpty || rawRole == 'null' ? null : rawRole;
    final fullNameValue = metadata['full_name'];
    final nameValue = metadata['name'];
    final resolvedFullName = fullNameValue != null &&
            fullNameValue.toString().trim().isNotEmpty
        ? fullNameValue.toString().trim()
        : nameValue != null && nameValue.toString().trim().isNotEmpty
            ? nameValue.toString().trim()
            : (user.email ?? '');

    UserSession.fullName = resolvedFullName;
    UserSession.email = user.email;
    if (UserSession.roles.isEmpty) {
      UserSession.roles = role != null && role.isNotEmpty
          ? [role.toLowerCase()]
          : ['customer'];
    }

    final email = (user.email ?? '').trim();
    await _resolveAccountFromServer(user, fallbackFullName: resolvedFullName);

    if (UserSession.userId == null || UserSession.userId! <= 0) {
      await _syncCustomerProfile(email, resolvedFullName);
      await _resolveAccountFromServer(user, fallbackFullName: resolvedFullName);
    }

    return (UserSession.userId ?? 0) > 0;
  }

  static void navigateToSignedInHome({bool showSnackBar = false}) {
    if (flow.state.recoveryActive &&
        hasVerifiedRecoverySession &&
        !flow.state.signedOutIdle) {
      _goToRecoveryPassword();
      return;
    }

    if ((UserSession.userId ?? 0) <= 0) {
      debugPrint('[AuthBootstrap] Refusing dashboard without userId.');
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingNavigation = () => navigateToSignedInHome(showSnackBar: showSnackBar);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingNavigation?.call();
      });
      return;
    }

    flow.markNavigatedToDashboard();
    _pendingNavigation = null;

    Widget destination;
    if (UserSession.roles.contains('admin') ||
        UserSession.roles.contains('receptionist')) {
      destination = const StaffWebPortalPage();
    } else if (UserSession.roles.contains('barber')) {
      destination = const BarberDashboardPage();
    } else {
      destination = const DashboardPage();
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );

    if (showSnackBar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context == null) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in successfully')),
        );
      });
    }
  }

  static void _queueDestination(AuthDestination destination) {
    if (destination == AuthDestination.changePassword) {
      _pendingNavigation = _goToRecoveryPassword;
      _goToRecoveryPassword();
      return;
    }
    if (destination == AuthDestination.dashboard) {
      _pendingNavigation = () => navigateToSignedInHome();
      navigateToSignedInHome();
    }
  }

  static void _goToRecoveryPassword() {
    if (!hasVerifiedRecoverySession) {
      _authLog(
        'refusing Change Password: no verified recovery session '
        'boundEmail=$_recoveryBoundEmail '
        'current=${Supabase.instance.client.auth.currentUser?.email}',
      );
      return;
    }
    if (flow.state.onRecoveryRoute) {
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingNavigation = _goToRecoveryPassword;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingNavigation?.call();
      });
      return;
    }

    flow.markNavigatedToRecovery();
    _pendingNavigation = null;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
      (route) => false,
    );
  }

  static void flushPendingNavigation() {
    final pending = _pendingNavigation;
    if (pending == null) {
      return;
    }
    pending();
  }

  static bool _uriLooksLikeRecovery(Uri uri) {
    return AuthFlowEngine.uriLooksLikeRecovery(
      query: uri.queryParameters,
      fragment: _readAuthCallbackParameters(uri),
    );
  }

  static Map<String, String> _readAuthCallbackParameters(Uri uri) {
    final fragment = uri.fragment;
    if (fragment.isEmpty) {
      return const <String, String>{};
    }
    final normalizedFragment =
        fragment.startsWith('?') ? fragment.substring(1) : fragment;
    if (normalizedFragment.isEmpty) {
      return const <String, String>{};
    }
    try {
      return Uri.splitQueryString(normalizedFragment);
    } catch (_) {
      return const <String, String>{};
    }
  }

  static Uri _normalizeAuthCallbackUri(Uri uri) {
    final fragmentParameters = _readAuthCallbackParameters(uri);
    if (fragmentParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      fragment: '',
      queryParameters: {
        ...uri.queryParameters,
        ...fragmentParameters,
      },
    );
  }

  static Future<void> _resolveAccountFromServer(
    User user, {
    required String fallbackFullName,
  }) async {
    final email = (user.email ?? '').trim();
    if (email.isEmpty) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'resolveAccount',
          'email': email,
          'fullName': fallbackFullName,
        }),
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 404) {
          await _syncCustomerProfile(email, fallbackFullName);
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final account = data['user'] as Map<String, dynamic>?;
      if (account == null) {
        return;
      }

      final resolvedUserId = account['userID'] is int
          ? account['userID'] as int
          : int.tryParse('${account['userID']}');
      if (resolvedUserId != null && resolvedUserId > 0) {
        UserSession.userId = resolvedUserId;
      }

      final mappedFullName = account['fullName']?.toString().trim();
      if (mappedFullName != null && mappedFullName.isNotEmpty) {
        UserSession.fullName = mappedFullName;
      }

      final resolvedRoles =
          (account['roles'] as List<dynamic>? ?? const ['authenticated'])
              .map((roleValue) => roleValue.toString().toLowerCase())
              .toList();
      if (resolvedRoles.isNotEmpty) {
        UserSession.roles = resolvedRoles;
      } else {
        UserSession.roles = ['customer'];
      }
    } catch (_) {}
  }

  static Future<void> _syncCustomerProfile(String email, String fullName) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/auth_sync.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': normalizedEmail,
          'full_name': fullName.trim().isNotEmpty
              ? fullName.trim()
              : normalizedEmail.split('@').first,
        }),
      );

      if (response.statusCode != 200 || response.body.isEmpty) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final syncedUserId = data['user_id'];
      final parsedId = syncedUserId is int
          ? syncedUserId
          : int.tryParse('$syncedUserId');
      if (parsedId != null && parsedId > 0) {
        UserSession.userId = parsedId;
        if (UserSession.roles.isEmpty) {
          UserSession.roles = ['customer'];
        }
      }
    } catch (_) {}
  }
}

class _AuthLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AuthBootstrap.flushPendingNavigation();
    }
  }
}
