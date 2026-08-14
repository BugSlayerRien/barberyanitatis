import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../user/widgets/app_top_bar.dart';
import '../user/widgets/shimmer_skeleton.dart';
import '../user/api_config.dart';
import '../user/user_session.dart';

class BarberProfilePage extends StatefulWidget {
  const BarberProfilePage({super.key});

  @override
  State<BarberProfilePage> createState() => _BarberProfilePageState();
}

class _BarberProfilePageState extends State<BarberProfilePage> {
  bool _loading = true;
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

  String _barberImageField(Map<String, dynamic>? barber) {
    if (barber == null) {
      return '';
    }
    final raw = barber['profile_image'] ?? barber['profileImage'] ?? '';
    final value = raw.toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') {
      return '';
    }
    return value;
  }

  /// Serve relative uploads through the existing PHP proxy so Android/iOS
  /// can load files Apache may not expose the same way as Flutter web.
  String _displayImageUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return ApiConfig.resolveImageUrl(trimmed);
    }
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '${ApiConfig.baseUrl}/image_proxy.php?path=${Uri.encodeComponent(path)}';
  }

  Future<void> _loadBarberProfile() async {
    final barberId = UserSession.userId;
    final email = (UserSession.email ?? '').trim();
    if ((barberId == null || barberId <= 0) && email.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'detail',
          'barberID': barberId ?? 0,
          'email': email,
        }),
      );
      if (!mounted) {
        return;
      }
      if (response.statusCode != 200 || response.body.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final barber = data['barber'] as Map<String, dynamic>?;
      final ratingValue = barber?['rating'];
      final resolvedId = barber?['barber_id'] is int
          ? barber!['barber_id'] as int
          : int.tryParse('${barber?['barber_id'] ?? ''}');
      if (resolvedId != null && resolvedId > 0) {
        UserSession.userId = resolvedId;
      }
      setState(() {
        if (ratingValue != null) {
          _rating = (double.tryParse(ratingValue.toString()) ?? 5.0).toStringAsFixed(2);
        }
        _ratingCount = (data['ratingCount'] as num?)?.toInt() ?? 0;
        _profileImageUrl = _barberImageField(barber);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final barberId = UserSession.userId;
    final email = (UserSession.email ?? '').trim();
    if ((barberId == null || barberId <= 0) && email.isEmpty) {
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
          'barberID': barberId ?? 0,
          'email': email,
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

      final saved = (data['profileImage'] ?? data['profile_image'])?.toString().trim() ?? '';
      if (saved.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved on disk, but the profile path was not stored.')),
        );
        return;
      }

      final savedBarberId = data['barberID'] is int
          ? data['barberID'] as int
          : int.tryParse('${data['barberID'] ?? ''}');
      if (savedBarberId != null && savedBarberId > 0) {
        UserSession.userId = savedBarberId;
      }

      setState(() {
        _profileImageUrl = saved;
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
      final url = _displayImageUrl(_profileImageUrl);
      return Image.network(
        url,
        key: ValueKey(url),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            initials,
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    return Center(
      child: Text(
        initials,
        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
      ),
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
            if (_loading)
              _buildProfileSkeleton()
            else ...[
              GestureDetector(
                onTap: _savingImage ? null : _pickAndUploadPhoto,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                    ),
                  ),
                  child: ClipOval(
                    child: _savingImage
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : _avatarWidget(initials),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                fullName.isNotEmpty ? fullName : 'Barber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                email.isNotEmpty ? email : 'No email available',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _infoCard('Role', roleText),
              const SizedBox(height: 16),
              _infoCard(
                'Current Rating',
                '$_rating ($_ratingCount ${_ratingCount == 1 ? 'rating' : 'ratings'})',
              ),
              const SizedBox(height: 16),
              _infoCard('Account ID', '${UserSession.userId ?? '-'}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSkeleton() {
    Widget skeletonCard({double valueWidth = 140}) {
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
            const AppShimmerBox(width: 80, height: 12, borderRadius: 4),
            const SizedBox(height: 10),
            AppShimmerBox(width: valueWidth, height: 14, borderRadius: 4),
          ],
        ),
      );
    }

    return AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: AppShimmerBox(width: 120, height: 120, borderRadius: 60),
          ),
          const SizedBox(height: 24),
          const Center(
            child: AppShimmerBox(width: 160, height: 18, borderRadius: 6),
          ),
          const SizedBox(height: 10),
          const Center(
            child: AppShimmerBox(width: 180, height: 13, borderRadius: 4),
          ),
          const SizedBox(height: 18),
          skeletonCard(),
          const SizedBox(height: 16),
          skeletonCard(valueWidth: 120),
          const SizedBox(height: 16),
          skeletonCard(valueWidth: 60),
        ],
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
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
