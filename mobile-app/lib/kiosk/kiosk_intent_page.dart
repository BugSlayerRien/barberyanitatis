import 'package:flutter/material.dart';

import 'kiosk_barber_page.dart';
import 'kiosk_scan_mode_page.dart';
import 'kiosk_session.dart';
import 'kiosk_style_pick_page.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// After guest name: choose scan, catalog, or skip straight to barber queue.
class KioskIntentPage extends StatelessWidget {
  const KioskIntentPage({super.key});

  void _goScan(BuildContext context) {
    KioskSession.entryPath = KioskEntryPath.scanFace;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskScanModePage()),
    );
  }

  void _goCatalog(BuildContext context) {
    KioskSession.entryPath = KioskEntryPath.browseCatalog;
    KioskSession.scanMode = null;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskStylePickPage()),
    );
  }

  void _goKnownStyle(BuildContext context) {
    KioskSession.entryPath = KioskEntryPath.knownStyle;
    KioskSession.scanMode = null;
    KioskSession.selectedVariantId = null;
    KioskSession.selectedStyleName = null;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskBarberPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = KioskSession.guestName ?? 'Guest';

    return KioskScaffold(
      title: 'Hi, $name',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How would you like to get started?',
              style: TextStyle(color: KioskColors.textMuted, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            _IntentCard(
              title: 'Scan face for recommendations',
              subtitle: 'AI suggests styles that suit you. Then choose 3-angle capture or live preview.',
              icon: Icons.face_retouching_natural_outlined,
              onTap: () => _goScan(context),
            ),
            const SizedBox(height: 12),
            _IntentCard(
              title: 'Browse haircut catalog',
              subtitle: 'Pick a style from our library, then join the walk-in queue.',
              icon: Icons.grid_view_rounded,
              onTap: () => _goCatalog(context),
            ),
            const SizedBox(height: 12),
            _IntentCard(
              title: 'I already know what I want',
              subtitle: 'Skip scanning and go straight to barber availability.',
              icon: Icons.schedule_outlined,
              onTap: () => _goKnownStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _IntentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KioskColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: KioskColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: KioskColors.textDim, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
