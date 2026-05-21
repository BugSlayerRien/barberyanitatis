import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../user/widgets/app_top_bar.dart';
import '../user/api_config.dart';
import '../user/user_session.dart';

class BarberProfilePage extends StatefulWidget {
  const BarberProfilePage({super.key});

  @override
  State<BarberProfilePage> createState() => _BarberProfilePageState();
}

class _BarberProfilePageState extends State<BarberProfilePage> {
  bool _loadingRating = false;
  bool _savingImage = false;
  String _rating = '5.0';
  int _ratingCount = 0;
  String _profileImageUrl = '';
  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _loadBarberProfile();
  }

  Future<void> _loadBarberProfile() async {
    final barberId = UserSession.userId;
    if (barberId == null || barberId <= 0) {
      return;
    }

    setState(() => _loadingRating = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'detail', 'barberID': barberId}),
      );
      if (!mounted) {
        return;
      }
      if (response.statusCode != 200 || response.body.isEmpty) {
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final barber = data['barber'] as Map<String, dynamic>?;
      final ratingValue = barber?['rating'];
      setState(() {
        if (ratingValue != null) {
          _rating = (double.tryParse(ratingValue.toString()) ?? 5.0).toStringAsFixed(2);
        }
        _ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
        _profileImageUrl = barber?['profile_image']?.toString() ?? '';
      });
    } catch (_) {
      // Keep fallback values on errors.
    } finally {
      if (mounted) {
        setState(() => _loadingRating = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final barberId = UserSession.userId;
    if (barberId == null || barberId <= 0) {
      return;
    }

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _pickedImage = image;
      _savingImage = true;
    });

    try {
      final bytes = await image.readAsBytes();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'updateProfileImage',
          'barberID': barberId,
          'profileImageBase64': base64Encode(bytes),
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (!mounted) {
        return;
      }

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Could not update photo.')),
        );
        return;
      }

      setState(() {
        _profileImageUrl = data['profileImage']?.toString() ?? _profileImageUrl;
        _pickedImage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingImage = false);
      }
    }
  }

  Widget _avatarWidget(String initials) {
    if (_pickedImage != null) {
      if (kIsWeb) {
        return Image.network(_pickedImage!.path, fit: BoxFit.cover);
      }
      return Image.file(File(_pickedImage!.path), fit: BoxFit.cover);
    }
    if (_profileImageUrl.isNotEmpty) {
      return Image.network(
        ApiConfig.resolveImageUrl(_profileImageUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        ),
      );
    }
    return Center(
      child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = (UserSession.fullName ?? '').trim();
    final email = (UserSession.email ?? '').trim();
    final roleText = UserSession.roles.isNotEmpty ? UserSession.roles.join(', ') : 'barber';
    final initials = fullName.isNotEmpty
        ? fullName
            .trim()
            .split(' ')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0])
            .take(2)
            .join()
            .toUpperCase()
        : 'B';

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
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    color: const Color(0xFF1A1A1A),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _savingImage
                      ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : _avatarWidget(initials),
                ),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFA99941),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _savingImage ? null : _pickAndUploadPhoto,
                  icon: const Icon(Icons.camera_alt, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _savingImage ? null : _pickAndUploadPhoto,
              child: const Text('Change profile photo', style: TextStyle(color: Color(0xFFA99941))),
            ),
            const SizedBox(height: 16),
            Text(
              fullName.isNotEmpty ? fullName : 'Barber',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              email.isNotEmpty ? email : 'No email available',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _infoCard('Role', roleText),
            const SizedBox(height: 16),
            _infoCard(
              'Current Rating',
              _loadingRating
                  ? 'Loading...'
                  : '$_rating (${_ratingCount} ${_ratingCount == 1 ? 'rating' : 'ratings'})',
            ),
            const SizedBox(height: 16),
            _infoCard('Account ID', '${UserSession.userId ?? '-'}'),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
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
}
