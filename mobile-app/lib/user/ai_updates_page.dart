import 'package:flutter/material.dart';
import 'app_brand.dart';

const Color kGoldColor = AppBrand.accent;
const Color kDarkBackground = Color(0xFF0A0A0A);

class AIUpdatesPage extends StatefulWidget {
  const AIUpdatesPage({super.key});

  @override
  State<AIUpdatesPage> createState() => _AIUpdatesPageState();
}

class _AIUpdatesPageState extends State<AIUpdatesPage> {
  String _selectedTab = 'TODAY';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'AI Updates',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'REC',
                        style: TextStyle(
                          color: Colors.black,
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
                        const Text(
                          'Receptionist',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'AI Analytics Dashboard',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('View profile')),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('View'),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Settings')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.settings, color: Colors.black, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // AI Updates Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Updates',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Real-time insights into AI managed appointment operations',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  // Tab Selection
                  Row(
                    children: [
                      _buildTabButton('TODAY'),
                      const SizedBox(width: 8),
                      _buildTabButton('THIS WEEK'),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.refresh, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          const Text(
                            'Last updated: 2 minutes ago',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Stats
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('TOTAL APPOINTMENTS', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 8),
                          Text(
                            _selectedTab == 'TODAY' ? '14' : '87',
                            style: const TextStyle(color: kGoldColor, fontWeight: FontWeight.bold, fontSize: 32),
                          ),
                          Text(
                            _selectedTab == 'TODAY' ? '+3 from yesterday' : '+12 from last week',
                            style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 10),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('AI MANAGED', style: TextStyle(color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 8),
                          Text(
                            _selectedTab == 'TODAY' ? '18' : '92',
                            style: const TextStyle(color: Color(0xFF4ECDC4), fontWeight: FontWeight.bold, fontSize: 32),
                          ),
                          Text(
                            _selectedTab == 'TODAY' ? '75% automation rate' : '68% automation rate',
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 20),
                  // AI Operations Summary
                  const Text(
                    'AI Operations Summary',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  _buildOperationItem('Auto-Reschedules', 'Handled seamlessly by AI', '7', const Color(0xFF9B59B6)),
                  const SizedBox(height: 10),
                  _buildOperationItem('Cancellation Management', 'Slots rescheduled automatically', '4', const Color(0xFFE74C3C)),
                  const SizedBox(height: 10),
                  _buildOperationItem('Waitlist Fills', 'Cancelled slots reassigned', '3', const Color(0xFFFFA726)),
                  const SizedBox(height: 10),
                  _buildOperationItem('Smart Notifications', 'Automated client updates sent', '22', const Color(0xFF3498DB)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Recent AI Actions Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent AI Actions',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  _buildActionItem(
                    'Rescheduled Maria Rodriguez',
                    '2:00 PM to 3:30 PM due to stylist availability',
                    '2 minutes ago',
                    const Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 12),
                  _buildActionItem(
                    'Filled Cancelled Slot',
                    'Moved Jessica from waitlist to 11:00 AM slot',
                    '15 minutes ago',
                    const Color(0xFF3498DB),
                  ),
                  const SizedBox(height: 12),
                  _buildActionItem(
                    'Sent Reminder Notifications',
                    '5 clients notified about tomorrow\'s appointments',
                    '28 minutes ago',
                    const Color(0xFFFFA726),
                  ),
                  const SizedBox(height: 12),
                  _buildActionItem(
                    'Optimized Schedule',
                    'Reduced gaps by 45 minutes for Mike Chen',
                    '1 hour ago',
                    const Color(0xFF9B59B6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // AI Efficiency Metrics Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI Efficiency Metrics',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard('RESPONSE TIME', '1.2s', 'Average', const Color(0xFF4ECDC4)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard('SUCCESS RATE', '97.8%', '114 week', const Color(0xFF4CAF50)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard('TIME SAVED', '4.2h', 'Daily average', const Color(0xFFFFA726)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard('REVENUE IMPACT', '₱2.1K', 'This week', const Color(0xFFE74C3C)),
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

  Widget _buildTabButton(String label) {
    final isSelected = _selectedTab == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white30,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildOperationItem(String title, String subtitle, String count, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color),
            ),
            child: Text(
              count,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(String title, String description, String time, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              description,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              time,
              style: TextStyle(color: color, fontSize: 10, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 9),
          ),
        ],
      ),
    );
  }
}
