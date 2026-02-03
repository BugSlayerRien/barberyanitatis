import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'calendar_page.dart';
import 'appointments_page.dart';
import 'profile_page.dart';
import 'dashboard_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'api_config.dart';

class BarberSelectionPage extends StatefulWidget {
  const BarberSelectionPage({super.key});

  @override
  State<BarberSelectionPage> createState() => _BarberSelectionPageState();
}

class _BarberSelectionPageState extends State<BarberSelectionPage> {
  int _selectedIndex = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _barbers = [];

  @override
  void initState() {
    super.initState();
    _loadBarbers();
  }

  Future<void> _loadBarbers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'list'}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load barbers.';
          _loading = false;
        });
        return;
      }

      final barbers = (data['barbers'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _barbers = barbers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load barbers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showBarberDetails(int barberId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'detail', 'barberID': barberId}),
      );
      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Failed to load barber info.')),
        );
        return;
      }
      final barber = data['barber'] as Map<String, dynamic>? ?? {};
      final todayCount = data['appointmentsToday'] is int
          ? data['appointmentsToday'] as int
          : int.tryParse('${data['appointmentsToday']}') ?? 0;

      showDialog(
        context: context,
        builder: (_) => BarberDetailDialog(
          barberName: barber['full_name']?.toString() ?? 'Barber',
          specialty: barber['specialty']?.toString() ?? 'General',
          yearsExperience: barber['years_experience'] is int
              ? barber['years_experience'] as int
              : int.tryParse('${barber['years_experience']}') ?? 0,
          rating: double.tryParse('${barber['rating']}') ?? 5.0,
          bio: barber['bio']?.toString() ?? '',
          todayAppointments: todayCount,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load barber info.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _barbers.length,
        itemBuilder: (context, index) {
          final barber = _barbers[index];
          final barberName = barber['full_name']?.toString() ?? 'Barber';
          final initials = barberName.isNotEmpty
              ? barberName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
              : 'B';

          return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10, width: 1),
              ),
                child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                barberName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          barber['specialty']?.toString() ?? 'General',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action buttons: View stats and Go to calendar
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          final barberId = barber['barber_id'] is int
                              ? barber['barber_id'] as int
                              : int.tryParse('${barber['barber_id']}') ?? 0;
                          if (barberId > 0) {
                            _showBarberDetails(barberId);
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('View'),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CalendarPage(
                                barberId: barber['barber_id'] is int ? barber['barber_id'] as int : int.tryParse('${barber['barber_id']}') ?? 0,
                                barberName: barberName,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.chevron_right, color: Colors.black, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
        },
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage()));
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppointmentsPage()));
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AiFaceScanPage()));
          } else if (index == 3) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedHaircutsPage()));
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }
}

class BarberDetailDialog extends StatelessWidget {
  final String barberName;
  final String specialty;
  final int yearsExperience;
  final double rating;
  final String bio;
  final int todayAppointments;

  const BarberDetailDialog({
    super.key,
    required this.barberName,
    required this.specialty,
    required this.yearsExperience,
    required this.rating,
    required this.bio,
    required this.todayAppointments,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFA99941),
            child: Text(
              barberName.isNotEmpty
                  ? barberName.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
                  : 'B',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              barberName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow('Specialty', specialty),
          _detailRow('Experience', '$yearsExperience yrs'),
          _detailRow('Rating', rating.toStringAsFixed(1)),
          _detailRow('Appointments today', '$todayAppointments'),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(bio, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}