import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../receptionist/receptionist_dashboard_page.dart';
import '../admins/admin_dashboard_page.dart';
import '../barber/barber_dashboard_page.dart';
import 'forgot_password_page.dart';
import 'reset_password_page.dart';
import 'dashboard_page.dart';
import 'api_config.dart';
import 'user_session.dart';
import 'web_utils.dart';

// Local copy of the white color used in the app to avoid circular imports
const Color kGoldColor = Colors.white;
const String kGoogleLogoAsset = 'assets/images/google_logo.png';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final String _apiBaseUrl = ApiConfig.baseUrl;
  static const String _supabaseRedirectUri =
      'io.supabase.flutter://login-callback';
  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  bool _isLogin = true;
  bool _isLoading = false;
  bool _didNavigateAfterSignIn = false;
  String? _lastProcessedAuthCallbackUri;
  // Login controllers
  final TextEditingController _loginUser = TextEditingController();
  final TextEditingController _loginPass = TextEditingController();

  // Register controllers
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _regEmail = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _regPass = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscureLogin = true;
  bool _obscureReg1 = true;
  bool _obscureReg2 = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _bootstrapAuthListeners();
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    _authStateSubscription?.cancel();
    _loginUser.dispose();
    _loginPass.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _regEmail.dispose();
    _phone.dispose();
    _regPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _bootstrapAuthListeners() async {
    _authStateSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        _applySupabaseSession(data.session!);
        _goToSignedInDestination();
      } else if (data.event == AuthChangeEvent.passwordRecovery &&
          data.session != null) {
        _applySupabaseSession(data.session!);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
        );
      } else if (data.event == AuthChangeEvent.signedOut) {
        await UserSession.clear();
        _didNavigateAfterSignIn = false;
        _lastProcessedAuthCallbackUri = null;
      }
    });

    _deepLinkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async => _handleAuthCallbackUri(uri),
      onError: (Object error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deep link error: $error')),
        );
      },
    );

    try {
      if (kIsWeb) {
        await _handleAuthCallbackUri(Uri.base);
      } else {
        final initialLink = await _appLinks.getInitialAppLink();
        if (initialLink != null) {
          await _handleAuthCallbackUri(initialLink);
        }
      }

      final existingSession = Supabase.instance.client.auth.currentSession;
      if (existingSession != null) {
        _applySupabaseSession(existingSession);
        _goToSignedInDestination();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to inspect auth callback: $error')),
      );
    }
  }

  bool _isSupabaseAuthCallbackUri(Uri uri) {
    if (uri.scheme == 'io.supabase.flutter' && uri.host == 'login-callback') {
      return true;
    }

    final fragmentParameters = _readAuthCallbackParameters(uri);
    final hasOAuthFragment = fragmentParameters.containsKey('access_token') ||
        fragmentParameters.containsKey('refresh_token') ||
        fragmentParameters.containsKey('error') ||
        fragmentParameters.containsKey('error_description');
    final hasOAuthQuery = uri.queryParameters.containsKey('code');
    return hasOAuthFragment || hasOAuthQuery;
  }

  Future<void> _handleAuthCallbackUri(Uri uri) async {
    if (!_isSupabaseAuthCallbackUri(uri)) {
      return;
    }

    final uriKey = uri.toString();
    if (_lastProcessedAuthCallbackUri == uriKey) {
      return;
    }
    _lastProcessedAuthCallbackUri = uriKey;

    try {
      final currentSession = Supabase.instance.client.auth.currentSession;
      if (currentSession != null) {
        _applySupabaseSession(currentSession);
        _goToSignedInDestination();
        return;
      }

      final normalizedUri = _normalizeAuthCallbackUri(uri);
      final response = await Supabase.instance.client.auth.getSessionFromUrl(
        normalizedUri,
      );
      _applySupabaseSession(response.session);
      if (kIsWeb) {
        try {
          clearUrlFragment();
        } catch (_) {}
      }
      _goToSignedInDestination();
      return;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Supabase callback failed: $error')),
      );
      _lastProcessedAuthCallbackUri = null;
    }
  }

  Map<String, String> _readAuthCallbackParameters(Uri uri) {
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

  Uri _normalizeAuthCallbackUri(Uri uri) {
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

  String _webOAuthRedirectTo() {
    return Uri.base.origin;
  }

  void _applySupabaseSession(Session session) {
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
        : user.email;

    UserSession.userId = user.id.hashCode.abs();
    UserSession.fullName = resolvedFullName;
    UserSession.email = user.email;
    UserSession.roles = role != null && role.isNotEmpty
        ? [role.toLowerCase()]
        : ['authenticated'];
  }

  void _goToSignedInDestination() {
    if (!mounted) {
      return;
    }

    if (_didNavigateAfterSignIn) {
      return;
    }
    _didNavigateAfterSignIn = true;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Signed in successfully')));

    if (UserSession.roles.contains('admin')) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
    } else if (UserSession.roles.contains('receptionist')) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => const ReceptionistDashboardPage()));
    } else if (UserSession.roles.contains('barber')) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BarberDashboardPage()));
    } else {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardPage()));
    }
  }

  Future<void> _login() async {
    final email = _loginUser.text.trim();
    final password = _loginPass.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/auth.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'login',
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Login failed.')),
        );
        return;
      }

      final user = data['user'] as Map<String, dynamic>? ?? {};
      final roles = (user['roles'] as List<dynamic>? ?? [])
          .map((role) => role.toString().toLowerCase())
          .toList();

      UserSession.userId = user['userID'] is int
          ? user['userID'] as int
          : int.tryParse('${user['userID']}');
      UserSession.fullName = user['fullName']?.toString();
      UserSession.email = user['email']?.toString();
      UserSession.roles = roles;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Login successful')));

      if (roles.contains('admin')) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
      } else if (roles.contains('receptionist')) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ReceptionistDashboardPage()));
      } else if (roles.contains('barber')) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BarberDashboardPage()));
      } else {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DashboardPage()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _register() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    final email = _regEmail.text.trim();
    final phone = _phone.text.trim();
    final password = _regPass.text;
    final confirm = _confirm.text;

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      return;
    }

    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password must be at least 6 characters.')),
      );
      return;
    }

    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number.')),
      );
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': '$firstName $lastName',
          'phone': phone,
        },
        emailRedirectTo: kIsWeb ? _webOAuthRedirectTo() : _supabaseRedirectUri,
      );

      if (!mounted) return;

      final session = response.session;
      if (session != null) {
        _applySupabaseSession(session);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful.')),
        );
        _goToSignedInDestination();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Registration successful. Check your email to confirm your account.')),
      );
      setState(() => _isLogin = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId:
            _googleServerClientId.isNotEmpty ? _googleServerClientId : null,
      );
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken?.trim() ?? '';
      final accessToken = googleAuth.accessToken?.trim() ?? '';
      final hasAnyToken = idToken.isNotEmpty || accessToken.isNotEmpty;
      if (!hasAnyToken) {
        throw Exception(
            'Google tokens are missing. Configure Android/iOS OAuth and GOOGLE_SERVER_CLIENT_ID.');
      }

      final response = await http.post(
        Uri.parse('$_apiBaseUrl/auth.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'googleLogin',
          'email': googleUser.email,
          'fullName': googleUser.displayName,
          'idToken': idToken,
          'accessToken': accessToken,
          'googleUid': googleUser.id,
          'photoUrl': googleUser.photoUrl,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        final message = data['error']?.toString() ??
            data['message']?.toString() ??
            'Google sign-in backend rejected the request (${response.statusCode}).';
        throw Exception(message);
      }

      final user = data['user'] as Map<String, dynamic>? ?? {};
      final roles = (user['roles'] as List<dynamic>? ?? ['customer'])
          .map((role) => role.toString().toLowerCase())
          .toList();

      UserSession.userId = user['userID'] is int
          ? user['userID'] as int
          : int.tryParse('${user['userID']}') ?? googleUser.id.hashCode.abs();
      UserSession.fullName =
          user['fullName']?.toString() ?? googleUser.displayName;
      UserSession.email = user['email']?.toString() ?? googleUser.email;
      UserSession.roles = roles;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in successful')));

      if (UserSession.roles.contains('admin')) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
      } else if (UserSession.roles.contains('receptionist')) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ReceptionistDashboardPage()));
      } else if (UserSession.roles.contains('barber')) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BarberDashboardPage()));
      } else {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const DashboardPage()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableGoogleSignInError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithSupabaseGoogle() async {
    setState(() => _isLoading = true);
    try {
      // Launch supabase OAuth flow (will open browser and redirect to the custom scheme)
      await Supabase.instance.client.auth.signInWithOAuth(
        Provider.google,
        redirectTo: kIsWeb ? _webOAuthRedirectTo() : _supabaseRedirectUri,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening browser for Google sign-in...')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Supabase Google sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithSupabaseFacebook() async {
    setState(() => _isLoading = true);
    try {
      // On web: redirect back to the running app URL so callback tokens are captured.
      // On mobile: use the deep-link scheme for the OAuth callback.
      await Supabase.instance.client.auth.signInWithOAuth(
        Provider.facebook,
        redirectTo: kIsWeb ? _webOAuthRedirectTo() : _supabaseRedirectUri,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening browser for Facebook sign-in...')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Supabase Facebook sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo outside the card
                Image.asset('assets/images/TATIS.png', height: 96),
                const SizedBox(height: 12),
                const Text(
                  'BARBERYA NI TATIS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2),
                ),
                const SizedBox(height: 18),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Toggle buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _isLogin = true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    _isLogin ? kGoldColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('SIGN IN',
                                  style: TextStyle(
                                      color: _isLogin
                                          ? Colors.black
                                          : Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _isLogin = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    !_isLogin ? kGoldColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('SIGN UP',
                                  style: TextStyle(
                                      color: !_isLogin
                                          ? Colors.black
                                          : Colors.white)),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Animated switch between login and register
                      AnimatedCrossFade(
                        firstChild: _buildLogin(context),
                        secondChild: _buildRegister(context),
                        crossFadeState: _isLogin
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        duration: const Duration(milliseconds: 250),
                        firstCurve: Curves.easeInOut,
                        secondCurve: Curves.easeInOut,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogin(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Sign in to your account',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _loginUser,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPass,
          obscureText: _obscureLogin,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your password',
              suffix: IconButton(
                  icon: Icon(
                      _obscureLogin ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white70),
                  onPressed: () =>
                      setState(() => _obscureLogin = !_obscureLogin))),
        ),
        const SizedBox(height: 12),
        // Remember me and Forgot password
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (value) =>
                      setState(() => _rememberMe = value ?? false),
                  side: const BorderSide(color: Colors.white54),
                ),
                const Text('Remember me',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                );
              },
              child: const Text('Forgot password?',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48)),
          child: Text(_isLoading ? 'PLEASE WAIT...' : 'SIGN IN',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _signInWithSupabaseGoogle,
          icon: Image.asset(
            kGoogleLogoAsset,
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.account_circle, color: Colors.white),
          ),
          label: const Text(
            'Continue with Google',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            side: const BorderSide(color: Colors.white24),
            backgroundColor: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _signInWithSupabaseFacebook,
          icon: const Icon(Icons.facebook, color: Colors.white, size: 20),
          label: const Text(
            'Continue with Facebook',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            side: const BorderSide(color: Colors.white24),
            backgroundColor: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Don’t have an account? ',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton(
              onPressed: () => setState(() => _isLogin = false),
              child: const Text('Sign up',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegister(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Create your account',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: TextField(
                    controller: _firstName,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Enter first name'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: _lastName,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('Enter last name'))),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmail,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your email'),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _phone,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Enter phone number'),
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextField(
            controller: _regPass,
            obscureText: _obscureReg1,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Enter your password',
                suffix: IconButton(
                    icon: Icon(
                        _obscureReg1 ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70),
                    onPressed: () =>
                        setState(() => _obscureReg1 = !_obscureReg1)))),
        const SizedBox(height: 12),
        TextField(
            controller: _confirm,
            obscureText: _obscureReg2,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Confirm your password',
                suffix: IconButton(
                    icon: Icon(
                        _obscureReg2 ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70),
                    onPressed: () =>
                        setState(() => _obscureReg2 = !_obscureReg2)))),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isLoading ? null : _register,
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(48)),
          child: Text(_isLoading ? 'PLEASE WAIT...' : 'CREATE ACCOUNT',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Already have an account? ',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton(
              onPressed: () => setState(() => _isLogin = true),
              child: const Text('Sign in',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      suffixIcon: suffix,
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 7 && digits.length <= 15;
  }

  String _readableGoogleSignInError(Object error) {
    final raw = error.toString().replaceFirst('Exception:', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('popup_closed') || lower.contains('cancel')) {
      return 'Google sign-in was cancelled.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'Network issue during Google sign-in. Please check your connection.';
    }
    if (lower.contains('backend') || lower.contains('rejected')) {
      return raw;
    }
    return 'Google sign-in failed. $raw';
  }
}
