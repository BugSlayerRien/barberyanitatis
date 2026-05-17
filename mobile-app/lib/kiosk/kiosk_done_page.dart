import 'package:flutter/material.dart';

import 'kiosk_home_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

class KioskDonePage extends StatelessWidget {
  final Map<String, dynamic> queueResult;

  const KioskDonePage({super.key, required this.queueResult});

  @override
  Widget build(BuildContext context) {
    final queueNumber = queueResult['queueNumber']?.toString() ?? '';
    final waitLabel = queueResult['waitLabel']?.toString() ?? '';
    final guestName = queueResult['guestName']?.toString() ?? KioskSession.guestName ?? '';

    return KioskScaffold(
      showBack: false,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 72),
                const SizedBox(height: 20),
                Text(
                  'You\'re in the queue, $guestName!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: KioskColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: KioskColors.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white),
                  ),
                  child: Column(
                    children: [
                      const Text('Queue number', style: TextStyle(color: KioskColors.textDim, fontSize: 13)),
                      const SizedBox(height: 8),
                      Text(
                        queueNumber,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      if (waitLabel.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          waitLabel,
                          style: const TextStyle(color: KioskColors.textMuted, fontSize: 16),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please have a seat. We\'ll call you when your barber is ready.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: KioskColors.textDim, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomBar: KioskPrimaryButton(
        label: 'Done — next guest',
        onPressed: () {
          KioskSession.reset();
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const KioskHomePage()),
            (_) => false,
          );
        },
      ),
    );
  }
}
