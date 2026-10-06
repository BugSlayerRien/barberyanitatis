import 'package:flutter/material.dart';

import '../app_brand.dart';

/// The customer app's bottom navigation.
///
/// This was a stock `BottomNavigationBar` where the only sign of the current
/// page was the icon turning gold -- a colour change on a 20px glyph, which is
/// easy to miss and invisible to anyone who struggles with that hue. The active
/// destination now gets a pill that slides to it, its icon lifts and its label
/// appears, so position, shape and motion all say where you are rather than
/// colour alone.
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const List<_NavDestination> _destinations = [
    _NavDestination(icon: Icons.home_rounded, label: 'Home'),
    _NavDestination(icon: Icons.calendar_month_rounded, label: 'Bookings'),
    _NavDestination(icon: Icons.center_focus_strong, label: 'AI Scan', raised: true),
    _NavDestination(icon: Icons.bookmark_rounded, label: 'Saved'),
    _NavDestination(icon: Icons.menu_rounded, label: 'Menu'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppBrand.panel,
        border: Border(top: BorderSide(color: AppBrand.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_destinations.length, (index) {
              final destination = _destinations[index];

              return Expanded(
                child: destination.raised
                    ? _RaisedAction(
                        destination: destination,
                        selected: currentIndex == index,
                        onTap: () => onTap(index),
                      )
                    : _NavItem(
                        destination: destination,
                        selected: currentIndex == index,
                        onTap: () => onTap(index),
                      ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final String label;
  final bool raised;

  const _NavDestination({
    required this.icon,
    required this.label,
    this.raised = false,
  });
}

class _NavItem extends StatelessWidget {
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 14 : 10,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              // The pill is the signal. Colour reinforces it; it does not
              // carry it alone.
              color: selected ? AppBrand.accentTint : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppBrand.accentLine : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  scale: selected ? 1.08 : 1,
                  child: Icon(
                    destination.icon,
                    size: 22,
                    color: selected ? AppBrand.accent : AppBrand.textSubtle,
                  ),
                ),
                // The label only shows for the current page, so the bar stays
                // uncluttered and the active one reads as a word, not a glyph.
                ClipRect(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.centerLeft,
                    widthFactor: selected ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Text(
                        destination.label,
                        style: const TextStyle(
                          color: AppBrand.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The AI Scan button, raised out of the bar because it is the thing the app is
/// actually for.
class _RaisedAction extends StatelessWidget {
  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _RaisedAction({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppBrand.accent,
                  selected ? AppBrand.accent : AppBrand.accentFill,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppBrand.accent.withValues(alpha: selected ? 0.55 : 0.3),
                  blurRadius: selected ? 20 : 12,
                  spreadRadius: selected ? 2 : 0,
                ),
              ],
            ),
            child: Icon(
              destination.icon,
              color: Colors.black,
              size: selected ? 27 : 25,
            ),
          ),
        ),
      ),
    );
  }
}
