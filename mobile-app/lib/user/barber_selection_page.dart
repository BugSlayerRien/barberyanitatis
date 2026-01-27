import 'package:flutter/material.dart';
import 'calendar_page.dart';
import 'top_picks_page.dart';
import 'appointments_page.dart';
import 'profile_page.dart';

class BarberSelectionPage extends StatefulWidget {
  const BarberSelectionPage({super.key});

  @override
  State<BarberSelectionPage> createState() => _BarberSelectionPageState();
}

class _BarberSelectionPageState extends State<BarberSelectionPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final barbers = [
      {
        'name': 'Anyone Available',
        'specialty': 'FASTEST',
        'initials': 'AA',
        'color': Colors.black,
      },
      {
        'name': 'Mike Chen',
        'specialty': 'Classic & Trendy Styles',
        'initials': 'MC',
        'color': Colors.black,
      },
      {
        'name': 'Emma Rodriguez',
        'specialty': 'Creative Styling',
        'initials': 'ER',
        'color': Colors.black,
      },
      {
        'name': 'Sarah Johnson',
        'specialty': 'Modern Cuts & Color',
        'initials': 'SJ',
        'color': Colors.black,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select Barber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: barbers.length,
        itemBuilder: (context, index) {
          final barber = barbers[index];
          final isAnyoneAvailable = index == 0;

          return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isAnyoneAvailable ? Colors.white : Colors.white10,
                  width: isAnyoneAvailable ? 2 : 1,
                ),
                boxShadow: isAnyoneAvailable
                    ? [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
              ),
                child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: barber['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        barber['initials'] as String,
                        style: const TextStyle(
                          color: Colors.white,
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                barber['name'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isAnyoneAvailable) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'FASTEST',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          barber['specialty'] as String,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action buttons: View stats and Go to calendar
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) => BarberStatsDialog(barberName: barber['name'] as String, todayCuts: barbers[index]['name'] == 'Anyone Available' ? 2 : 0), // Pass a sample 'todayCuts'
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
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => CalendarPage(barberName: barber['name'] as String)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.chevron_right, color: Colors.black, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
        },
      ),
      // Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF1A1A1A),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            // Appointments
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AppointmentsPage()),
            );
          } else if (index == 1) {
            // Haircuts
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TopPicksPage()),
            );
          } else if (index == 2) {
            // Profile
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            );
          } else if (index == 3) {
            // Logout - go back to main
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Appointments'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Haircuts'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Logout'),
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}

class BarberStatsDialog extends StatelessWidget {
  final String barberName;
  final int todayCuts; // Added to pass a more accurate "Cuts today" value

  const BarberStatsDialog({super.key, required this.barberName, this.todayCuts = 2});

  @override
  Widget build(BuildContext context) {
    // This sample data must now align with the visual data in your second image for consistency:
    // Tue and Fri are high (red), Sat is low (green), others are in between (red).
    // The image data: Mon(Med), Tues(High), Wed(Low), Thurs(Med), Fri(High), Sat(Low, Green)
    final data = {
      'Mon': 4, 
      'Tues': 6, // High
      'Wed': 2, 
      'Thurs': 4,
      'Fri': 7, // Highest
      'Sat': 1, // Lowest (Green)
    };
    
    // Use the actual data for the current day, which for this example we'll assume is Monday's data,
    // or use the 'todayCuts' passed in from the calling widget.
    final cutsToday = todayCuts; // Using the value passed in

    final busiest = data.entries.reduce((a, b) => a.value > b.value ? a : b);
    final total = data.values.reduce((a, b) => a + b);
    final maxVal = data.values.reduce((a, b) => a > b ? a : b).toDouble();
    // Maximum height of the bars in pixels (arbitrary unit for scaling)
    const double barMaxHeight = 60.0;

    return Dialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container( // Removed ConstrainedBox and SingleChildScrollView on the Dialog body
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title for the chart
            Text('Day Availability Controls', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            // The Bar Chart
            SizedBox(
              height: barMaxHeight + 30, // Increased height for bar + label
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end, // Align bars to the bottom
                children: data.entries.map((e) {
                  // Scale the bar height proportionally to the max value
                  final barHeight = (e.value / (maxVal == 0 ? 1 : maxVal)) * barMaxHeight;
                  
                  // Color logic to match the image: Green for Saturday (1 cut), Red for the rest.
                  // The original logic was more complex, simplifying to match the visual output.
                  final color = e.key == 'Sat' ? const Color(0xFF4CAF50) : const Color(0xFFE74C3C);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 24,
                        // Use a fixed minimum height of 4.0 for very small values to ensure visibility
                        height: barHeight > 0 ? barHeight : 4.0, 
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                      ),
                      const SizedBox(height: 6),
                      Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16), // Increased spacing for better separation
            // Cuts Today / Total Weekly
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        const Text('Cuts today', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        // Use the correct 'cutsToday' value
                        Text('$cutsToday', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        const Text('Total weekly', style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 8),
                        Text('$total', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Summary Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(children: [
                      const TextSpan(text: 'Busiest Day: ', style: TextStyle(color: Colors.white70)),
                      TextSpan(text: '${busiest.key}\n', style: const TextStyle(color: Colors.white)),
                      const TextSpan(text: 'Total Hours: ', style: TextStyle(color: Colors.white70)),
                      const TextSpan(text: '55 hours', style: TextStyle(color: Colors.white)), // Kept hardcoded 55 hours from original code
                    ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Close Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}