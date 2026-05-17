import 'dart:async';

import 'package:flutter/material.dart';

import '../user/auth_page.dart';
import 'receptionist_analytics_page.dart';
import 'receptionist_appointments_page.dart';
import 'receptionist_api.dart';
import 'receptionist_barbers_page.dart';
import 'receptionist_tracking_page.dart';
import 'receptionist_walkins_page.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);
const Color kCardShadow = Color(0x22000000);

class ReceptionistDashboardPage extends StatefulWidget {
  const ReceptionistDashboardPage({super.key});

  @override
  State<ReceptionistDashboardPage> createState() => _ReceptionistDashboardPageState();
}

class _ReceptionistDashboardPageState extends State<ReceptionistDashboardPage> {
  int _selectedIndex = 0;
  bool _initialLoading = true;
  String? _error;
  Timer? _refreshTimer;

  List<Map<String, dynamic>> _todayAppointments = [];
  List<Map<String, dynamic>> _walkIns = [];
  List<Map<String, dynamic>> _trackingData = [];

  final List<Map<String, dynamic>> _barbers = [
    {'initials': 'MC', 'name': 'Mike Chen', 'specialty': 'Precision Cuts', 'rating': 4.9, 'experience': '8 years'},
    {'initials': 'SJ', 'name': 'Sarah Johnson', 'specialty': 'Color Expert', 'rating': 4.8, 'experience': '6 years'},
    {'initials': 'ER', 'name': 'Emma Rodriguez', 'specialty': 'Styling Specialist', 'rating': 4.7, 'experience': '5 years'},
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => _loadDashboard(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _initialLoading = true;
        _error = null;
      });
    }

    try {
      final data = await ReceptionistApi.loadDashboard();
      final appointments = ReceptionistApi.mapAppointments(
        data['appointments'] as List<dynamic>? ?? const [],
      );
      final walkIns = (data['walkins'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .map((row) {
            final name = row['name']?.toString() ?? 'Walk-in';
            return {
              ...row,
              'initials': name.length >= 2 ? name.substring(0, 2).toUpperCase() : 'W',
              'service': row['service']?.toString() ?? 'Walk-in',
              'waitTime': row['waitTime']?.toString() ?? '',
            };
          })
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _todayAppointments = appointments;
        _walkIns = walkIns;
        _trackingData = ReceptionistApi.buildTrackingData(appointments, walkIns);
        _initialLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _initialLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        backgroundColor: kDarkBackground,
        elevation: 0,
        title: const Text(
          'RECEPTIONIST DASHBOARD',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _loadDashboard(),
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
      body: _initialLoading
          ? _buildInitialSkeleton()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _loadDashboard,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildCurrentBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex > 4 ? 0 : _selectedIndex,
        onTap: (index) {
          if (index == 5) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AuthPage()),
            );
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        backgroundColor: kDarkBackground,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        elevation: 20,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.insights), label: 'AI ANALYTICS'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'APPOINTMENTS'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'WALK-INS'),
          BottomNavigationBarItem(icon: Icon(Icons.location_searching), label: 'TRACKING'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'BARBERS'),
          BottomNavigationBarItem(icon: Icon(Icons.logout), label: 'LOGOUT'),
        ],
      ),
    );
  }

  Widget _buildCurrentBody() {
    return _selectedIndex == 0
        ? ReceptionistAnalyticsPage(walkInsCount: _walkIns.length)
        : _selectedIndex == 1
            ? ReceptionistAppointmentsPage(
                appointments: _todayAppointments,
                onStatusChanged: (_) => _loadDashboard(silent: true),
                onAppointmentRemoved: (_) => _loadDashboard(silent: true),
              )
            : _selectedIndex == 2
                ? ReceptionistWalkInsPage(
                    walkIns: _walkIns,
                    onWalkInAdded: (_) => _loadDashboard(silent: true),
                  )
                : _selectedIndex == 3
                    ? ReceptionistTrackingPage(
                        appointments: _todayAppointments,
                        walkIns: _walkIns,
                        onChanged: () => _loadDashboard(silent: true),
                      )
                    : _selectedIndex == 4
                        ? ReceptionistBarbersPage(barbers: _barbers)
                        : const Center(
                            child: Text(
                              'Logging out...',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
  }

  Widget _buildInitialSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skeletonBox(height: 14, width: 220),
          const SizedBox(height: 14),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonBox({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
