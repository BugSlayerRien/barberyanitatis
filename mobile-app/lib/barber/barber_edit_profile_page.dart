import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';
import '../user/app_brand.dart';
import '../user/user_session.dart';
import '../user/widgets/app_top_bar.dart';

/// Lets a barber edit their own details.
///
/// Barbers used to be sent to the customer profile screen, which posts to
/// `profile.php`. That resolves the signed-in email against `users`, while a
/// barber's identity lives in `barbers` -- two unrelated id spaces -- so it
/// answered "You are not authorized to access this account" and a barber could
/// not change anything. This screen talks to `barbers.php` instead, the same
/// endpoint the barber Profile tab already reads from.
class BarberEditProfilePage extends StatefulWidget {
  const BarberEditProfilePage({super.key});

  @override
  State<BarberEditProfilePage> createState() => _BarberEditProfilePageState();
}

class _BarberEditProfilePageState extends State<BarberEditProfilePage> {
  final _nameController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _bioController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final barberId = UserSession.userId ?? 0;
    final email = UserSession.email ?? '';
    if (barberId <= 0 && email.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'detail', 'barberID': barberId, 'email': email}),
      );
      if (!mounted) return;

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = data['error']?.toString() ?? 'Could not load your profile.';
        });
        return;
      }

      final barber = (data['barber'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _nameController.text = barber['full_name']?.toString() ?? '';
        _specialtyController.text = barber['specialty']?.toString() ?? '';
        _bioController.text = barber['bio']?.toString() ?? '';
        _email = barber['email']?.toString() ?? email;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile. Check your connection.';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'updateProfile',
          'barberID': UserSession.userId ?? 0,
          'email': _email,
          'fullName': name,
          'specialty': _specialtyController.text.trim(),
          'bio': _bioController.text.trim(),
        }),
      );
      if (!mounted) return;

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      if (response.statusCode != 200) {
        // The server validates the same way the admin portal does, so its
        // wording is the useful thing to show.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Could not save your profile.')),
        );
        return;
      }

      UserSession.fullName = name;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Check your connection and try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppTopBar(
        showBack: true,
        showCustomerActions: false,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Edit profile',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _email,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    _field('Name', _nameController, hint: 'Your full name'),
                    const SizedBox(height: 16),
                    _field('Specialty', _specialtyController, hint: 'e.g. Fades, beard work'),
                    const SizedBox(height: 16),
                    _field('About you', _bioController, hint: 'Shown to customers', maxLines: 4),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: AppBrand.primaryButton,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your photo, rating and experience are managed by the shop admin.',
                      style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: AppBrand.field(hint ?? ''),
        ),
      ],
    );
  }
}
