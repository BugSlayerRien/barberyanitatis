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
import 'barber_calendar_page.dart';

class BarberDashboardPage extends StatefulWidget {
  const BarberDashboardPage({super.key});

  @override
  State<BarberDashboardPage> createState() => _BarberDashboardPageState();
}

class _BarberDashboardPageState extends State<BarberDashboardPage> {
  static const int _tabDashboard = 0;
  static const int _tabCalendar = 1;
  static const int _tabProfile = 2;
  static const int _tabMenu = 3;

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
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentTab.clamp(0, 3),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        onTap: (index) async {
          if (index == _tabDashboard) {
            setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabCalendar) {
            setState(() => _currentTab = _tabCalendar);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BarberCalendarPage()),
            );
            if (mounted) setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabProfile) {
            setState(() => _currentTab = _tabProfile);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BarberProfilePage()),
            );
            if (mounted) setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabMenu) {
            setState(() => _currentTab = _tabMenu);
            await showAppMenuSheet(context);
            if (mounted) setState(() => _currentTab = _tabDashboard);
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.event_available),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
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
            child: Text(
              'No appointments assigned yet.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ];
    }

    const upcomingStatuses = ['Scheduled', 'CheckedIn', 'InProgress'];
    const folderStatuses = ['Completed', 'Cancelled', 'NoShow'];

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final appt in _appointments) {
      final status = (appt['status']?.toString() ?? 'Unknown').trim();
      groups.putIfAbsent(status, () => []);
      groups[status]!.add(appt);
    }

    final widgets = <Widget>[];

    // Upcoming appointments are always visible (not tucked into folders).
    final upcoming = <Map<String, dynamic>>[];
    for (final status in upcomingStatuses) {
      upcoming.addAll(groups[status] ?? const []);
    }
    widgets.add(
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          'Upcoming appointments',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    if (upcoming.isEmpty) {
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: const Text(
            'No scheduled appointments right now.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    } else {
      widgets.addAll(upcoming.map((appt) => _appointmentTile(context, appt)));
      widgets.add(const SizedBox(height: 8));
    }

    // Completed / cancelled / no-show stay in collapsible folders.
    for (final status in folderStatuses) {
      final items = groups[status] ?? [];
      if (items.isEmpty) continue;
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

    // Any unexpected status still appears as a folder so nothing is hidden.
    for (final status in groups.keys) {
      if (upcomingStatuses.contains(status) || folderStatuses.contains(status)) {
        continue;
      }
      final items = groups[status] ?? [];
      if (items.isEmpty) continue;
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
    final isGroup = appt['isGroup'] == true;
    final customerName = isGroup
        ? (appt['displayTitle']?.toString() ?? appt['customerName']?.toString() ?? 'Group booking')
        : (appt['customerName']?.toString() ?? 'Customer');
    final date = appt['appointmentDate']?.toString() ?? '';
    final timeRange = appt['timeRange']?.toString() ?? '';
    final startTime = formatTo12Hour(appt['startTime']?.toString() ?? '');
    final scheduleLabel = timeRange.isNotEmpty ? timeRange : startTime;
    final status = appt['status']?.toString() ?? 'Unknown';
    final peopleCount = (appt['peopleCount'] as num?)?.toInt() ?? 1;

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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customerName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      if (isGroup)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA99941).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA99941)),
                          ),
                          child: Text(
                            'Group · $peopleCount',
                            style: const TextStyle(color: Color(0xFFA99941), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$date  $scheduleLabel',
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
}
