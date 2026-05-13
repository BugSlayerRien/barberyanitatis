import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  String _gender = '';
  String _hairTexture = '';
  String _profileImageUrl = '';
  Uint8List? _profileImageBytes;
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

  bool get _hasLocalSession {
    return UserSession.userId != null ||
        (UserSession.fullName ?? '').trim().isNotEmpty ||
        (UserSession.email ?? '').trim().isNotEmpty;
  }

  String _readProfileValue(
    Map<String, dynamic> metadata,
    String key,
  ) {
    return metadata[key]?.toString().trim() ?? '';
  }

  Future<void> _loadProfile() async {
    final currentSession = Supabase.instance.client.auth.currentSession;
    final user = currentSession?.user ?? Supabase.instance.client.auth.currentUser;
    if (user == null && !_hasLocalSession) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    try {
      final metadata = user?.userMetadata ?? <String, dynamic>{};
      final resolvedFullName = _readProfileValue(metadata, 'full_name').isNotEmpty
          ? _readProfileValue(metadata, 'full_name')
          : _readProfileValue(metadata, 'name').isNotEmpty
              ? _readProfileValue(metadata, 'name')
              : (UserSession.fullName ?? '').trim();
      final resolvedEmail = (user?.email ?? UserSession.email ?? '').trim();
      final resolvedPhone = _readProfileValue(metadata, 'phone');
      final resolvedAccountAge = _readProfileValue(metadata, 'account_age');
      final resolvedGender = _readProfileValue(metadata, 'gender');
      final resolvedHairTexture = _readProfileValue(metadata, 'hair_texture');
      final resolvedProfileImageUrl = _readProfileValue(metadata, 'avatar_url');
      final resolvedProfileImageBase64 = _readProfileValue(metadata, 'profile_image_base64');
      final resolvedHaircutsDone = metadata['haircuts_done'] is int
          ? metadata['haircuts_done'] as int
          : int.tryParse('${metadata['haircuts_done']}') ?? 0;
      
      setState(() {
        _fullName = resolvedFullName;
        _email = resolvedEmail;
        _profileImageUrl = resolvedProfileImageUrl;
        _profileImageBytes = resolvedProfileImageBase64.isNotEmpty
            ? base64Decode(resolvedProfileImageBase64)
            : null;
        _phone = resolvedPhone;
        _accountAge = resolvedAccountAge.isNotEmpty ? resolvedAccountAge : '—';
        _gender = resolvedGender;
        _hairTexture = resolvedHairTexture;
        _haircutsDone = resolvedHaircutsDone;
        
        _nameController.text = _fullName;
        _phoneController.text = _phone;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading profile: ${e.toString()}';
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
                        : (_profileImageBytes != null
                            ? Image.memory(_profileImageBytes!, fit: BoxFit.cover)
                            : (_profileImageUrl.isNotEmpty
                                ? Image.network(ApiConfig.resolveImageUrl(_profileImageUrl), fit: BoxFit.cover)
                                : Center(
                                    child: Text(
                                      _fullName.isNotEmpty
                                          ? _fullName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase()
                                          : 'U',
                                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                  ))),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _fullName.isNotEmpty ? _fullName : 'Customer',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              _buildTierBadge(),
              const SizedBox(height: 18),

              _editCard('Full Name', _nameController, hint: 'Enter full name'),
              const SizedBox(height: 16),

              _infoCard('Email', _email.isNotEmpty ? _email : '—'),
              const SizedBox(height: 16),
              _infoCard('Gender', _formatGender(_gender)),
              const SizedBox(height: 16),
              _infoCard('Hair Texture', _formatHairTexture(_hairTexture)),
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
    setState(() => _saving = true);
    try {
      final newFullName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();
      Uint8List? newProfileImageBytes;
      
      // Update Supabase user metadata
      final updates = <String, dynamic>{
        'full_name': newFullName,
        'phone': newPhone,
      };
      
      // If a new image was selected, convert to base64
      if (_profileImage != null) {
        try {
          final bytes = await _profileImage!.readAsBytes();
          newProfileImageBytes = bytes;
          final imageBase64 = base64Encode(bytes);
          updates['profile_image_base64'] = imageBase64;
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to process image: $e')),
          );
          setState(() => _saving = false);
          return;
        }
      }
      
      final currentSession = Supabase.instance.client.auth.currentSession;
      final currentUser = currentSession?.user ?? Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw StateError('No Supabase session found. Please sign in again.');
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: updates,
        ),
      );
      
      if (!mounted) return;
      
      // Update local state and UserSession
      setState(() {
        _fullName = newFullName;
        _phone = newPhone;
        _profileImageBytes = newProfileImageBytes ?? _profileImageBytes;
        _profileImage = null;
        _saving = false;
      });
      
      UserSession.fullName = newFullName;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _saving = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile to Supabase: $e')),
      );
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

  String _formatGender(String value) {
    if (value.isEmpty) {
      return 'Prefer not to tell';
    }
    if (value.toLowerCase() == 'other') {
      return 'Prefer not to tell';
    }
    return value;
  }

  String _formatHairTexture(String value) {
    if (value.isEmpty) {
      return 'Prefer not to tell';
    }
    return value;
  }

  String _tierLabel(int count) {
    if (count >= 20) return 'Platinum';
    if (count >= 10) return 'Gold';
    if (count >= 5) return 'Silver';
    if (count >= 2) return 'Bronze';
    return 'Rookie';
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'Platinum':
        return const Color(0xFFE5E4E2);
      case 'Gold':
        return const Color(0xFFA99941);
      case 'Silver':
        return const Color(0xFFC0C0C0);
      case 'Bronze':
        return const Color(0xFFCD7F32);
      default:
        return Colors.white70;
    }
  }

  Widget _buildTierBadge() {
    final tier = _tierLabel(_haircutsDone);
    final color = _tierColor(tier);
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Loyalty Badge', style: TextStyle(color: Colors.white)),
            content: Text(
              'Tier: $tier\nCompleted haircuts: $_haircutsDone',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              tier,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
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
