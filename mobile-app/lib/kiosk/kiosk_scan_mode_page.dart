import 'package:flutter/material.dart';

import '../user/ai_face_scan_page.dart';
import '../user/user_session.dart';
import 'kiosk_session.dart';
import 'kiosk_style_pick_page.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// Pick exactly one scan path — mutually exclusive.
class KioskScanModePage extends StatefulWidget {
  const KioskScanModePage({super.key});

  @override
  State<KioskScanModePage> createState() => _KioskScanModePageState();
}

class _KioskScanModePageState extends State<KioskScanModePage> {
  KioskScanMode? _selected;

  void _select(KioskScanMode mode) {
    setState(() => _selected = mode);
  }

  Future<void> _continue() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose one scan option')),
      );
      return;
    }

    KioskSession.scanMode = _selected;
    UserSession.resetScanState();

    if (_selected == KioskScanMode.threeAngle) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AiFaceScanPage(kioskMode: true),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const KioskStylePickPage(livePreviewNext: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: 'How would you like to preview?',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose one option only. You cannot use both for the same visit.',
              style: TextStyle(color: KioskColors.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 20),
            _ModeCard(
              title: '3-angle capture',
              subtitle:
                  'Capture front, left, and right photos. AI analyzes your face, recommends matching styles, and can generate previews when you pick a cut.',
              icon: Icons.photo_camera_outlined,
              selected: _selected == KioskScanMode.threeAngle,
              onTap: () => _select(KioskScanMode.threeAngle),
            ),
            const SizedBox(height: 12),
            _ModeCard(
              title: 'Live preview',
              subtitle: 'Pick a style first, then try it on camera in real time.',
              icon: Icons.videocam_outlined,
              selected: _selected == KioskScanMode.liveOnly,
              onTap: () => _select(KioskScanMode.liveOnly),
            ),
          ],
        ),
      ),
      bottomBar: KioskPrimaryButton(
        label: 'Continue',
        onPressed: _selected == null ? null : _continue,
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1F1F1F) : KioskColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? Colors.white : KioskColors.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? Colors.white : KioskColors.textDim, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? Colors.white : KioskColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: KioskColors.textDim, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? Colors.white : Colors.white38,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
