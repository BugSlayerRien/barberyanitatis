import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  String _rating = '5.0';

  @override
  void initState() {
    super.initState();
    _loadBarberRating();
  }

  Future<void> _loadBarberRating() async {
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
      if (ratingValue != null) {
        setState(() {
          _rating = (double.tryParse(ratingValue.toString()) ?? 5.0).toStringAsFixed(2);
        });
      }
    } catch (_) {
      // Keep fallback rating on errors.
    } finally {
      if (mounted) {
        setState(() => _loadingRating = false);
      }
    }
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
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                gradient: LinearGradient(
                  colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
                ),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
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
            _infoCard('Current Rating', _loadingRating ? 'Loading...' : _rating),
            const SizedBox(height: 16),
            _infoCard('Account ID', '${UserSession.userId ?? '-'}'),
            const SizedBox(height: 16),
            _infoCard('Profile', 'This is your barber account profile.'),
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
}
