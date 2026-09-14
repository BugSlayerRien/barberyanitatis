import 'package:flutter/material.dart';

import '../user/app_brand.dart';

/// Shared kiosk colors — same Brilliante tokens as the customer app.
class KioskColors {
  KioskColors._();

  static const background = AppBrand.background;
  static const panel = AppBrand.panel;
  static const panelAlt = AppBrand.surfaceAlt;
  static const border = AppBrand.border;
  static const borderStrong = AppBrand.borderStrong;
  static const textPrimary = AppBrand.text;
  static const textMuted = AppBrand.textMuted;
  static const textDim = AppBrand.textMuted;
  static const accent = AppBrand.accent;
  static const chalk = AppBrand.chalk;

  @Deprecated('Brilliante rebrand — use KioskColors.accent')
  static const gold = AppBrand.accent;
  static const accentTint = AppBrand.accentTint;

  @Deprecated('Brilliante rebrand — use KioskColors.accentTint')
  static const goldTint = AppBrand.accentTint;
  static const accentLine = AppBrand.accentLine;

  @Deprecated('Brilliante rebrand — use KioskColors.accentLine')
  static const goldLine = AppBrand.accentLine;
}

InputDecoration kioskInputDecoration({
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: KioskColors.textMuted),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: KioskColors.panel,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: KioskColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: KioskColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: KioskColors.accent),
    ),
  );
}

BoxDecoration kioskCardDecoration({bool selected = false}) {
  return BoxDecoration(
    color: selected ? KioskColors.accentTint : KioskColors.panel,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(
      color: selected ? KioskColors.accent : KioskColors.border,
      width: selected ? 1.5 : 1,
    ),
  );
}

class KioskPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const KioskPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: AppBrand.primaryButton.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}

class KioskOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const KioskOutlineButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: AppBrand.outlineButton.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
