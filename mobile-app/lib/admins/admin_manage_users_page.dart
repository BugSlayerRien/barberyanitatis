import 'package:flutter/material.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminManageUsersPage extends StatefulWidget {
  const AdminManageUsersPage({super.key});

  @override
  State<AdminManageUsersPage> createState() => _AdminManageUsersPageState();
}

class _AdminManageUsersPageState extends State<AdminManageUsersPage> {
  List<Map<String, dynamic>> users = [
    {
      'id': '001',
      'name': 'Jessica Martinez',
      'email': 'jessica@gmail.com',
      'role': 'Customer',
      'status': 'Active',
      'services': '12 services',
      'avatar': 'JM',
    },
    {
      'id': '002',
      'name': 'Sarah Johnson',
      'email': 'sarah.j@email.com',
      'role': 'Barber',
      'status': 'Active',
      'services': '156 services',
      'avatar': 'SJ',
    },
    {
      'id': '003',
      'name': 'Mike Chan',
      'email': 'mike.chan@email.com',
      'role': 'Receptionist',
      'status': 'Active',
      'services': '0 services',
      'avatar': 'MC',
    },
    {
      'id': '004',
      'name': 'Emma Wilson',
      'email': 'emma.w@email.com',
      'role': 'Customer',
      'status': 'Active',
      'services': '3 services',
      'avatar': 'EW',
    },
    {
      'id': '005',
      'name': 'David Rodriguez',
      'email': 'david@edovisum.com',
      'role': 'Barber',
      'status': 'Active',
      'services': '89 services',
      'avatar': 'DR',
    },
  ];

  String selectedRole = 'All Roles';
  final TextEditingController searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'User Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Cards
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2,
              children: [
                _buildSmallStatCard('Total Users', '5', 'registered user', const Color(0xFF4CAF50)),
                _buildSmallStatCard('Active Users', '4', 'currently active', const Color(0xFF4CAF50)),
                _buildSmallStatCard('Stylists', '2', 'registered staff', const Color(0xFFFF9800)),
                _buildSmallStatCard('Customers', '3', 'client accounts', const Color(0xFFE74C3C)),
              ],
            ),
            const SizedBox(height: 32),
            // Filter and Search Section
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white),
                    ),
                    child: TextField(
                      controller: searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search, color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                      onChanged: (value) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  onSelected: (value) => setState(() => selectedRole = value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'All Roles', child: Text('All Roles')),
                    const PopupMenuItem(value: 'Customer', child: Text('Customer')),
                    const PopupMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                    const PopupMenuItem(value: 'Barber', child: Text('Barber')),
                    const PopupMenuItem(value: 'Admin', child: Text('Admin')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, color: Colors.black, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          selectedRole,
                          style: const TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Users Table/List
            const Text(
              'USERS',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._getFilteredUsers().map((user) => _buildUserCard(user)).toList(),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredUsers() {
    return users.where((user) {
      final matchesSearch = user['name'].toString().toLowerCase().contains(searchController.text.toLowerCase()) ||
          user['email'].toString().toLowerCase().contains(searchController.text.toLowerCase());
      final matchesRole = selectedRole == 'All Roles' || user['role'] == selectedRole;
      return matchesSearch && matchesRole;
    }).toList();
  }

  Widget _buildSmallStatCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kGoldColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                user['avatar'],
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['name'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user['email'],
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () => _showRoleChangeDialog(user),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(user['role']).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _getRoleColor(user['role'])),
                  ),
                  child: Text(
                    user['role'],
                    style: TextStyle(
                      color: _getRoleColor(user['role']),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                user['status'],
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Text(
                user['services'],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user['services'] == '0 services' ? 'staff' : 'bookings',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'Customer':
        return const Color(0xFFE74C3C);
      case 'Barber':
        return const Color(0xFF4CAF50);
      case 'Receptionist':
        return const Color(0xFFFF9800);
      case 'Admin':
        return kGoldColor;
      default:
        return Colors.white;
    }
  }

  void _showRoleChangeDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Change User Role', style: TextStyle(color: Colors.white)),
        content: Text(
          'Select a new role for ${user['name']}',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white70)),
          ),
          ...[
            ('Customer', const Color(0xFFE74C3C)),
            ('Receptionist', const Color(0xFFFF9800)),
            ('Barber', const Color(0xFF4CAF50)),
            ('Admin', kGoldColor),
          ].map((roleData) {
            return ElevatedButton(
              onPressed: () {
                setState(() {
                  user['role'] = roleData.$1;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${user['name']} role changed to ${roleData.$1}')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: roleData.$2,
                foregroundColor: roleData.$1 == 'Admin' ? Colors.black : Colors.white,
              ),
              child: Text(roleData.$1),
            );
          }).toList(),
        ],
      ),
    );
  }
}
