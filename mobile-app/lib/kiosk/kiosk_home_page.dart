import 'package:flutter/material.dart';

import 'kiosk_guest_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

class KioskHomePage extends StatelessWidget {
  const KioskHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      showBack: false,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/TATIS.png', height: 100),
                const SizedBox(height: 20),
                const Text(
                  'Walk-In Kiosk',
                  style: TextStyle(
                    color: KioskColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Get a haircut recommendation, pick your barber, and join the queue — no account needed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: KioskColors.textMuted, fontSize: 15, height: 1.45),
                ),
                const SizedBox(height: 36),
                KioskPrimaryButton(
                  label: 'Start walk-in',
                  onPressed: () {
                    KioskSession.reset();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const KioskGuestPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
