import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_brand.dart';
import 'auth_bootstrap.dart';
import 'auth_redirect.dart';
import 'auth_user_messages.dart';

/// Two-step recovery, both driven by the same Supabase recovery email:
///   1. Request the email (`resetPasswordForEmail`).
///   2. Enter the 6-digit code from that email (`verifyOTP` type recovery),
///      which establishes the recovery session in-app.
///
/// The recovery *link* in the same email still works and is handled by
/// [AuthBootstrap]'s deep-link path — entering the code is an alternative so
/// the user never has to leave the app.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  bool _isSubmitting = false;
  bool _isVerifying = false;

  /// Email the code was actually sent to. Non-null means step 2.
  String? _sentToEmail;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      AuthRedirect.prepareWebOAuthReturn();
      // redirectTo keeps the emailed recovery *link* working as before. If the
      // template also contains {{ .Token }}, the same email carries a code the
      // user can type below instead.
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: AuthRedirect.supabaseRedirectUri,
      );
      await AuthBootstrap.markRecoveryRequested(email: email);
      if (!mounted) return;
      setState(() => _sentToEmail = email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If an account exists for that email, we sent a reset code.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(authFriendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _sentToEmail;
    final code = _codeController.text.trim();
    if (email == null) {
      return;
    }
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the code from your email.')),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );

      final session = response.session;
      if (session == null) {
        throw const AuthException('No session returned for that code.');
      }

      // Binds this session as the verified recovery session and routes to the
      // password screen. Navigation is owned by AuthBootstrap, same as the
      // recovery-link path.
      final bound = await AuthBootstrap.completeOtpRecovery(session);
      if (!mounted) return;
      if (!bound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not verify that code for this account. '
              'Request a new code and try again.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_readableOtpError(e))),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String _readableOtpError(Object error) {
    final friendly = authFriendlyError(error);
    if (friendly.contains('Too many emails')) {
      return friendly;
    }
    final lower = error.toString().toLowerCase();
    // GoTrue returns one combined message, "Token has expired or is invalid",
    // for both a wrong code and a genuinely expired one. Do not claim it
    // expired — a mistyped or truncated code is far more common, and telling
    // the user it expired sends them to request a new email they don't need
    // (which also burns the project's hourly email quota).
    if (lower.contains('expired') || lower.contains('invalid')) {
      return 'That code did not work. Check the code in your email and '
          're-enter it, or tap “Send again” if it is more than an hour old.';
    }
    if (lower.contains('token')) {
      return 'That code is not correct. Check your email and try again.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'Network issue. Please try again.';
    }
    return friendly;
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: AppBrand.surfaceAlt,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppBrand.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppBrand.goldLine),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppBrand.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onCodeStep = _sentToEmail != null;
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Forgot Password',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (onCodeStep) {
              setState(() {
                _sentToEmail = null;
                _codeController.clear();
              });
              return;
            }
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: AppBrand.card,
              child: onCodeStep ? _buildCodeStep() : _buildEmailStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reset your password',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your email and we’ll send you a reset code. You can type the '
          'code here without leaving the app.',
          style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('Enter your email'),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _sendReset,
          style: AppBrand.primaryButton,
          child: Text(_isSubmitting ? 'Sending...' : 'Send reset code'),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter your code',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a code to ${_sentToEmail!}. Enter it below to set a new '
          'password. The reset link in that same email still works too.',
          style: const TextStyle(
              color: Colors.white70, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // Supabase's "Email OTP Length" is configurable (6-10). Cap at the
          // maximum rather than a specific length: hardcoding 6 silently
          // truncated an 8-digit code, which then failed as "invalid".
          maxLength: 10,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            letterSpacing: 6,
          ),
          decoration:
              _fieldDecoration('Enter the code').copyWith(counterText: ''),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _isVerifying ? null : _verifyCode,
          style: AppBrand.primaryButton,
          child: Text(_isVerifying ? 'Verifying...' : 'Verify code'),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: _isSubmitting || _isVerifying ? null : _sendReset,
            child: Text(
              _isSubmitting ? 'Sending...' : 'Send again',
              style: const TextStyle(color: AppBrand.gold, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
