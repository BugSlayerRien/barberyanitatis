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
import 'signup_otp_page.dart';
import 'auth_user_messages.dart';
import 'supabase_password_identity.dart';
import 'user_session.dart';

// Field styling, button styling and the accent all come from AppBrand now —
// see lib/user/app_brand.dart for the Brilliante token set.
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

      // No session means Supabase requires email confirmation. Send the user to
      // the OTP screen instead of dumping them back on Sign In, where the
      // account would silently refuse to log in until they found the emailed
      // link. The same email carries a 6-digit code, which is faster and keeps
      // them inside the app.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignupOtpPage(email: email, fullName: fullName),
        ),
      );
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
      // Stock SDK initiation, as in 3e1976e where repeated Google sign-in
      // worked. signInWithOAuth generates the PKCE verifier, stores it, builds
      // the authorize URL and launches the browser in one step. The custom
      // getOAuthSignInUrl + manual launch path that replaced it is what this
      // restructure rolls back.
      //
      // markExpectingOAuth() must stay: it is what makes AuthBootstrap treat
      // the resulting signedIn event as AuthArrival.oauthCallback and route to
      // the dashboard.
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
                const SizedBox(height: AppBrand.s5),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                      AppBrand.s5, AppBrand.s4, AppBrand.s5, AppBrand.s5),
                  decoration: AppBrand.cardRaised,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AuthModeSwitch(
                        isLogin: _isLogin,
                        onChanged: (value) => setState(() => _isLogin = value),
                      ),

                      const SizedBox(height: AppBrand.s5),

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
        const _FieldLabel('Email'),
        TextField(
          controller: _loginUser,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          style: const TextStyle(color: AppBrand.text),
          decoration: AppBrand.field('you@example.com'),
        ),
        const SizedBox(height: AppBrand.s4),
        const _FieldLabel('Password'),
        TextField(
          controller: _loginPass,
          obscureText: _obscureLogin,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _isLoading ? null : _login(),
          style: const TextStyle(color: AppBrand.text),
          decoration: AppBrand.field('Enter your password',
              suffix: _RevealButton(
                obscured: _obscureLogin,
                onPressed: () =>
                    setState(() => _obscureLogin = !_obscureLogin),
              )),
        ),
        const SizedBox(height: AppBrand.s1),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
              );
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppBrand.s2, vertical: AppBrand.s2),
              minimumSize: const Size(0, 40),
              foregroundColor: AppBrand.accent,
            ),
            child: const Text(
              'Forgot password?',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: AppBrand.s3),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: AppBrand.primaryButton,
          child: _isLoading
              ? const _ButtonSpinner()
              : const Text('SIGN IN'),
        ),
        const SizedBox(height: AppBrand.s4),
        const _OrDivider(),
        const SizedBox(height: AppBrand.s3),
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
            style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w600),
          ),
          style: AppBrand.outlineButton,
        ),
        const SizedBox(height: AppBrand.s2),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _signInWithSupabaseFacebook,
          icon: const Icon(Icons.facebook, color: AppBrand.text, size: 20),
          label: const Text(
            'Continue with Facebook',
            style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w600),
          ),
          style: AppBrand.outlineButton,
        ),
        const SizedBox(height: AppBrand.s3),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Don’t have an account? ',
                style: TextStyle(color: AppBrand.textMuted, fontSize: 12.5)),
            TextButton(
              onPressed: () => setState(() => _isLogin = false),
              style: TextButton.styleFrom(
                foregroundColor: AppBrand.accent,
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Sign up',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegister(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('First name'),
                  TextField(
                      controller: _firstName,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.givenName],
                      style: const TextStyle(color: AppBrand.text),
                      decoration: AppBrand.field('Juan')),
                ],
              ),
            ),
            const SizedBox(width: AppBrand.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('Last name'),
                  TextField(
                      controller: _lastName,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.familyName],
                      style: const TextStyle(color: AppBrand.text),
                      decoration: AppBrand.field('Dela Cruz')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppBrand.s4),
        const _FieldLabel('Email'),
        TextField(
          controller: _regEmail,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(color: AppBrand.text),
          decoration: AppBrand.field('you@example.com',
              helperText: 'We send your booking confirmations here.'),
        ),
        // Phone is intentionally not collected at registration — it keeps
        // sign-up short and is not needed to create an account. Customers can
        // add or edit it any time under Profile → Mobile Number.
        const SizedBox(height: AppBrand.s4),
        const _FieldLabel('Password'),
        TextField(
            controller: _regPass,
            focusNode: _regPassFocus,
            obscureText: _obscureReg1,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(color: AppBrand.text),
            decoration: AppBrand.field('Create a password',
                suffix: _RevealButton(
                  obscured: _obscureReg1,
                  onPressed: () =>
                      setState(() => _obscureReg1 = !_obscureReg1),
                ))),
        AnimatedSize(
          duration: AppBrand.medium,
          curve: AppBrand.ease,
          alignment: Alignment.topCenter,
          child: _shouldShowPasswordRequirements
              ? Padding(
                  padding: const EdgeInsets.only(top: AppBrand.s2),
                  child: _buildPasswordRequirementsChecklist(_regPass.text),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: AppBrand.s4),
        const _FieldLabel('Confirm password'),
        TextField(
            controller: _confirm,
            obscureText: _obscureReg2,
            autofillHints: const [AutofillHints.newPassword],
            style: const TextStyle(color: AppBrand.text),
            decoration: AppBrand.field('Re-enter your password',
                errorText: _showConfirmMismatchMessage
                    ? 'Passwords do not match.'
                    : null,
                suffix: _RevealButton(
                  obscured: _obscureReg2,
                  onPressed: () =>
                      setState(() => _obscureReg2 = !_obscureReg2),
                ))),
        const SizedBox(height: AppBrand.s5),
        ElevatedButton(
          onPressed: (_isLoading || !_canSubmitRegisterPassword)
              ? null
              : _register,
          style: AppBrand.primaryButton,
          child: _isLoading
              ? const _ButtonSpinner()
              : const Text('CREATE ACCOUNT'),
        ),
        const SizedBox(height: AppBrand.s3),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Already have an account? ',
                style: TextStyle(color: AppBrand.textMuted, fontSize: 12.5)),
            TextButton(
              onPressed: () => setState(() => _isLogin = true),
              style: TextButton.styleFrom(
                foregroundColor: AppBrand.accent,
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Sign in',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ],
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppBrand.s3, vertical: AppBrand.s3),
      decoration: BoxDecoration(
        color: AppBrand.panel,
        borderRadius: AppBrand.radiusSm,
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in states.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                children: [
                  // Shape changes with state as well as colour, so the
                  // checklist still reads without colour vision.
                  AnimatedSwitcher(
                    duration: AppBrand.fast,
                    child: Icon(
                      entry.value
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      key: ValueKey(entry.value),
                      size: 15,
                      color: entry.value
                          ? AppBrand.success
                          : AppBrand.textSubtle,
                    ),
                  ),
                  const SizedBox(width: AppBrand.s2),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: entry.value
                            ? AppBrand.textMuted
                            : AppBrand.textSubtle,
                        fontSize: 11.5,
                        height: 1.3,
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
      // Deliberately generic. The genuinely OAuth-only case is already caught
      // by the _lookupEmail(oauthOnly) branch above, so the old "use those
      // buttons" advice was wrong for the common case: a Google user who has
      // since set a password can sign in here, and telling them otherwise sent
      // them down the wrong path. Staff (@tatis.local) get the same message —
      // the old branch printed working admin/receptionist demo credentials into
      // a toast that any customer could trigger by typing a @tatis.local email.
      return 'Invalid email or password.';
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

/// Sign in / Sign up segmented control.
///
/// Replaces the two loose pills. Both halves are full-height tap targets and
/// the selected state slides between them, so the change of mode reads as one
/// object moving rather than two colours swapping.
class _AuthModeSwitch extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;

  const _AuthModeSwitch({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppBrand.tapTarget,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppBrand.background,
        borderRadius: AppBrand.radiusMd,
        border: Border.all(color: AppBrand.border),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppBrand.medium,
            curve: AppBrand.ease,
            alignment: isLogin ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppBrand.surfaceLift,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppBrand.accentLine),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _AuthModeTab(
                label: 'SIGN IN',
                selected: isLogin,
                onTap: () => onChanged(true),
              ),
              _AuthModeTab(
                label: 'SIGN UP',
                selected: !isLogin,
                onTap: () => onChanged(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AuthModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: AppBrand.medium,
                curve: AppBrand.ease,
                style: TextStyle(
                  fontFamily: 'CenturyGothic',
                  color: selected ? AppBrand.chalk : AppBrand.textMuted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 1.2,
                ),
                child: Text(label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every input gets a visible label. A placeholder alone disappears the moment
/// someone starts typing, which is exactly when they need to check what the
/// field was asking for.
class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppBrand.s2, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: AppBrand.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _RevealButton extends StatelessWidget {
  final bool obscured;
  final VoidCallback onPressed;

  const _RevealButton({required this.obscured, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: obscured ? 'Show password' : 'Hide password',
      splashRadius: 22,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppBrand.textMuted,
        size: 20,
      ),
    );
  }
}

/// Keeps the button's own label out of the loading state — the width no longer
/// jumps between "SIGN IN" and "PLEASE WAIT...".
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: Color(0xFF0B0B0E),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppBrand.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppBrand.s3),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppBrand.textSubtle,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppBrand.border, height: 1)),
      ],
    );
  }
}
