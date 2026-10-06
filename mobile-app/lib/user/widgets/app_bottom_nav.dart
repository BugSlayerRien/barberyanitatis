import 'package:flutter/material.dart';

import '../app_brand.dart';

/// One destination in the bottom bar.
class AppNavDestination {
  final IconData icon;
  final String label;

  /// Lifted out of the bar as a circular action — reserved for the one thing
  /// the screen is really for.
  final bool raised;

  const AppNavDestination({
    required this.icon,
    required this.label,
    this.raised = false,
  });
}

/// The app's bottom navigation, shared by the customer and barber screens.
///
/// This was a stock `BottomNavigationBar` where the only sign of the current
/// page was the icon turning gold — a colour change on a 20px glyph, easy to
/// miss and invisible to anyone who struggles with that hue. The active
/// destination now sits in a pill, so position and shape carry the signal and
/// colour only reinforces it.
///
/// Labels sit *under* their icons and are always shown. An earlier version
/// expanded the label beside the icon only when selected, which overflowed on
/// narrow phones the moment a longer word like "Bookings" was picked.
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Defaults to the customer destinations; the barber app passes its own.
  final List<AppNavDestination> destinations;

  static const List<AppNavDestination> customerDestinations = [
    AppNavDestination(icon: Icons.home_rounded, label: 'Home'),
    AppNavDestination(icon: Icons.calendar_month_rounded, label: 'Bookings'),
    AppNavDestination(icon: Icons.center_focus_strong, label: 'AI Scan', raised: true),
    AppNavDestination(icon: Icons.bookmark_rounded, label: 'Saved'),
    AppNavDestination(icon: Icons.menu_rounded, label: 'Menu'),
  ];

  static const List<AppNavDestination> barberDestinations = [
    AppNavDestination(icon: Icons.event_available_rounded, label: 'Today'),
    AppNavDestination(icon: Icons.calendar_month_rounded, label: 'Calendar'),
    AppNavDestination(icon: Icons.person_rounded, label: 'Profile'),
    AppNavDestination(icon: Icons.menu_rounded, label: 'Menu'),
  ];

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.destinations = customerDestinations,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppBrand.panel,
        border: const Border(top: BorderSide(color: AppBrand.border)),
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
          height: 68,
          child: Row(
            children: List.generate(destinations.length, (index) {
              final destination = destinations[index];

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

class _NavItem extends StatelessWidget {
  final AppNavDestination destination;
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
        borderRadius: BorderRadius.circular(16),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppBrand.accentTint : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? AppBrand.accentLine : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  scale: selected ? 1.1 : 1,
                  child: Icon(
                    destination.icon,
                    size: 22,
                    color: selected ? AppBrand.accent : AppBrand.textSubtle,
                  ),
                ),
                const SizedBox(height: 3),
                // Always visible and under the icon, so the bar's width never
                // depends on which word happens to be selected.
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppBrand.accent : AppBrand.textSubtle,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

/// The raised circular action, used for AI Scan on the customer app.
class _RaisedAction extends StatelessWidget {
  final AppNavDestination destination;
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 46,
                height: 46,
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
                      color: AppBrand.accent.withValues(alpha: selected ? 0.5 : 0.28),
                      blurRadius: selected ? 18 : 11,
                      spreadRadius: selected ? 1 : 0,
                    ),
                  ],
                ),
                child: Icon(destination.icon, color: Colors.black, size: 24),
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppBrand.accent : AppBrand.textSubtle,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
