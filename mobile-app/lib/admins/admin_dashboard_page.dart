import 'package:flutter/material.dart';
import '../user/auth_page.dart';
import 'admin_manage_users_page.dart';
import 'admin_audit_page.dart';
import 'admin_analytics_page.dart';
import 'admin_manage_services_page.dart';
import 'admin_settings_page.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: _selectedTab == 0 ? _buildDashboardContent() : _selectedTab == 1 ? const AdminManageUsersPage() : _selectedTab == 2 ? const AdminAuditPage() : _selectedTab == 3 ? const AdminAnalyticsPage() : _selectedTab == 4 ? const AdminManageServicesPage() : _selectedTab == 5 ? const AdminSettingsPage() : _selectedTab == 6 ? const AuthPage() : Container(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F0F0F),
          currentIndex: _selectedTab,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            if (index == 6) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const AuthPage()),
              );
            } else {
              setState(() => _selectedTab = index);
            }
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined, color: _selectedTab == 0 ? Colors.white : Colors.grey),
              label: 'DASHBOARD',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_outline, color: _selectedTab == 1 ? Colors.white : Colors.grey),
              label: 'MANAGE USERS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined, color: _selectedTab == 2 ? Colors.white : Colors.grey),
              label: 'AUDIT',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.analytics_outlined, color: _selectedTab == 3 ? Colors.white : Colors.grey),
              label: 'ANALYTICS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.design_services_outlined, color: _selectedTab == 4 ? Colors.white : Colors.grey),
              label: 'MANAGE SERVICES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, color: _selectedTab == 5 ? Colors.white : Colors.grey),
              label: 'SYSTEM SETTINGS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.logout, color: _selectedTab == 6 ? Colors.white : Colors.grey),
              label: 'LOGOUT',
            ),
          ],
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.0,
            children: [
              _buildStatCard(
                title: 'Total Users',
                value: '1,247',
                change: '+12% from last month',
                changeColor: const Color(0xFF4CAF50),
              ),
              _buildStatCard(
                title: 'Active Services',
                value: '12',
                change: '2 new this week',
                changeColor: const Color(0xFF4CAF50),
              ),
              _buildStatCard(
                title: 'Monthly Revenue',
                value: '₱45,680',
                change: '+8% from last month',
                changeColor: const Color(0xFF4CAF50),
              ),
              _buildStatCard(
                title: 'Pending Appointments',
                value: '23',
                change: 'Requires attention',
                changeColor: const Color(0xFFFF9800),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Recent Activity Section
          const Text(
            'Recent Activity',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          _buildActivityCard(
            icon: Icons.person_add,
            iconColor: const Color(0xFFE74C3C),
            title: 'New user registration',
            description: 'Jessica Martinez registered 5 minutes ago',
            time: 'JUST NOW',
          ),
          const SizedBox(height: 12),
          _buildActivityCard(
            icon: Icons.payment,
            iconColor: const Color(0xFFE74C3C),
            title: 'Payment received',
            description: '\$750 payment for luxury treatment',
            time: '15 min ago',
          ),
          const SizedBox(height: 12),
          _buildActivityCard(
            icon: Icons.event_available,
            iconColor: const Color(0xFFE74C3C),
            title: 'Service booking',
            description: 'Color transformation booked for tomorrow',
            time: '1 hour ago',
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String change,
    required Color changeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            change,
            style: TextStyle(
              color: changeColor,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String time,
  }) {
    return Container(
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(icon, color: Colors.black, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.white70.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
