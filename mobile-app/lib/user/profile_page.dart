import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'widgets/app_top_bar.dart';
import 'api_config.dart';
import 'user_session.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = true;
  String? _error;
  bool _saving = false;
  String _fullName = '';
  String _email = '';
  String _phone = '';
  String _accountAge = '';
  int _haircutsDone = 0;
  String _profileImageUrl = '';
  XFile? _profileImage;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (UserSession.userId == null) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/profile.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userID': UserSession.userId}),
      );
      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = data['error']?.toString() ?? 'Failed to load profile.';
        });
        return;
      }
      final profile = data['profile'] as Map<String, dynamic>? ?? {};
      setState(() {
        _fullName = profile['fullName']?.toString() ?? UserSession.fullName ?? '';
        _email = profile['email']?.toString() ?? UserSession.email ?? '';
        _phone = profile['phone']?.toString() ?? '';
        _accountAge = profile['accountAge']?.toString() ?? '';
        _haircutsDone = profile['haircutsDone'] is int
            ? profile['haircutsDone'] as int
            : int.tryParse('${profile['haircutsDone']}') ?? 0;
        _profileImageUrl = profile['profileImage']?.toString() ?? '';
        _nameController.text = _fullName;
        _phoneController.text = _phone;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load profile: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.white70))
            else ...[
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    gradient: LinearGradient(
                      colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
                    ),
                  ),
                  child: ClipOval(
                    child: _profileImage != null
                        ? (kIsWeb
                            ? Image.network(_profileImage!.path, fit: BoxFit.cover)
                            : Image.file(File(_profileImage!.path), fit: BoxFit.cover))
                        : (_profileImageUrl.isNotEmpty
                            ? Image.network(ApiConfig.resolveImageUrl(_profileImageUrl), fit: BoxFit.cover)
                            : Center(
                                child: Text(
                                  _fullName.isNotEmpty
                                      ? _fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                                      : 'U',
                                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                ),
                              )),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              _editCard('Full Name', _nameController, hint: 'Enter full name'),
              const SizedBox(height: 16),

              _infoCard('Email', _email.isNotEmpty ? _email : '—'),
              const SizedBox(height: 16),
              _editCard('Mobile Number', _phoneController, hint: 'Enter mobile number'),
              const SizedBox(height: 16),
              _infoCard('Account Age', _accountAge.isNotEmpty ? _accountAge : '—'),
              const SizedBox(height: 16),
              _infoCard('Haircuts Done', _haircutsDone.toString()),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Text('Save Changes', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _profileImage = image);
    }
  }

  Future<void> _saveProfile() async {
    if (UserSession.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in again.')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageBase64;
      if (_profileImage != null) {
        final bytes = await _profileImage!.readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/profile.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'update',
          'userID': UserSession.userId,
          'fullName': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          if (imageBase64 != null) 'profileImageBase64': imageBase64,
        }),
      );

      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Failed to save profile.')),
        );
        return;
      }
      final profile = data['profile'] as Map<String, dynamic>? ?? {};
      setState(() {
        _fullName = profile['fullName']?.toString() ?? _fullName;
        _email = profile['email']?.toString() ?? _email;
        _phone = profile['phone']?.toString() ?? _phone;
        _profileImageUrl = profile['profileImage']?.toString() ?? _profileImageUrl;
        _profileImage = null;
      });
      UserSession.fullName = _fullName;
      UserSession.email = _email;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _infoCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _editCard(String label, TextEditingController controller, {String? hint}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF111111),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
