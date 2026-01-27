import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../receptionist/receptionist_dashboard_page.dart';
import '../admins/admin_dashboard_page.dart';
import 'forgot_password_page.dart';
import 'quiz_gender.dart';

// Local copy of the white color used in the app to avoid circular imports
const Color kGoldColor = Colors.white;

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _isLogin = true;
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

  Future<void> _signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google sign-in successful')),
      );
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizGenderPage()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in failed: $e')),
      );
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
                Image.asset('assets/images/TATIS.png', height: 96, color: Colors.white),
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
          decoration: _fieldDecoration('Enter username (Customer, Recep, or Admin)'),
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
          onPressed: () {
            final u = _loginUser.text.trim();
            final p = _loginPass.text;
            if (u == 'Customer' && p == 'Cust123') {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login successful')));
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizGenderPage()));
            } else if (u == 'recep' && p == 'recep123') {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login successful')));
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReceptionistDashboardPage()));
            } else if (u == 'admin' && p == 'admin123') {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login successful')));
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
            } else {
              showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Login failed', style: TextStyle(color: Colors.white)),
                  content: const Text('Invalid username or password.', style: TextStyle(color: Colors.white70)),
                  actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          child: const Text('SIGN IN', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        // OR CONTINUE WITH
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white24)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('OR CONTINUE WITH', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w500)),
            ),
            Expanded(child: Divider(color: Colors.white24)),
          ],
        ),
        const SizedBox(height: 12),
        // Google sign-in button inside the container
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _signInWithGoogle,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.language, size: 18),
            label: const Text('Continue with Google'),
          ),
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
          onPressed: () {
            // UX-only: just close back to previous screen
            setState(() => _isLogin = true);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
          child: const Text('SIGN UP', style: TextStyle(fontWeight: FontWeight.bold)),
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
}
