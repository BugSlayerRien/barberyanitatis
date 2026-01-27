import 'package:flutter/material.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminAuditPage extends StatefulWidget {
  const AdminAuditPage({super.key});

  @override
  State<AdminAuditPage> createState() => _AdminAuditPageState();
}

class _AdminAuditPageState extends State<AdminAuditPage> {
  late TextEditingController _searchController;
  String _selectedCategory = 'All';
  int _currentPage = 1;

  final List<Map<String, dynamic>> _auditLogs = [
    {
      'timestamp': '12:00:00',
      'user': 'Sarah Johnson',
      'action': 'Reserved',
      'category': 'Customer',
      'categoryColor': const Color(0xFFE74C3C),
    },
    {
      'timestamp': '11:45:30',
      'user': 'Mike Chan',
      'action': 'Updated Schedule',
      'category': 'Receptionist',
      'categoryColor': const Color(0xFFFF9800),
    },
    {
      'timestamp': '11:30:15',
      'user': 'David Rodriguez',
      'action': 'Completed Service',
      'category': 'Barber',
      'categoryColor': const Color(0xFF4CAF50),
    },
    {
      'timestamp': '11:15:00',
      'user': 'Jessica Martinez',
      'action': 'Logged In',
      'category': 'Customer',
      'categoryColor': const Color(0xFFE74C3C),
    },
    {
      'timestamp': '11:00:45',
      'user': 'Emma Wilson',
      'action': 'Booked Appointment',
      'category': 'Customer',
      'categoryColor': const Color(0xFFE74C3C),
    },
  ];

  late List<Map<String, dynamic>> _filteredLogs;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredLogs = _auditLogs;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterLogs(String query) {
    setState(() {
      _filteredLogs = _auditLogs.where((log) {
        final matchesSearch = query.isEmpty ||
            log['user'].toString().toLowerCase().contains(query.toLowerCase()) ||
            log['action'].toString().toLowerCase().contains(query.toLowerCase());
        final matchesCategory =
            _selectedCategory == 'All' || log['category'] == _selectedCategory;
        return matchesSearch && matchesCategory;
      }).toList();
      _currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kDarkBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar
            TextField(
              controller: _searchController,
              onChanged: (value) => _filterLogs(value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search logs by user, action, or details...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white70),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white54),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Filters Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.filter_list, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Filters',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _selectedCategory,
                    dropdownColor: const Color(0xFF111111),
                    style: const TextStyle(color: Colors.white),
                    iconEnabledColor: Colors.white,
                    items: ['All', 'Customer', 'Barber', 'Receptionist', 'Admin']
                        .map((category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedCategory = value);
                        _filterLogs(_searchController.text);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Export Button
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Audit log exported as CSV'),
                    backgroundColor: Color(0xFFE74C3C),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE74C3C),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text(
                'Export CSV',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),

            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'TIMESTAMP',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'USER',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ACTION',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'CATEGORY',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Table Rows
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F0F),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Column(
                children: _filteredLogs.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No logs found',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ]
                    : _filteredLogs.map((log) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white10,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  log['timestamp'],
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  log['user'],
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  log['action'],
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: log['categoryColor'].withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: log['categoryColor'],
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    log['category'],
                                    style: TextStyle(
                                      color: log['categoryColor'],
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Pagination
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${_filteredLogs.length} of ${_auditLogs.length} results',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          if (_currentPage > 1) {
                            setState(() => _currentPage--);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Colors.black),
                        ),
                        child: const Text(
                          'Previous',
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          setState(() => _currentPage++);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Colors.black),
                        ),
                        child: const Text(
                          'Next',
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
