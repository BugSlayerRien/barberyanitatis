import 'dart:async';

import 'package:flutter/material.dart';

import '../ai_credit_purchase_page.dart';
import '../app_brand.dart';

/// How many AI previews are left, as a compact pill with a help button.
///
/// Extracted from FaceScanResultsPage so the library and the try-on page show
/// the same control rather than each inventing its own. The library's version
/// was a full-width bar with a sentence and a "Top up" button, which read as a
/// different feature from the pill beside Top picks.
///
/// Deliberately just the icon and the number. The long form -- "3 of 5 free
/// previews used (2 purchased)" -- lives behind the help button, because the
/// count is glanced at constantly and read properly about once.
class PreviewQuotaPill extends StatelessWidget {
  /// The quota map from FaceScanService, or null when none has arrived.
  final Map<String, dynamic>? quota;

  /// True while the first fetch is still in flight. Shows a skeleton rather
  /// than nothing, so the pill cannot silently never appear.
  final bool loading;

  /// False in kiosk mode and for signed-out customers, who cannot buy.
  final bool canPurchase;

  final Future<void> Function() onPurchase;

  const PreviewQuotaPill({
    super.key,
    required this.quota,
    required this.canPurchase,
    required this.onPurchase,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = quota;
    if (data == null) {
      return loading ? const _QuotaPillSkeleton() : const SizedBox.shrink();
    }
    if (data['unlimited'] == true) return const SizedBox.shrink();

    final limit = (data['limit'] as num?)?.toInt();
    final used = (data['used'] as num?)?.toInt();
    if (limit == null || used == null || limit <= 0) {
      return const SizedBox.shrink();
    }

    // Clamped: `used` can legitimately exceed `limit` (previews generated while
    // AI_TRYON_UNLIMITED was on, or before a limit was lowered), and a negative
    // "left" count would be nonsense.
    final remaining = (limit - used).clamp(0, limit);
    final isEmpty = remaining <= 0;
    final accentColor = isEmpty ? Colors.orange.shade200 : Colors.white70;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isEmpty ? const Color(0xFF3A1A10) : const Color(0xFF1A1A1A),
          shape: StadiumBorder(
            side: BorderSide(
              color: isEmpty ? Colors.orange.shade300 : Colors.white24,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canPurchase ? () => unawaited(onPurchase()) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 7, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: accentColor),
                  const SizedBox(width: 5),
                  Text(
                    '$remaining',
                    style: TextStyle(
                      color: isEmpty ? Colors.orange.shade200 : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (canPurchase) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.add_circle, size: 15, color: accentColor),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => unawaited(_showHelp(context, data)),
          icon: const Icon(Icons.help_outline, size: 16, color: Colors.white38),
          tooltip: 'What is this number?',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Future<void> _showHelp(BuildContext context, Map<String, dynamic> data) {
    final limit = (data['limit'] as num?)?.toInt() ?? 0;
    final used = (data['used'] as num?)?.toInt() ?? 0;
    final purchased = (data['purchased'] as num?)?.toInt() ?? 0;
    final free = (limit - purchased).clamp(0, limit);
    final remaining = (limit - used).clamp(0, limit);

    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppBrand.panel,
        shape: RoundedRectangleBorder(
          borderRadius: AppBrand.radiusMd,
          side: const BorderSide(color: AppBrand.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: AppBrand.accent),
            SizedBox(width: 8),
            Text(
              'AI previews',
              style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This number is how many AI hairstyle previews you have left. '
              'Generating a new style uses one.',
              style: const TextStyle(color: AppBrand.textMuted, height: 1.45)
                  .copyWith(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            _helpRow('Previews left', '$remaining'),
            _helpRow('Free allowance', '$free'),
            if (purchased > 0) _helpRow('Purchased', '$purchased'),
            _helpRow('Used so far', '$used'),
            const SizedBox(height: 12),
            const Text(
              'Reopening a style you already generated is free — it does not '
              'use another preview.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: AppBrand.accent),
            child: const Text('Got it'),
          ),
          if (canPurchase)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(onPurchase());
              },
              child: Text(
                'Get ${AiCreditPurchasePage.bundleCredits} more — '
                '₱${AiCreditPurchasePage.bundleAmountPhp.toStringAsFixed(0)}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _helpRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotaPillSkeleton extends StatelessWidget {
  const _QuotaPillSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 26,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.white38,
        ),
      ),
    );
  }
}
