import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_brand.dart';
import 'api_config.dart';
import 'auth_redirect.dart';
import 'auth_user_messages.dart';
import 'password_policy.dart';
import 'supabase_password_identity.dart';
import 'user_session.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _formError;
  late final bool _hasPasswordIdentity;

  @override
  void initState() {
    super.initState();
    _hasPasswordIdentity = supabaseUserHasPasswordIdentity(
      Supabase.instance.client.auth.currentUser,
    );
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;

    setState(() => _formError = null);

    if (_hasPasswordIdentity && current.isEmpty) {
      setState(() => _formError = 'Current password is required.');
      return;
    }
    if (next.isEmpty || confirm.isEmpty) {
      setState(() => _formError = 'Please enter and confirm your new password.');
      return;
    }

    final policyError = PasswordPolicy.validationError(next);
    if (policyError != null) {
      setState(() => _formError = policyError);
      return;
    }

    if (next != confirm) {
      setState(() => _formError = 'New password and confirmation do not match.');
      return;
    }

    if (_hasPasswordIdentity && current == next) {
      setState(() => _formError = 'New password must be different from your current password.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final email = (UserSession.email ?? '').trim();
      final supabase = Supabase.instance.client;
      if (supabase.auth.currentSession != null && email.isNotEmpty) {
        final updated = await _updateSupabasePassword(
          email: email,
          currentPassword: current,
          newPassword: next,
          requireCurrentPassword: _hasPasswordIdentity,
        );
        if (updated) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully.')),
          );
          Navigator.of(context).pop(true);
          return;
        }
        return;
      }

      await _updatePhpPassword(
        current: current,
        next: next,
        confirm: confirm,
      );
    } catch (e) {
      const message = 'Could not change password. Check your connection and try again.';
      setState(() => _formError = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$message\n$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Returns true when the password was changed. Returns false when a
  /// user-facing error was already shown (wrong current password / OAuth).
  Future<bool> _updateSupabasePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
    required bool requireCurrentPassword,
  }) async {
    try {
      if (requireCurrentPassword) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: currentPassword,
        );
      }
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return true;
    } on AuthException catch (e) {
      final message = authLooksLikeInvalidCredentials(e)
          ? 'Current password is incorrect.'
          : authFriendlyError(e);
      setState(() => _formError = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      return false;
    }
  }

  Future<void> _sendPasswordSetupEmail() async {
    final email = (UserSession.email ?? '').trim();
    if (email.isEmpty) {
      setState(() => _formError = 'No email is available on this session.');
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      AuthRedirect.prepareWebOAuthReturn();
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: AuthRedirect.supabaseRedirectUri,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If this account can receive email, a password setup link was sent.',
          ),
        ),
      );
    } catch (e) {
      final message = authFriendlyError(e);
      setState(() => _formError = message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _updatePhpPassword({
    required String current,
    required String next,
    required String confirm,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'changePassword',
        'userId': UserSession.userId,
        'email': UserSession.email,
        'currentPassword': current,
        'newPassword': next,
        'confirmPassword': confirm,
      }),
    );

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode == 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['message']?.toString() ?? 'Password updated successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    final code = data['code']?.toString() ?? '';
    final message = code == 'OAUTH_ONLY'
        ? 'This account uses Google or Facebook. Use those buttons, or Forgot password to set an email password.'
        : code == 'SUPABASE_PASSWORD'
            ? 'Sign in with your email and password first, then try again. Or use Forgot password.'
            : (data['error']?.toString() ?? 'Could not change password.');
    setState(() => _formError = message);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Change Password',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _hasPasswordIdentity
                ? 'Update the password for your account. Use a strong password you have not used here before.'
                : 'This account signed in with Google or Facebook and has no email password yet. Set one here while you are signed in, or email yourself a recovery link.',
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_hasPasswordIdentity) ...[
            _field(
              controller: _currentController,
              label: 'Current password',
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 14),
          ],
          _field(
            controller: _newController,
            label: 'New password',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _buildRequirementsChecklist(_newController.text),
          const SizedBox(height: 14),
          _field(
            controller: _confirmController,
            label: 'Confirm new password',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 14),
            Text(
              _formError!,
              style: const TextStyle(color: Color(0xFFE57373), fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: AppBrand.primaryButton,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    _hasPasswordIdentity ? 'Update password' : 'Set password',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
          if (!_hasPasswordIdentity) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _submitting ? null : _sendPasswordSetupEmail,
              child: const Text(
                'Email me a password setup link instead',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: AppBrand.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppBrand.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppBrand.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppBrand.goldLine),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Colors.white54,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _buildRequirementsChecklist(String password) {
    final states = PasswordPolicy.requirementStates(password);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in states.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    entry.value ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: entry.value ? const Color(0xFF81C784) : Colors.white38,
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
}
