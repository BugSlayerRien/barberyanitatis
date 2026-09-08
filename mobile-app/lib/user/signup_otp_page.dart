import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_bootstrap.dart';
import 'auth_user_messages.dart';

/// Email verification step for a new account.
///
/// Supabase sends both a confirmation link and a 6-digit code in the same
/// sign-up email. The link requires leaving the app and coming back through a
/// deep link; the code can be typed here, which is the same pattern the
/// password-recovery screen already uses (`OtpType.recovery`). This screen uses
/// `OtpType.signup`, and a successful verification returns a real session, so
/// the customer lands on the dashboard already signed in.
class SignupOtpPage extends StatefulWidget {
  final String email;
  final String fullName;

  const SignupOtpPage({
    super.key,
    required this.email,
    required this.fullName,
  });

  @override
  State<SignupOtpPage> createState() => _SignupOtpPageState();
}

class _SignupOtpPageState extends State<SignupOtpPage> {
  final _codeController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit code from your email.')),
      );
      return;
    }

    setState(() => _verifying = true);
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: widget.email,
        token: code,
        type: OtpType.signup,
      );

      final session = response.session;
      if (session == null) {
        throw const AuthException('No session returned for that code.');
      }

      await AuthBootstrap.applySupabaseSession(session);
      AuthBootstrap.markPasswordLogin();
      if (!mounted) return;
      AuthBootstrap.navigateToSignedInHome(showSnackBar: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authFriendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code is on its way.')),
      );
    } catch (e) {
      if (!mounted) return;
      // Supabase's free tier caps outbound auth email per hour across the whole
      // project, so this is a normal thing to hit while testing.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authFriendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: const Text('Verify your email'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              'We sent a 6-digit code to ${widget.email}. Enter it below to '
              'finish creating your account.',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  color: Colors.white, fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '000000',
                hintStyle: TextStyle(color: Colors.white24, letterSpacing: 8),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _verifying ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _verifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('Verify and continue',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _resending ? null : _resend,
              child: Text(
                _resending ? 'Sending...' : 'Resend code',
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
