import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';
import '../user/time_format_utils.dart';
import '../user/widgets/app_top_bar.dart';
import '../user/widgets/menu_sheet.dart';
import '../user/user_session.dart';
import 'barber_appointment_detail_page.dart';
import 'barber_profile_page.dart';

class BarberDashboardPage extends StatefulWidget {
  const BarberDashboardPage({super.key});

  @override
  State<BarberDashboardPage> createState() => _BarberDashboardPageState();
}

class _BarberDashboardPageState extends State<BarberDashboardPage> {
  static const int _tabDashboard = 0;
  static const int _tabProfile = 1;
  static const int _tabMenu = 2;

  int _currentTab = _tabDashboard;
  bool _loading = true;
  bool _showWelcomeBanner = true;
  String? _error;
  String? _expandedStatus;
  List<Map<String, dynamic>> _appointments = [];
  Timer? _welcomeTimer;

  @override
  void initState() {
    super.initState();
    _welcomeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showWelcomeBanner = false);
    });
    _loadAppointments();
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    final barberId = UserSession.userId;
    if (barberId == null || barberId <= 0) {
      setState(() {
        _loading = false;
        _error = 'Invalid barber session. Please log in again.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listByBarber',
          'barberID': barberId,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load barber appointments.';
          _loading = false;
        });
        return;
      }

      final items = (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _appointments = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load barber appointments: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        onProfileTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BarberProfilePage()),
          );
        },
      ),
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        onRefresh: _loadAppointments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            if (_showWelcomeBanner) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  UserSession.fullName != null ? 'Welcome ${UserSession.fullName}' : 'Welcome',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._buildCategorizedSections(context),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navButton(
              icon: Icons.event_available,
              isActive: _currentTab == _tabDashboard,
              onTap: () {
                setState(() => _currentTab = _tabDashboard);
              },
            ),
            _navButton(
              icon: Icons.person_outline,
              isActive: _currentTab == _tabProfile,
              onTap: () {
                setState(() => _currentTab = _tabProfile);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BarberProfilePage()),
                );
              },
            ),
            _navButton(
              icon: Icons.menu,
              isActive: _currentTab == _tabMenu,
              onTap: () async {
                setState(() => _currentTab = _tabMenu);
                await showAppMenuSheet(context);
                if (mounted) {
                  setState(() => _currentTab = _tabDashboard);
                }
              },
            ),
          ],
        ),
      ),
    ),
    );
  }

  List<Widget> _buildCategorizedSections(BuildContext context) {
    if (_appointments.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No appointments assigned yet.', style: TextStyle(color: Colors.white70)),
          ),
        ),
      ];
    }

    const order = [
      'Scheduled',
      'CheckedIn',
      'InProgress',
      'Completed',
      'Cancelled',
      'NoShow',
    ];

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final appt in _appointments) {
      final status = (appt['status']?.toString() ?? 'Unknown').trim();
      groups.putIfAbsent(status, () => []);
      groups[status]!.add(appt);
    }

    final statuses = <String>[];
    for (final status in order) {
      if (groups.containsKey(status)) {
        statuses.add(status);
      }
    }
    for (final status in groups.keys) {
      if (!statuses.contains(status)) {
        statuses.add(status);
      }
    }

    final widgets = <Widget>[];
    for (final status in statuses) {
      final items = groups[status] ?? [];
      final isExpanded = _expandedStatus == status;
      widgets.add(
        _statusHeader(
          status: status,
          count: items.length,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              _expandedStatus = isExpanded ? null : status;
            });
          },
        ),
      );
      if (isExpanded) {
        widgets.add(const SizedBox(height: 8));
        widgets.addAll(items.map((appt) => _appointmentTile(context, appt)));
      }
      widgets.add(const SizedBox(height: 14));
    }
    return widgets;
  }

  Widget _statusHeader({
    required String status,
    required int count,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              color: Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white60,
            ),
          ],
        ),
      ),
    );
  }

  Widget _appointmentTile(BuildContext context, Map<String, dynamic> appt) {
    final customerName = appt['customerName']?.toString() ?? 'Customer';
    final date = appt['appointmentDate']?.toString() ?? '';
    final startTime = formatTo12Hour(appt['startTime']?.toString() ?? '');
    final status = appt['status']?.toString() ?? 'Unknown';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BarberAppointmentDetailPage(appointment: appt),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customerName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$date  $startTime',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: $status',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final color = isActive ? Colors.white : Colors.white54;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
          ],
        ),
      ),
    );
  }
}
