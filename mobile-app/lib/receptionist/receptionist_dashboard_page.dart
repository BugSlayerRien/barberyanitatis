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
      body: _selectedIndex == 0
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
                            ),
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
}

