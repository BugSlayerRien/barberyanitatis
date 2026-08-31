import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigator.dart';
import '../barber/barber_dashboard_page.dart';
import 'api_config.dart';
import 'auth_flow_state.dart';
import 'auth_intent_store.dart';
import 'dashboard_page.dart';
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

  static Future<void> markRecoveryRequested() async {
    flow.markRecoveryRequested();
    await AuthIntentStore.markRecoveryRequested();
  }

  static void markExpectingOAuth() {
    flow.markExpectingOAuth();
  }

  static void markPasswordLogin() {
    flow.markPasswordLogin();
  }

  static Future<void> onSignedOut() async {
    flow.markSignedOut();
    _pendingNavigation = null;
    _lastProcessedAuthCallbackUri = null;
    _handlingAuthCallback = false;
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

    AuthArrival arrival = AuthArrival.none;
    if (data.event == AuthChangeEvent.passwordRecovery) {
      arrival = AuthArrival.recoveryCallback;
      flow.markRecoveryActive();
    } else if (flow.state.expectingOAuth) {
      arrival = AuthArrival.oauthCallback;
    } else if (flow.state.recoveryPending ||
        sessionLooksLikePasswordRecovery(session)) {
      arrival = AuthArrival.recoveryCallback;
      flow.markRecoveryActive();
    }

    final destination = flow.decide(
      event: eventName,
      arrival: arrival,
      sessionIsRecovery: sessionLooksLikePasswordRecovery(session),
      redirectTypeRecovery: false,
      hasSession: true,
      hasUserId: (UserSession.userId ?? 0) > 0,
    );

    if (destination == AuthDestination.stay) {
      return;
    }

    final ready = await applySupabaseSession(session);
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

    final recovery = flow.state.recoveryPending ||
        sessionLooksLikePasswordRecovery(session);
    final ready = await applySupabaseSession(session);
    final destination = flow.decide(
      event: 'signedIn',
      arrival: recovery
          ? AuthArrival.recoveryCallback
          : AuthArrival.splashRestore,
      sessionIsRecovery: sessionLooksLikePasswordRecovery(session),
      redirectTypeRecovery: false,
      hasSession: true,
      hasUserId: ready,
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

    final uriKey = uri.toString();
    if (_lastProcessedAuthCallbackUri == uriKey &&
        (flow.state.didNavigate || flow.state.onRecoveryRoute)) {
      return true;
    }
    _lastProcessedAuthCallbackUri = uriKey;
    _handlingAuthCallback = true;

    try {
      final uriRecovery = _uriLooksLikeRecovery(uri);
      var redirectTypeRecovery = false;

      Session? session;
      final hasCode = uri.queryParameters.containsKey('code') ||
          _readAuthCallbackParameters(uri).containsKey('code');

      if (hasCode || uriRecovery) {
        try {
          final response = await Supabase.instance.client.auth.getSessionFromUrl(
            _normalizeAuthCallbackUri(uri),
          );
          session = response.session;
          if (response.redirectType == 'recovery') {
            redirectTypeRecovery = true;
          }
        } catch (e) {
          debugPrint('[AuthBootstrap] getSessionFromUrl failed: $e');
        }
      }

      session ??= await _recoverSessionFromFragment(uri);
      session ??= Supabase.instance.client.auth.currentSession;

      if (session == null) {
        debugPrint('[AuthBootstrap] No session recovered from auth callback.');
        _lastProcessedAuthCallbackUri = null;
        return false;
      }

      final recovery = uriRecovery ||
          redirectTypeRecovery ||
          sessionLooksLikePasswordRecovery(session) ||
          (flow.state.recoveryPending && !flow.state.expectingOAuth);

      if (recovery) {
        flow.markRecoveryActive();
      } else {
        flow.markExpectingOAuth();
      }

      final ready = await applySupabaseSession(session);
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
        sessionIsRecovery: sessionLooksLikePasswordRecovery(session),
        redirectTypeRecovery: redirectTypeRecovery,
        hasSession: true,
        hasUserId: ready,
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
      debugPrint('[AuthBootstrap] OAuth callback failed: $e\n$stack');
      _lastProcessedAuthCallbackUri = null;
      return false;
    } finally {
      _handlingAuthCallback = false;
    }
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
    if (flow.state.recoveryActive && !flow.state.signedOutIdle) {
      if (flow.decide(
            event: 'passwordRecovery',
            arrival: AuthArrival.recoveryCallback,
            sessionIsRecovery: true,
            redirectTypeRecovery: true,
            hasSession: true,
            hasUserId: true,
          ) ==
          AuthDestination.changePassword) {
        _goToRecoveryPassword();
        return;
      }
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
