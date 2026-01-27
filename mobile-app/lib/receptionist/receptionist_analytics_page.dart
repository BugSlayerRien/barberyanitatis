import 'package:flutter/material.dart';
import '../user/ai_updates_page.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);
const Color kCardShadow = Color(0x22000000);

class ReceptionistAnalyticsPage extends StatefulWidget {
  final int walkInsCount;

  const ReceptionistAnalyticsPage({
    super.key,
    required this.walkInsCount,
  });

  @override
  State<ReceptionistAnalyticsPage> createState() => _ReceptionistAnalyticsPageState();
}

class _ReceptionistAnalyticsPageState extends State<ReceptionistAnalyticsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Walk-In Analytics Card
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
                  'AI Walk-In Analytics',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 20),
                // Estimated vs Actual
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ESTIMATED WALK-INS', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 8),
                        const Text('12', style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold, fontSize: 32)),
                        const Text('85% confidence', style: TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('ACTUAL SO FAR', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 8),
                        Text(
                          widget.walkInsCount.toString(),
                          style: const TextStyle(color: Color(0xFF4ECDC4), fontWeight: FontWeight.bold, fontSize: 32),
                        ),
                        const Text('Updated live', style: TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Avg Wait Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AVG WAIT TIME', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 8),
                    const Text('15 min', style: TextStyle(color: Color(0xFFFFA726), fontWeight: FontWeight.bold, fontSize: 24)),
                    const Text('Current estimate', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 24),
                // Peak Hours Prediction
                const Text(
                  'Peak Hours Prediction',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE74C3C).withOpacity(0.5)),
                        ),
                        child: const Text(
                          '11:00 AM - 1:00 PM',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE74C3C).withOpacity(0.5)),
                        ),
                        child: const Text(
                          '3:00 PM - 5:00 PM',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFE74C3C), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // AI Insights
                const Text(
                  'AI Insights',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                _buildInsightItem('Expected busy period starting at 11:00 AM', '90% confidence', const Color(0xFFE74C3C)),
                const SizedBox(height: 8),
                _buildInsightItem('Consider adding extra staff for afternoon rush', '78% confidence', const Color(0xFFFFA726)),
                const SizedBox(height: 8),
                _buildInsightItem('High demand predicted for quick cuts today', '88% confidence', const Color(0xFF4CAF50)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // View AI Updates Button
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AIUpdatesPage()),
                );
              },
              icon: const Icon(Icons.insights),
              label: const Text('VIEW DETAILED AI UPDATES'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightItem(String text, String confidence, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Text(confidence, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
