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
import 'dashboard_page.dart';
import 'reset_password_page.dart';
import 'staff_web_portal_page.dart';
import 'user_session.dart';
import 'web_utils.dart';

/// Central OAuth/session handling so redirects work before [AuthPage] mounts.
class AuthBootstrap {
  AuthBootstrap._();

  static bool _didNavigateAfterSignIn = false;
  static String? _lastProcessedAuthCallbackUri;
  static StreamSubscription<AuthState>? _authSubscription;
  static StreamSubscription<Uri>? _oauthDeepLinkSubscription;

  static bool get didNavigateAfterSignIn => _didNavigateAfterSignIn;

  static void resetNavigationLock() {
    _didNavigateAfterSignIn = false;
    _lastProcessedAuthCallbackUri = null;
  }

  /// Applies session from PHP auth.php (staff, barber, receptionist, legacy customer).
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
    resetNavigationLock();
  }

  static Future<void> initialize() async {
    await _authSubscription?.cancel();
    await _oauthDeepLinkSubscription?.cancel();

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final session = data.session;
      if (session == null) {
        return;
      }

      if (data.event == AuthChangeEvent.passwordRecovery) {
        await applySupabaseSession(session);
        _scheduleNavigation(() => _navigateToResetPassword());
        return;
      }

      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.tokenRefreshed) {
        await applySupabaseSession(session);
        if (data.event != AuthChangeEvent.tokenRefreshed) {
          _scheduleNavigation(() => navigateToSignedInHome());
        }
      } else if (data.event == AuthChangeEvent.signedOut) {
        await UserSession.clear();
        resetNavigationLock();
      }
    });

    final appLinks = AppLinks();
    _oauthDeepLinkSubscription = appLinks.uriLinkStream.listen(
      (uri) => unawaited(handleAuthCallbackUri(uri)),
      onError: (_) {},
    );

    if (kIsWeb) {
      await handleAuthCallbackUri(Uri.base);
    } else {
      final initialLink = await appLinks.getInitialAppLink();
      if (initialLink != null) {
        await handleAuthCallbackUri(initialLink);
      }
    }
  }

  /// Returns true when navigation to a signed-in screen already happened.
  static Future<bool> restoreSessionOnColdStart() async {
    if (_didNavigateAfterSignIn) {
      return true;
    }

    if (kIsWeb && isSupabaseAuthCallbackUri(Uri.base)) {
      final handled = await handleAuthCallbackUri(Uri.base);
      if (handled || _didNavigateAfterSignIn) {
        return true;
      }
    }

    if (!kIsWeb) {
      final initialLink = await AppLinks().getInitialAppLink();
      if (initialLink != null) {
        final handled = await handleAuthCallbackUri(initialLink);
        if (handled || _didNavigateAfterSignIn) {
          return true;
        }
      }
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await applySupabaseSession(session);
      navigateToSignedInHome();
      return true;
    }

    return _didNavigateAfterSignIn;
  }

  static bool isSupabaseAuthCallbackUri(Uri uri) {
    if (uri.scheme == 'io.supabase.flutter' && uri.host == 'login-callback') {
      return true;
    }

    // Native OAuth must return via the custom scheme. Do not treat arbitrary
    // https pages that happen to contain `?code=` (Google intermediate, HTML
    // error pages) as a PKCE callback — exchanging those yields HTML/JSON errors.
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
    if (_lastProcessedAuthCallbackUri == uriKey) {
      return _didNavigateAfterSignIn;
    }
    _lastProcessedAuthCallbackUri = uriKey;

    try {
      final currentSession = Supabase.instance.client.auth.currentSession;
      if (currentSession != null) {
        await applySupabaseSession(currentSession);
        _scheduleNavigation(() => navigateToSignedInHome());
        return true;
      }

      final normalizedUri = _normalizeAuthCallbackUri(uri);
      Session? session;

      try {
        final response = await Supabase.instance.client.auth.getSessionFromUrl(
          normalizedUri,
        );
        session = response.session;
      } catch (e) {
        debugPrint('[AuthBootstrap] getSessionFromUrl failed: $e');
      }

      session ??= await _recoverSessionFromFragment(uri);

      if (session == null) {
        debugPrint('[AuthBootstrap] No session recovered from OAuth callback.');
        _lastProcessedAuthCallbackUri = null;
        return false;
      }

      await applySupabaseSession(session);
      if (kIsWeb) {
        try {
          clearUrlFragment();
        } catch (_) {}
      }

      _scheduleNavigation(() => navigateToSignedInHome());
      return true;
    } catch (e, stack) {
      debugPrint('[AuthBootstrap] OAuth callback failed: $e\n$stack');
      _lastProcessedAuthCallbackUri = null;
      return false;
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

  static Future<void> applySupabaseSession(Session session) async {
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

    UserSession.userId = null;
    UserSession.fullName = resolvedFullName;
    UserSession.email = user.email;
    UserSession.roles = role != null && role.isNotEmpty
        ? [role.toLowerCase()]
        : ['customer'];

    final email = (user.email ?? '').trim();
    await _resolveAccountFromServer(user, fallbackFullName: resolvedFullName);

    if (UserSession.userId == null || UserSession.userId! <= 0) {
      await _syncCustomerProfile(email, resolvedFullName);
      await _resolveAccountFromServer(user, fallbackFullName: resolvedFullName);
    }
  }

  static void navigateToSignedInHome({bool showSnackBar = false}) {
    if (_didNavigateAfterSignIn) {
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _scheduleNavigation(() => navigateToSignedInHome(showSnackBar: showSnackBar));
      return;
    }

    _didNavigateAfterSignIn = true;

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

  static void _navigateToResetPassword() {
    if (_didNavigateAfterSignIn) {
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _scheduleNavigation(_navigateToResetPassword);
      return;
    }

    _didNavigateAfterSignIn = true;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
      (route) => false,
    );
  }

  static void _scheduleNavigation(VoidCallback navigate) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigate();
      if (!_didNavigateAfterSignIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_didNavigateAfterSignIn) {
            navigate();
          }
        });
      }
    });
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

      final resolvedRoles = (account['roles'] as List<dynamic>? ?? const ['authenticated'])
          .map((roleValue) => roleValue.toString().toLowerCase())
          .toList();
      if (resolvedRoles.isNotEmpty) {
        UserSession.roles = resolvedRoles;
      } else {
        UserSession.roles = ['customer'];
      }
    } catch (_) {
      // Keep fallback session values when account resolution is unavailable.
    }
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
          'full_name': fullName.trim().isNotEmpty ? fullName.trim() : normalizedEmail.split('@').first,
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
    } catch (_) {
      // Best effort only.
    }
  }
}
