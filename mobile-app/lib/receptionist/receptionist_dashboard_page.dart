import 'package:flutter/material.dart';
import '../user/auth_page.dart';

import 'receptionist_analytics_page.dart';
import 'receptionist_appointments_page.dart';
import 'receptionist_walkins_page.dart';
import 'receptionist_tracking_page.dart';
import 'receptionist_barbers_page.dart';

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

  List<Map<String, dynamic>> _todayAppointments = [
    {
      'initials': 'JD',
      'name': 'Jessica Davis',
      'service': 'Precision Cut & Style',
      'time': '10:00 AM',
      'duration': '90 min',
      'price': '₱100',
      'status': 'CONFIRMED',
      'barber': 'Mike Chen',
    },
    {
      'initials': 'MR',
      'name': 'Maria Rodriguez',
      'service': 'Color Transformation',
      'time': '2:00 PM',
      'duration': '180 min',
      'price': '₱150',
      'status': 'PENDING',
      'barber': 'Sarah Johnson',
    },
    {
      'initials': 'SJ',
      'name': 'Sarah Johnson',
      'service': 'Luxury Treatment',
      'time': '5:00 PM',
      'duration': '120 min',
      'price': '₱200',
      'status': 'CONFIRMED',
      'barber': 'Emma Rodriguez',
    },
  ];

  List<Map<String, dynamic>> _walkIns = [];

  final List<Map<String, dynamic>> _barbers = [
    {'initials': 'MC', 'name': 'Mike Chen', 'specialty': 'Precision Cuts', 'rating': 4.9, 'experience': '8 years'},
    {'initials': 'SJ', 'name': 'Sarah Johnson', 'specialty': 'Color Expert', 'rating': 4.8, 'experience': '6 years'},
    {'initials': 'ER', 'name': 'Emma Rodriguez', 'specialty': 'Styling Specialist', 'rating': 4.7, 'experience': '5 years'},
  ];

  final List<Map<String, dynamic>> _trackingData = [
    {
      'initials': 'AB',
      'name': 'Alex Brown',
      'service': 'Haircut & Styling',
      'status': 'IN PROGRESS',
      'progress': 0.65,
      'timeRemaining': '15 min remaining',
      'color': const Color(0xFF4CAF50),
    },
    {
      'initials': 'JW',
      'name': 'Jessica White',
      'service': 'Color Treatment',
      'status': 'WAITING',
      'progress': 0.0,
      'timeRemaining': 'Waiting',
      'color': const Color(0xFF2196F3),
    },
    {
      'initials': 'MJ',
      'name': 'Michael Johnson',
      'service': 'Beard Trim',
      'status': 'COMPLETED',
      'progress': 1.0,
      'timeRemaining': 'Completed',
      'color': const Color(0xFF9E9E9E),
    },
  ];

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) {
        return;
      }
      setState(() => _initialLoading = false);
    });
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
      ),
      body: _initialLoading ? _buildInitialSkeleton() : _buildCurrentBody(),
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
                onStatusChanged: (appointment) {
                  setState(() {});
                },
                onAppointmentRemoved: (appointment) {
                  setState(() {
                    _todayAppointments.remove(appointment);
                  });
                },
              )
            : _selectedIndex == 2
                ? ReceptionistWalkInsPage(
                    walkIns: _walkIns,
                    onWalkInAdded: (walkIn) {
                      setState(() {
                        _walkIns.add(walkIn);
                      });
                    },
                  )
                : _selectedIndex == 3
                    ? ReceptionistTrackingPage(trackingData: _trackingData)
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
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skeletonBox(height: 18, width: 170),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _skeletonStatBlock(),
                    _skeletonStatBlock(),
                  ],
                ),
                const SizedBox(height: 20),
                _skeletonBox(height: 14, width: 110),
                const SizedBox(height: 10),
                _skeletonBox(height: 24, width: 90),
                const SizedBox(height: 18),
                _skeletonBox(height: 14, width: 150),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _skeletonChip()),
                    const SizedBox(width: 8),
                    Expanded(child: _skeletonChip()),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 210,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonStatBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBox(height: 10, width: 84),
        const SizedBox(height: 8),
        _skeletonBox(height: 28, width: 54),
        const SizedBox(height: 6),
        _skeletonBox(height: 10, width: 74),
      ],
    );
  }

  Widget _skeletonChip() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _skeletonBox({required double height, double? width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

