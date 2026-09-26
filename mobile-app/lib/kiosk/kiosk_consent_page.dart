import 'package:flutter/material.dart';

import '../user/terms_and_conditions_page.dart';
import 'kiosk_guest_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// Terms gate for a walk-in, shown before anything is captured.
///
/// Per use, not per device: the mobile app can remember that an account
/// accepted the terms, but a kiosk serves a different person every time, so a
/// stored flag would be someone else's agreement. [KioskSession.reset] clears
/// it, and the acceptance is written to the walk-in row when the guest joins
/// the queue (api/kiosk.php createWalkin) -- nothing exists in the database
/// before that point to attach it to.
class KioskConsentPage extends StatefulWidget {
  const KioskConsentPage({super.key});

  @override
  State<KioskConsentPage> createState() => _KioskConsentPageState();
}

class _KioskConsentPageState extends State<KioskConsentPage> {
  bool _agreed = false;

  static const _points = <(IconData, String, String)>[
    (
      Icons.photo_camera_outlined,
      'We take three photos',
      'Front, left and right, used to suggest haircuts that suit your face.',
    ),
    (
      Icons.auto_awesome_outlined,
      'A preview is generated',
      'Your photos power an AI preview of the style you pick.',
    ),
    (
      Icons.timer_outlined,
      'Only for this visit',
      'A walk-in is not an account. This session ends when you finish here.',
    ),
  ];

  void _continue() {
    KioskSession.consentAccepted = true;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskGuestPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: 'Before we start',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Using the kiosk means agreeing to how your photos are handled.',
              style: TextStyle(color: KioskColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            for (final point in _points) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: KioskColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(point.$1, color: KioskColors.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          point.$2,
                          style: const TextStyle(
                            color: KioskColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          point.$3,
                          style: const TextStyle(
                            color: KioskColors.textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            const SizedBox(height: 4),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _agreed = !_agreed),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreed,
                        onChanged: (value) => setState(() => _agreed = value ?? false),
                        activeColor: KioskColors.accent,
                        checkColor: Colors.black,
                        side: const BorderSide(color: KioskColors.textMuted),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'I agree to the Terms and Conditions.',
                            style: TextStyle(
                              color: _agreed ? KioskColors.textPrimary : KioskColors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
                );
              },
              child: const Text(
                'Read the full Terms and Conditions',
                style: TextStyle(color: KioskColors.accent),
              ),
            ),
          ],
        ),
      ),
      bottomBar: KioskPrimaryButton(
        label: 'Agree and continue',
        onPressed: _agreed ? _continue : null,
      ),
    );
  }
}
