import 'package:flutter/material.dart';

import '../app_brand.dart';

class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: AppBrand.surface,
      selectedItemColor: AppBrand.gold,
      unselectedItemColor: AppBrand.textMuted,
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedFontSize: 11,
      unselectedFontSize: 10,
      onTap: onTap,
      items: [
        const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        const BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Appointments'),
        BottomNavigationBarItem(
          icon: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppBrand.gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppBrand.gold.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.center_focus_strong, color: Colors.black, size: 26),
          ),
          label: 'AI Scan',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.bookmark_border), label: 'Saved'),
        const BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'Menu'),
      ],
    );
  }
}
