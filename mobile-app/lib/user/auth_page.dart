import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'forgot_password_page.dart';
import 'api_config.dart';
import 'app_brand.dart';
import 'auth_bootstrap.dart';
import 'auth_redirect.dart';
import 'auth_user_messages.dart';
import 'supabase_password_identity.dart';
import 'user_session.dart';

const Color kGoldColor = AppBrand.gold;
const String kGoogleLogoAsset = 'assets/images/google_logo.png';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  String get _apiBaseUrl => ApiConfig.baseUrl;
  static const String _googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');

  bool _isLogin = true;
  bool _isLoading = false;
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
  final FocusNode _regPassFocus = FocusNode();

  bool _obscureLogin = true;
  bool _obscureReg1 = true;
  bool _obscureReg2 = true;
  bool _passwordFieldFocused = false;

  static final RegExp _passwordUpper = RegExp(r'[A-Z]');
  static final RegExp _passwordLower = RegExp(r'[a-z]');
  static final RegExp _passwordDigit = RegExp(r'\d');
  static final RegExp _passwordSpecial =
      RegExp(r'[!@#$%^&*()_+\-=\[\]{};:,.<>?]');

  @override
  void initState() {
    super.initState();
    _regPass.addListener(_onRegisterPasswordFieldsChanged);
    _confirm.addListener(_onRegisterPasswordFieldsChanged);
    _regPassFocus.addListener(_onRegPassFocusChanged);
  }

  void _onRegisterPasswordFieldsChanged() {
    if (mounted) setState(() {});
  }

  void _onRegPassFocusChanged() {
    if (!mounted) return;
    setState(() => _passwordFieldFocused = _regPassFocus.hasFocus);
  }

  @override
  void dispose() {
    _regPass.removeListener(_onRegisterPasswordFieldsChanged);
    _confirm.removeListener(_onRegisterPasswordFieldsChanged);
    _regPassFocus.removeListener(_onRegPassFocusChanged);
    _regPassFocus.dispose();
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

  Map<String, dynamic> _tryDecodeJsonMap(String body) {
    final raw = body.trim();
    if (raw.isEmpty || raw.startsWith('<')) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // HTML/proxy bodies must not abort customer Supabase login.
    }
    return const <String, dynamic>{};
  }

  /// Web staff keep PHP sessions. Returns true when login is finished.
  /// Customers and barbers always continue to Supabase Auth for the JWT.
  Future<bool> _completePhpStaffLoginIfPossible(
    String email,
    String password,
  ) async {
    late final http.Response phpLogin;
    try {
      phpLogin = await http
          .post(
            Uri.parse('$_apiBaseUrl/auth.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'action': 'login',
              'client': 'mobile',
              'email': email,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return false;
    } on http.ClientException {
      return false;
    }

    final phpData = _tryDecodeJsonMap(phpLogin.body);

    if (phpLogin.statusCode == 200) {
      final phpUser = phpData['user'] as Map<String, dynamic>?;
      if (phpUser != null) {
        final roles = (phpUser['roles'] as List<dynamic>? ?? const [])
            .map((role) => role.toString().toLowerCase())
            .toList();
        final isWebStaff = roles.any(
          (role) =>
              role == 'admin' ||
              role == 'receptionist' ||
              role == 'staff',
        );
        if (isWebStaff) {
          AuthBootstrap.applyPhpAuthUser(phpUser);
          if (!mounted) return true;
          AuthBootstrap.navigateToSignedInHome(showSnackBar: true);
          return true;
        }
      }
      return false;
    }

    if (phpLogin.statusCode == 401) {
      final code = phpData['code']?.toString() ?? '';
      final accountType = phpData['accountType']?.toString() ?? '';
      final message =
          phpData['error']?.toString() ?? 'Invalid email or password.';
      if (accountType == 'staff' &&
          (code == 'NO_LOCAL_PASSWORD' ||
              code == 'WRONG_PASSWORD' ||
              code == 'OAUTH_ONLY')) {
        throw Exception(message);
      }
    }

    return false;
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
      // Web staff stay on PHP. Customers and barbers use Supabase Auth.
      if (await _completePhpStaffLoginIfPossible(email, password)) {
        return;
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final session = response.session;
      if (session == null) {
        throw Exception('Login succeeded but no Supabase session was returned.');
      }

      await AuthBootstrap.applySupabaseSession(session);
      await confirmEmailPasswordCredential();
      if (!mounted) return;
      AuthBootstrap.markPasswordLogin();
      AuthBootstrap.navigateToSignedInHome(showSnackBar: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(await _readableLoginError(e, email: email))),
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
    final fullName = '$firstName $lastName'.trim();

    // Validation 1: Required fields
    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all required fields.')),
      );
      return;
    }

    // Validation 2: Email format
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address (e.g., yourname@example.com).')),
      );
      return;
    }

    // Validation 3: Duplicate email in app tables and Supabase Auth
    try {
      final lookup = await _lookupEmail(email);
      if (lookup['exists'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_duplicateSignupMessage(lookup))),
        );
        return;
      }
    } catch (_) {
      // Lookup failed; signUp still rejects existing Auth users.
    }

    // Validation 4: Password strength
    final passwordError = _getPasswordValidationError(password);
    if (passwordError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordError)),
      );
      return;
    }

    // Validation 5: Passwords match
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    // Validation 6: Phone number (if provided)
    if (phone.isNotEmpty && !_isValidPhone(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Philippine phone number (e.g., 09123456789).')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Sign up with email confirmation enabled (auto-confirm for dev)
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'phone': phone,
        },
        emailRedirectTo: AuthRedirect.supabaseRedirectUri,
      );

      if (!mounted) return;

      final session = response.session;
      if (session != null) {
        // Signup succeeded and user is signed in
        await AuthBootstrap.applySupabaseSession(session);
        await confirmEmailPasswordCredential();
        AuthBootstrap.markPasswordLogin();
        
        // Sync the new user to public.users table
        try {
          await http.post(
            Uri.parse('$_apiBaseUrl/auth_sync.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'full_name': fullName,
            }),
          );
        } catch (_) {
          // Sync failed but user is authenticated; continue anyway
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration successful. Welcome!')),
        );
        AuthBootstrap.navigateToSignedInHome(showSnackBar: true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Registration successful. You can now sign in.')),
      );
      setState(() => _isLogin = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authFriendlyError(e))),
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

      AuthBootstrap.navigateToSignedInHome(showSnackBar: false);
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
      // Stock SDK sign-in. signInWithOAuth forces LaunchMode.externalApplication
      // for Google on Android internally ("Google login has to be performed on
      // external browser window on Android"), and the SDK's own deep-link
      // observer completes the code exchange. Driving that exchange ourselves
      // is what broke repeat sign-ins with flow_state_not_found.
      //
      // markExpectingOAuth() must stay: it is what makes AuthBootstrap treat
      // the resulting signedIn event as AuthArrival.oauthCallback and route to
      // the dashboard. Without it the session is created but nothing navigates.
      AuthBootstrap.markExpectingOAuth();
      AuthRedirect.prepareWebOAuthReturn();
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AuthRedirect.supabaseRedirectUri,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Complete Google sign-in, then you will return to ${AuthRedirect.webAppReturnUri}',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening browser for Google sign-in...')),
        );
      }
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
      AuthBootstrap.markExpectingOAuth();
      AuthRedirect.prepareWebOAuthReturn();
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: AuthRedirect.supabaseRedirectUri,
        authScreenLaunchMode: LaunchMode.externalApplication,
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: AppBrand.background,
      resizeToAvoidBottomInset: true,
      body: Center(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandWordmark(logoHeight: 104),
                const SizedBox(height: 18),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: AppBrand.card,
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
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Forgot password?',
              style: TextStyle(color: AppBrand.gold, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: AppBrand.primaryButton,
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
          style: AppBrand.outlineButton,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _signInWithSupabaseFacebook,
          icon: const Icon(Icons.facebook, color: Colors.white, size: 20),
          label: const Text(
            'Continue with Facebook',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          style: AppBrand.outlineButton,
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
                  style: TextStyle(color: AppBrand.gold, fontSize: 12)),
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
          decoration: _fieldDecoration('Enter your email', helperText: 'Format: yourname@example.com'),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _phone,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Enter phone number', helperText: 'PH format: 09123456789 or 02-1234567'),
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextField(
            controller: _regPass,
            focusNode: _regPassFocus,
            obscureText: _obscureReg1,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Enter your password',
                suffix: IconButton(
                    icon: Icon(
                        _obscureReg1 ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70),
                    onPressed: () =>
                        setState(() => _obscureReg1 = !_obscureReg1)))),
        if (_shouldShowPasswordRequirements) ...[
          const SizedBox(height: 8),
          _buildPasswordRequirementsChecklist(_regPass.text),
        ],
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
        if (_showConfirmMismatchMessage) ...[
          const SizedBox(height: 6),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Passwords do not match.',
              style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: (_isLoading || !_canSubmitRegisterPassword)
              ? null
              : _register,
          style: AppBrand.primaryButton,
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
                  style: TextStyle(color: AppBrand.gold, fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hint, {Widget? suffix, String? helperText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      helperText: helperText,
      helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
      filled: true,
      fillColor: AppBrand.surfaceAlt,
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppBrand.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppBrand.goldLine)),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppBrand.border)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      suffixIcon: suffix,
    );
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool _isValidPhone(String phone) {
    // Accept Philippine phone numbers
    // Formats: 09123456789 (11 digits), 02-1234567 (8-10 digits), +63912345678
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    
    // PH mobile: 09xxxxxxxxx (11 digits) or 639xxxxxxxxx (international, 12 digits)
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return true;
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return true;
    }

    // PH landline: 0X-xxxxxxx to 0XX-xxxxx (area codes 02-08, 8-10 total digits)
    // Valid: 02-1234567 (9 digits), 032-123456 (9 digits), etc.
    if ((cleaned.startsWith('02') || cleaned.startsWith('03') ||
         cleaned.startsWith('04') || cleaned.startsWith('05') ||
         cleaned.startsWith('06') || cleaned.startsWith('07') ||
         cleaned.startsWith('08')) &&
        cleaned.length >= 8 && cleaned.length <= 10) {
      return true;
    }

    return false;
  }

  bool get _shouldShowPasswordRequirements =>
      _passwordFieldFocused || _regPass.text.isNotEmpty;

  bool get _showConfirmMismatchMessage =>
      _confirm.text.isNotEmpty && _regPass.text != _confirm.text;

  bool get _canSubmitRegisterPassword {
    final password = _regPass.text;
    return _isPasswordValid(password) &&
        _confirm.text.isNotEmpty &&
        password == _confirm.text;
  }

  Map<String, bool> _passwordRequirementStates(String password) {
    return {
      'At least 8 characters': password.length >= 8,
      'One uppercase letter': _passwordUpper.hasMatch(password),
      'One lowercase letter': _passwordLower.hasMatch(password),
      'One number': _passwordDigit.hasMatch(password),
      'One special character': _passwordSpecial.hasMatch(password),
    };
  }

  bool _isPasswordValid(String password) {
    final states = _passwordRequirementStates(password);
    return states.values.every((met) => met);
  }

  Widget _buildPasswordRequirementsChecklist(String password) {
    final states = _passwordRequirementStates(password);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in states.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                children: [
                  Icon(
                    entry.value ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: entry.value
                        ? const Color(0xFF81C784)
                        : Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: entry.value ? Colors.white70 : Colors.white38,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _getPasswordValidationError(String password) {
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!_passwordUpper.hasMatch(password)) {
      return 'Password must contain at least one uppercase letter (A-Z).';
    }
    if (!_passwordLower.hasMatch(password)) {
      return 'Password must contain at least one lowercase letter (a-z).';
    }
    if (!_passwordDigit.hasMatch(password)) {
      return 'Password must contain at least one number (0-9).';
    }
    if (!_passwordSpecial.hasMatch(password)) {
      return 'Password must contain at least one special character (!@#\$%^&*).';
    }
    return null;
  }

  Future<Map<String, dynamic>> _lookupEmail(String email) async {
    final response = await http
        .post(
          Uri.parse('$_apiBaseUrl/auth.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'checkEmailExists',
            'email': email,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      return const <String, dynamic>{};
    }
    return _tryDecodeJsonMap(response.body);
  }

  String _duplicateSignupMessage(Map<String, dynamic> lookup) {
    if (lookup['oauthOnly'] == true) {
      final providers = (lookup['providers'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList();
      return authOauthOnlySignInMessage(providers);
    }
    return 'This email is already registered. Try signing in instead.';
  }

  Future<String> _readableLoginError(Object error, {required String email}) async {
    final raw = error.toString().replaceFirst('Exception:', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('over_email_send_rate_limit') ||
        lower.contains('rate limit') ||
        lower.contains('429')) {
      return authFriendlyError(error);
    }
    if (authLooksLikeInvalidCredentials(error)) {
      try {
        final lookup = await _lookupEmail(email);
        if (lookup['oauthOnly'] == true) {
          final providers = (lookup['providers'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList();
          return authOauthOnlySignInMessage(providers);
        }
      } catch (_) {}
      if (email.endsWith('@tatis.local')) {
        return '@tatis.local staff accounts log in via the API (auth.php). '
            'Customer and barber demo emails must exist in Supabase Auth. '
            'Web staff demo: receptionist@tatis.local / Reception123!, '
            'admin@tatis.local / Admin123!.';
      }
      return 'Invalid email or password. If you registered with Google or Facebook, use those buttons. If you registered with email, confirm your email first or reset your password.';
    }
    if (lower.contains('failed to fetch') || lower.contains('network')) {
      return 'Cannot reach the auth server. Check your internet connection and API URL.';
    }
    return 'Login failed: $raw';
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
