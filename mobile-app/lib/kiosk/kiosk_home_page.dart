import 'package:flutter/material.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBlackColor = Color(0xFF111111);
const Color kOrangeColor = Color(0xFFF37022);

class KioskHomePage extends StatefulWidget {
  const KioskHomePage({super.key});

  @override
  State<KioskHomePage> createState() => _KioskHomePageState();
}

class _KioskHomePageState extends State<KioskHomePage> {
  int _selectedIndex = 0;

  final List<Map<String, String>> _recommendations = [
    {
      'style': 'Textured Crop',
      'score': '0.85',
      'image': 'assets/images/hairstyle_placeholder.png',
    },
    {
      'style': 'Classic Pompadour',
      'score': '0.82',
      'image': 'assets/images/hairstyle_placeholder.png',
    },
    {
      'style': 'Low Taper Fade',
      'score': '0.78',
      'image': 'assets/images/hairstyle_placeholder.png',
    },
    {
      'style': 'Modern Quiff',
      'score': '0.74',
      'image': 'assets/images/hairstyle_placeholder.png',
    },
    {
      'style': 'Crew Cut',
      'score': '0.71',
      'image': 'assets/images/hairstyle_placeholder.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDarkBlackColor,
      body: SafeArea(
        child: Row(
          children: [
            _buildSidebar(context),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildScanPanel(context),
                          const SizedBox(height: 24),
                          _buildRecommendations(context),
                          const SizedBox(height: 24),
                          _buildQueueSummary(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 240,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              CircleAvatar(radius: 18, backgroundColor: kGoldColor, child: Icon(Icons.cut, color: Colors.black)),
              SizedBox(width: 12),
              Text('KIOSK', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 36),
          _buildNavItem(Icons.camera_alt, 'Scan', 0),
          _buildNavItem(Icons.style, 'Recommendations', 1),
          _buildNavItem(Icons.confirmation_number, 'Queue', 2),
          _buildNavItem(Icons.settings, 'Settings', 3),
          const Spacer(),
          Text('Barberya ni Tatis', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: isActive ? kGoldColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? kGoldColor : Colors.white70),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white70,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Row(
        children: [
          const Text(
            'AI Kiosk Dashboard',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.play_arrow, color: Colors.black),
            label: const Text('Start New Scan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGoldColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Current Scan', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Capture a new photo or review the last scan for recommendations.',
                    style: TextStyle(color: Colors.white70)),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.greenAccent),
                    SizedBox(width: 8),
                    Text('Status: Ready', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 160,
            width: 220,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: const Center(
              child: Icon(Icons.camera_alt, color: kGoldColor, size: 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Top Recommendations', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _recommendations
              .map((item) => Container(
                    width: 230,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black,
                          ),
                          child: const Center(
                            child: Icon(Icons.image, color: Colors.white24, size: 42),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(item['style'] ?? '',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Match score: ${item['score']}', style: const TextStyle(color: Colors.white60)),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kGoldColor,
                              side: const BorderSide(color: kGoldColor),
                            ),
                            child: const Text('Select for Try-On'),
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildQueueSummary(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: const [
          Icon(Icons.confirmation_number, color: kOrangeColor, size: 32),
          SizedBox(width: 12),
          Expanded(
            child: Text('Queue Status: 3 customers waiting · Average wait 12 mins',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
