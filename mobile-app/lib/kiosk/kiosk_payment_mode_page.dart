import 'package:flutter/material.dart';

import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// How the guest intends to pay, asked just before they join the queue.
///
/// This records an intention only -- the kiosk never contacts the payment
/// gateway. Staff still take the money, and completing the visit is what
/// writes the actual payment (api/payment_recording.php). The choice is stored
/// on the walk-in row so the till knows what to expect, and so a GCash walk-in
/// is not booked as cash.
class KioskPaymentModePage extends StatefulWidget {
  /// Runs once a mode is chosen. Kept as a callback because the barber page
  /// owns the queue submission and its loading state.
  final Future<void> Function(String mode) onConfirm;
  final bool submitting;

  const KioskPaymentModePage({
    super.key,
    required this.onConfirm,
    this.submitting = false,
  });

  @override
  State<KioskPaymentModePage> createState() => _KioskPaymentModePageState();
}

class _KioskPaymentModePageState extends State<KioskPaymentModePage> {
  String _mode = KioskSession.paymentMode;
  bool _busy = false;

  static const _options = <(String, IconData, String, String)>[
    ('counter', Icons.storefront_outlined, 'Pay at the counter', 'Cash or card with our staff after your haircut.'),
    ('gcash', Icons.qr_code_2, 'Pay with GCash', 'Tell our staff at the counter — they will complete it with you.'),
  ];

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    KioskSession.paymentMode = _mode;
    try {
      await widget.onConfirm(_mode);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || widget.submitting;

    return KioskScaffold(
      title: 'How will you pay?',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'You pay after your haircut. This just tells our staff what to expect.',
              style: TextStyle(color: KioskColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            for (final option in _options) ...[
              _optionCard(
                value: option.$1,
                icon: option.$2,
                title: option.$3,
                subtitle: option.$4,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      bottomBar: KioskPrimaryButton(
        label: 'Join the queue',
        loading: busy,
        onPressed: busy ? null : _confirm,
      ),
    );
  }

  Widget _optionCard({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _mode == value;

    return Material(
      color: selected ? KioskColors.accent.withValues(alpha: 0.10) : KioskColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => setState(() => _mode = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? KioskColors.accent : KioskColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? KioskColors.accent : KioskColors.textMuted, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? KioskColors.textPrimary : KioskColors.textMuted,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: KioskColors.textMuted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: KioskColors.accent, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
