import 'package:flutter/material.dart';
import 'hairstyle_detail_page.dart';
import 'appointments_page.dart';
import 'profile_page.dart';
import 'dashboard_page.dart';
import 'ai_face_scan_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';

class HaircutsListPage extends StatefulWidget {
  const HaircutsListPage({super.key});

  @override
  State<HaircutsListPage> createState() => _HaircutsListPageState();
}

class _HaircutsListPageState extends State<HaircutsListPage> {
  int _selectedTab = 0;

  final List<Map<String, String>> _recommendedStyles = [
    {
      'name': 'Pixie Cut',
      'description': 'Perfect for your face shape',
      'image': 'assets/images/jeo ai haircut.jpg',
      'details': 'Compliments your oval face shape\nMatches your hair texture\nLow maintenance styling',
      'rating': '★★★★★',
    },
    {
      'name': 'French Crop',
      'description': 'Trending this season',
      'image': 'assets/images/jeo ai haircut.jpg',
      'details': 'Compliments your hair type\nMatches your hair texture\nEasy to maintain and style',
      'rating': '★★★★★',
    },
    {
      'name': 'Mullet',
      'description': 'Al-generous 20 provide scalp features',
      'image': 'assets/images/jeo ai haircut.jpg',
      'details': 'Matches your face shape perfectly\nCompliments your hair type\nEasy to maintain and style',
      'rating': '★★★★★',
    },
  ];

  final List<Map<String, String>> _trendyStyles = [
    {
      'name': 'Modern Fade',
      'description': 'Sharp and clean look',
      'image': 'assets/images/mordern_fade.jpg',
      'details': 'Clean professional appearance\nMatches your hair texture\nRequires regular maintenance',
      'rating': '★★★★☆',
    },
    {
      'name': 'Undercut',
      'description': 'Bold and stylish',
      'image': 'assets/images/amazing_hair.jpg',
      'details': 'High contrast styling\nMatches your hair type\nVersatile styling options',
      'rating': '★★★★☆',
    },
    {
      'name': 'Textured Top',
      'description': 'Casual and trendy',
      'image': 'assets/images/kids_cut.jpg',
      'details': 'Adds volume and texture\nMatches your hair type\nEasy daily styling',
      'rating': '★★★★★',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final styles = _selectedTab == 0 ? _recommendedStyles : _trendyStyles;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // Tabs with gradient
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF37022).withOpacity(0.2), width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: _selectedTab == 0
                              ? const LinearGradient(colors: [Color(0xFFF37022), Color(0xFFFF8C42)])
                              : null,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Recommended',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 0 ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: _selectedTab == 1
                              ? const LinearGradient(colors: [Color(0xFFF37022), Color(0xFFFF8C42)])
                              : null,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Trendy',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 1 ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hairstyle cards grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: styles.length,
              itemBuilder: (context, index) => _hairStyleCard(context, styles[index]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),

      // Persistent bottom navigation
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage()));
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppointmentsPage()));
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AiFaceScanPage()));
          } else if (index == 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Placeholder tab - suggest: Saved styles or Notifications')),
            );
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }

  Widget _hairStyleCard(BuildContext context, Map<String, String> style) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF37022).withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF37022).withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  image: DecorationImage(image: AssetImage(style['image']!), fit: BoxFit.cover),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withOpacity(0.3), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // Title and rating
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(style['name']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(style['description']!, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3)),
                  const SizedBox(height: 8),
                  Text(style['rating']!, style: const TextStyle(color: Color(0xFFF37022), fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
