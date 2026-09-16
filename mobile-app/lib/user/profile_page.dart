import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'customer_navigation.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/shimmer_skeleton.dart';
import 'api_config.dart';
import 'customer_api.dart';
import 'user_session.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const _genderOptions = ['Male', 'Female', 'Prefer not to tell'];
  static const _hairTextureOptions = ['Straight', 'Wavy', 'Curly'];

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
  Map<String, String?> _bookingPreferences = {};
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

  String _readProfileValue(Map<String, dynamic> metadata, String key) {
    return metadata[key]?.toString().trim() ?? '';
  }

  String _genderForUi(String dbValue) {
    final value = dbValue.trim();
    if (value.isEmpty || value.toLowerCase() == 'other') {
      return 'Prefer not to tell';
    }
    if (_genderOptions.contains(value)) {
      return value;
    }
    return 'Prefer not to tell';
  }

  String _hairTextureForUi(String dbValue) {
    final value = dbValue.trim();
    if (value.isEmpty) {
      return '';
    }
    for (final option in _hairTextureOptions) {
      if (option.toLowerCase() == value.toLowerCase()) {
        return option;
      }
    }
    return value;
  }

  void _applyProfileData({
    required String fullName,
    required String email,
    required String phone,
    required String accountAge,
    required int haircutsDone,
    required String gender,
    required String hairTexture,
    required String profileImageUrl,
    Map<String, String?>? bookingPreferences,
    Uint8List? profileImageBytes,
  }) {
    // Keeps the cancel-appointment flow (appointments_page.dart) in sync: it
    // checks UserSession.phone directly rather than re-fetching the profile,
    // so every place that learns the phone number must update it here too.
    UserSession.phone = phone;
    setState(() {
      _fullName = fullName;
      _email = email;
      _phone = phone;
      _accountAge = accountAge.isNotEmpty ? accountAge : '—';
      _gender = _genderForUi(gender);
      _hairTexture = _hairTextureForUi(hairTexture);
      _haircutsDone = haircutsDone;
      if (bookingPreferences != null) {
        _bookingPreferences = bookingPreferences;
      }
      _profileImageUrl = profileImageUrl;
      _profileImageBytes = profileImageBytes;
      _nameController.text = _fullName;
      _phoneController.text = _phone;
      _loading = false;
      _error = null;
    });
  }

  Future<Map<String, dynamic>?> _loadProfileFromApi(int userId) async {
    final body = await CustomerApi.postDecoded('profile.php', {
      'action': 'get',
      'userID': userId,
    });

    final profile = body['profile'];
    if (profile is! Map) {
      throw const CustomerApiException('Profile response was invalid');
    }
    return Map<String, dynamic>.from(profile);
  }

  Map<String, String?> _bookingPreferencesFromProfile(Map<String, dynamic> profile) {
    final raw = profile['bookingPreferences'];
    if (raw is! Map) {
      return {};
    }
    String? label(dynamic value) {
      final text = value?.toString().trim() ?? '';
      return text.isEmpty ? null : text;
    }

    return {
      'usualBookingTime': label(raw['usualBookingTime']),
      'usualBarber': label(raw['usualBarber']),
      'usualBookingDay': label(raw['usualBookingDay']),
      'visitCount': '${raw['visitCount'] ?? 0}',
      'usualMinVisits': '${raw['usualMinVisits'] ?? 2}',
      'usualMinShare': '${raw['usualMinShare'] ?? 0.5}',
    };
  }

  String _preferenceDisplay(String key) {
    final value = _bookingPreferences[key]?.trim() ?? '';
    return value.isEmpty ? 'Not enough history yet' : value;
  }

  int get _visitCount =>
      int.tryParse(_bookingPreferences['visitCount'] ?? '') ?? 0;

  int get _usualMinVisits =>
      int.tryParse(_bookingPreferences['usualMinVisits'] ?? '') ?? 2;

  /// Explains what the card is showing, or exactly what is still missing.
  /// Mirrors slot_recommendation_is_usual(): a pattern counts as "usual" once
  /// the customer has at least [_usualMinVisits] completed visits AND the most
  /// common value either repeats that many times or covers at least the
  /// configured share of their visits.
  String _preferenceExplanation(String key, String what) {
    final visits = _visitCount;
    final needed = _usualMinVisits;
    final share = ((double.tryParse(_bookingPreferences['usualMinShare'] ?? '') ?? 0.5) * 100)
        .round();
    final hasValue = (_bookingPreferences[key]?.trim() ?? '').isNotEmpty;

    if (hasValue) {
      return 'This is your most frequent $what across your '
          '$visits completed appointment${visits == 1 ? '' : 's'}. '
          'It is used to suggest booking slots for you.';
    }

    if (visits < needed) {
      final remaining = needed - visits;
      return 'We need at least $needed completed appointments to spot a '
          'pattern. You have $visits, so $remaining more to go.\n\n'
          'Cancelled and no-show bookings do not count.';
    }

    return 'You have $visits completed appointments, but no clear favourite '
        '$what yet. One option needs to repeat at least $needed times, or '
        'cover $share% of your bookings.\n\n'
        'Keep booking and this will fill in on its own.';
  }

  void _showPreferenceInfo(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _saveProfileToApi({
    required int userId,
    required String fullName,
    required String phone,
    required String gender,
    required String hairTexture,
    String? profileImageBase64,
  }) async {
    final payload = <String, dynamic>{
      'action': 'update',
      'userID': userId,
      'fullName': fullName,
      'phone': phone,
      'gender': gender,
      'hairTexture': hairTexture,
    };
    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      payload['profile_image_base64'] = profileImageBase64;
    }

    final body = await CustomerApi.postDecoded('profile.php', payload);

    final profile = body['profile'];
    if (profile is Map) {
      return Map<String, dynamic>.from(profile);
    }
    return body;
  }

  /// Small Auth metadata only. Never write profile_image_base64 here — GoTrue
  /// copies user_metadata into every JWT and oversized tokens are rejected.
  Future<void> _syncSupabaseMetadata(Map<String, dynamic> updates) async {
    final currentSession = Supabase.instance.client.auth.currentSession;
    final currentUser =
        currentSession?.user ?? Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      return;
    }

    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: updates),
    );
  }

  Future<void> _loadProfile() async {
    final userId = UserSession.userId;
    final currentSession = Supabase.instance.client.auth.currentSession;
    final user = currentSession?.user ?? Supabase.instance.client.auth.currentUser;

    if (userId == null && user == null && !_hasLocalSession) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    try {
      if (userId != null && userId > 0) {
        final profile = await _loadProfileFromApi(userId);
        if (profile != null) {
          _applyProfileData(
            fullName: profile['fullName']?.toString().trim() ?? (UserSession.fullName ?? ''),
            email: profile['email']?.toString().trim() ?? (UserSession.email ?? ''),
            phone: profile['phone']?.toString().trim() ?? '',
            accountAge: profile['accountAge']?.toString().trim() ?? '',
            haircutsDone: profile['haircutsDone'] is int
                ? profile['haircutsDone'] as int
                : int.tryParse('${profile['haircutsDone']}') ?? 0,
            gender: profile['gender']?.toString().trim() ?? '',
            hairTexture: profile['hairTexture']?.toString().trim() ?? '',
            profileImageUrl: profile['profileImage']?.toString().trim() ?? '',
            bookingPreferences: _bookingPreferencesFromProfile(profile),
          );
          return;
        }
      }

      final metadata = user?.userMetadata ?? <String, dynamic>{};
      final resolvedFullName = _readProfileValue(metadata, 'full_name').isNotEmpty
          ? _readProfileValue(metadata, 'full_name')
          : _readProfileValue(metadata, 'name').isNotEmpty
              ? _readProfileValue(metadata, 'name')
              : (UserSession.fullName ?? '').trim();
      final resolvedEmail = (user?.email ?? UserSession.email ?? '').trim();
      final resolvedPhone = _readProfileValue(metadata, 'phone');
      // UserSession.phone is now set inside _applyProfileData below, so every
      // load path (this one and the API path above) keeps it current.
      final resolvedAccountAge = _readProfileValue(metadata, 'account_age');
      final resolvedGender = _readProfileValue(metadata, 'gender');
      final resolvedHairTexture = _readProfileValue(metadata, 'hair_texture');
      final resolvedProfileImageUrl = _readProfileValue(metadata, 'avatar_url');
      final resolvedHaircutsDone = metadata['haircuts_done'] is int
          ? metadata['haircuts_done'] as int
          : int.tryParse('${metadata['haircuts_done']}') ?? 0;

      _applyProfileData(
        fullName: resolvedFullName,
        email: resolvedEmail,
        phone: resolvedPhone,
        accountAge: resolvedAccountAge,
        haircutsDone: resolvedHaircutsDone,
        gender: resolvedGender,
        hairTexture: resolvedHairTexture,
        profileImageUrl: resolvedProfileImageUrl,
      );
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
        onBack: () => navigateBackToCustomerHome(context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (_loading)
              _buildProfileSkeleton()
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
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
                                ? Image.network(
                                    ApiConfig.resolveImageUrl(_profileImageUrl),
                                    fit: BoxFit.cover,
                                  )
                                : Center(
                                    child: Text(
                                      _fullName.isNotEmpty
                                          ? _fullName
                                              .trim()
                                              .split(' ')
                                              .map((e) => e.isNotEmpty ? e[0] : '')
                                              .take(2)
                                              .join()
                                              .toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ))),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _fullName.isNotEmpty ? _fullName : 'Customer',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              _buildTierBadge(),
              const SizedBox(height: 18),
              _highlightCard('Account Age', _accountAge),
              const SizedBox(height: 16),
              _editCard('Full Name', _nameController, hint: 'Enter full name'),
              const SizedBox(height: 16),
              _infoCard('Email', _email.isNotEmpty ? _email : '—'),
              const SizedBox(height: 16),
              // Gender is hidden from the profile UI — it is not needed for
              // anything the customer app does. The stored value is still
              // loaded and saved untouched so existing records keep their
              // value instead of being overwritten.
              _dropdownCard(
                label: 'Hair Texture',
                value: _hairTexture.isEmpty ? _hairTextureOptions.first : _hairTexture,
                options: _hairTextureOptions,
                onChanged: (value) => setState(() => _hairTexture = value ?? _hairTextureOptions.first),
              ),
              const SizedBox(height: 16),
              _editCard('Mobile Number', _phoneController, hint: 'Enter mobile number'),
              const SizedBox(height: 16),
              _infoCard('Haircuts Done', _haircutsDone.toString()),
              const SizedBox(height: 16),
              _infoCard('Usual booking time', _preferenceDisplay('usualBookingTime'),
                  onInfo: () => _showPreferenceInfo('Usual booking time',
                      _preferenceExplanation('usualBookingTime', 'time of day'))),
              const SizedBox(height: 16),
              _infoCard('Usual barber', _preferenceDisplay('usualBarber'),
                  onInfo: () => _showPreferenceInfo('Usual barber',
                      _preferenceExplanation('usualBarber', 'barber'))),
              const SizedBox(height: 16),
              _infoCard('Usual booking day', _preferenceDisplay('usualBookingDay'),
                  onInfo: () => _showPreferenceInfo('Usual booking day',
                      _preferenceExplanation('usualBookingDay', 'day of the week'))),
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
                    : const Text(
                        'Save Changes',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
              ),
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
            child: AppShimmerBox(width: 100, height: 24, borderRadius: 12),
          ),
          const SizedBox(height: 18),
          skeletonCard(valueWidth: 120),
          const SizedBox(height: 16),
          skeletonCard(),
          const SizedBox(height: 16),
          skeletonCard(valueWidth: 180),
          const SizedBox(height: 16),
          skeletonCard(),
          const SizedBox(height: 16),
          skeletonCard(),
          const SizedBox(height: 16),
          skeletonCard(),
          const SizedBox(height: 16),
          skeletonCard(valueWidth: 60),
          const SizedBox(height: 24),
          const AppShimmerBox(height: 50, borderRadius: 10),
        ],
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
      final newGender = _gender.trim().isEmpty ? 'Prefer not to tell' : _gender.trim();
      final newHairTexture =
          _hairTexture.trim().isEmpty ? _hairTextureOptions.first : _hairTexture.trim();

      if (newFullName.isEmpty) {
        throw StateError('Full name is required.');
      }

      Uint8List? newProfileImageBytes;
      String? profileImageBase64;

      if (_profileImage != null) {
        final bytes = await _profileImage!.readAsBytes();
        newProfileImageBytes = bytes;
        profileImageBase64 = base64Encode(bytes);
      }

      final userId = UserSession.userId;
      if (userId != null && userId > 0) {
        final saved = await _saveProfileToApi(
          userId: userId,
          fullName: newFullName,
          phone: newPhone,
          gender: newGender,
          hairTexture: newHairTexture,
          profileImageBase64: profileImageBase64,
        );

        UserSession.fullName = newFullName;

        if (!mounted) return;
        _applyProfileData(
          fullName: saved['fullName']?.toString().trim() ?? newFullName,
          email: saved['email']?.toString().trim() ?? _email,
          phone: saved['phone']?.toString().trim() ?? newPhone,
          accountAge: saved['accountAge']?.toString().trim() ?? _accountAge,
          haircutsDone: saved['haircutsDone'] is int
              ? saved['haircutsDone'] as int
              : _haircutsDone,
          gender: saved['gender']?.toString().trim() ?? newGender,
          hairTexture: saved['hairTexture']?.toString().trim() ?? newHairTexture,
          profileImageUrl: saved['profileImage']?.toString().trim() ?? _profileImageUrl,
          bookingPreferences: _bookingPreferencesFromProfile(saved),
          profileImageBytes: newProfileImageBytes ?? _profileImageBytes,
        );
        setState(() {
          _profileImage = null;
          _saving = false;
        });

        await _syncSupabaseMetadata({
          'full_name': newFullName,
          'phone': newPhone,
          'gender': newGender,
          'hair_texture': newHairTexture,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully.')),
        );
        return;
      }

      final currentSession = Supabase.instance.client.auth.currentSession;
      final currentUser =
          currentSession?.user ?? Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw StateError('No active session found. Please sign in again.');
      }

      final updates = <String, dynamic>{
        'full_name': newFullName,
        'phone': newPhone,
        'gender': newGender,
        'hair_texture': newHairTexture,
      };

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: updates),
      );

      if (!mounted) return;

      setState(() {
        _fullName = newFullName;
        _phone = newPhone;
        _gender = newGender;
        _hairTexture = newHairTexture;
        _profileImageBytes = newProfileImageBytes ?? _profileImageBytes;
        _profileImage = null;
        _saving = false;
      });

      UserSession.fullName = newFullName;
      await UserSession.savePreferredHairTexture(newHairTexture);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $e')),
      );
    }
  }

  Widget _cardShell({required Widget child}) {
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
      child: child,
    );
  }

  Widget _highlightCard(String label, String value) {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, {VoidCallback? onInfo}) {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              if (onInfo != null)
                GestureDetector(
                  onTap: onInfo,
                  // Padding keeps the tap target usable; the icon alone is
                  // smaller than the minimum comfortable touch size.
                  child: const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 4),
                    child: Icon(Icons.info_outline, color: Colors.white54, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _dropdownCard({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return _cardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: options.contains(value) ? value : options.first,
            dropdownColor: const Color(0xFF1A1A1A),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF111111),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
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
        return AppBrand.accent;
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
              'Tier: $tier\n'
              'Completed appointments: $_haircutsDone\n\n'
              'Rookie: 0–1 completed\n'
              'Bronze: 2–4\n'
              'Silver: 5–9\n'
              'Gold: 10–19\n'
              'Platinum: 20+',
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
    return _cardShell(
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
