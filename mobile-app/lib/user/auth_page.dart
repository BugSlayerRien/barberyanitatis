import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../receptionist/receptionist_dashboard_page.dart';
import '../admins/admin_dashboard_page.dart';
import 'forgot_password_page.dart';
import 'quiz_gender.dart';
import 'api_config.dart';
import 'user_session.dart';

// Local copy of the white color used in the app to avoid circular imports
const Color kGoldColor = Colors.white;

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final String _apiBaseUrl = ApiConfig.baseUrl;

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

  bool _obscureLogin = true;
  bool _obscureReg1 = true;
  bool _obscureReg2 = true;
  bool _rememberMe = false;

  Future<void> _login() async {
    final email = _loginUser.text.trim();
    final password = _loginPass.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter email and password.')),
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

        UserSession.userId = user['userID'] is int ? user['userID'] as int : int.tryParse('${user['userID']}');
        UserSession.fullName = user['fullName']?.toString();
        UserSession.email = user['email']?.toString();
        UserSession.roles = roles;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login successful')));

      if (roles.contains('admin')) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
      } else if (roles.contains('receptionist')) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceptionistDashboardPage()));
      } else {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizGenderPage()));
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

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty) {
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
        const SnackBar(content: Text('Password must be at least 6 characters.')),
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
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/auth.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'register',
          'fullName': '$firstName $lastName',
          'email': email,
          'password': password,
          'phone': phone,
          'roleName': 'Customer',
        }),
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;

      if (response.statusCode != 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Registration failed.')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful. Please sign in.')),
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
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _isLogin ? kGoldColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('SIGN IN', style: TextStyle(color: _isLogin ? Colors.black : Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => _isLogin = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: !_isLogin ? kGoldColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('SIGN UP (REGISTER)', style: TextStyle(color: !_isLogin ? Colors.black : Colors.white)),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Animated switch between login and register
                      AnimatedCrossFade(
                        firstChild: _buildLogin(context),
                        secondChild: _buildRegister(context),
                        crossFadeState: _isLogin ? CrossFadeState.showFirst : CrossFadeState.showSecond,
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
          child: Text('Sign in to your account', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _loginUser,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPass,
          obscureText: _obscureLogin,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your password', suffix: IconButton(icon: Icon(_obscureLogin ? Icons.visibility_off : Icons.visibility, color: Colors.white70), onPressed: () => setState(() => _obscureLogin = !_obscureLogin))),
        ),
        const SizedBox(height: 12),
        // Remember me and Forgot password
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _rememberMe,
                  onChanged: (value) => setState(() => _rememberMe = value ?? false),
                  side: const BorderSide(color: Colors.white54),
                ),
                const Text('Remember me', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                );
              },
              child: const Text('Forgot password?', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          child: Text(_isLoading ? 'PLEASE WAIT...' : 'SIGN IN', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Don’t have an account? ', style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton(
              onPressed: () => setState(() => _isLogin = false),
              child: const Text('Sign up', style: TextStyle(color: Colors.white, fontSize: 12)),
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
          child: Text('Create your account', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: TextField(controller: _firstName, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Enter first name'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _lastName, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Enter last name'))),
          ],
        ),
        const SizedBox(height: 12),
        TextField(controller: _regEmail, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Enter your email')),
        const SizedBox(height: 12),
        TextField(controller: _phone, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Enter phone number'), keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextField(controller: _regPass, obscureText: _obscureReg1, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Enter your password', suffix: IconButton(icon: Icon(_obscureReg1 ? Icons.visibility_off : Icons.visibility, color: Colors.white70), onPressed: () => setState(() => _obscureReg1 = !_obscureReg1)))),
        const SizedBox(height: 12),
        TextField(controller: _confirm, obscureText: _obscureReg2, style: const TextStyle(color: Colors.white), decoration: _fieldDecoration('Confirm your password', suffix: IconButton(icon: Icon(_obscureReg2 ? Icons.visibility_off : Icons.visibility, color: Colors.white70), onPressed: () => setState(() => _obscureReg2 = !_obscureReg2)))),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isLoading ? null : _register,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          child: Text(_isLoading ? 'PLEASE WAIT...' : 'CREATE ACCOUNT', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Already have an account? ', style: TextStyle(color: Colors.white54, fontSize: 12)),
            TextButton(
              onPressed: () => setState(() => _isLogin = true),
              child: const Text('Sign in', style: TextStyle(color: Colors.white, fontSize: 12)),
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
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
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
}
