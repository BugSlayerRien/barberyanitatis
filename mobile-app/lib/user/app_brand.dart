import 'package:flutter/material.dart';

/// Customer/barber app brand tokens aligned with the web portal gold,
/// without copying the operations dashboard layout.
class AppBrand {
  AppBrand._();

  static const Color gold = Color(0xFFA99941);
  static const Color goldMuted = Color(0xFF8C7F34);
  static const Color goldTint = Color(0x21A99941);
  static const Color goldLine = Color(0x66A99941);

  static const Color background = Color(0xFF08080A);
  static const Color surface = Color(0xFF121216);
  static const Color surfaceAlt = Color(0xFF17171C);
  static const Color panel = Color(0xFF0F0F12);

  static const Color text = Color(0xFFF4F4F6);
  static const Color textMuted = Color(0xFFA2A2AD);

  static const Color border = Color(0x12FFFFFF);
  static const Color borderStrong = Color(0x21FFFFFF);

  static BorderRadius get radiusMd => BorderRadius.circular(12);
  static BorderRadius get radiusLg => BorderRadius.circular(14);

  static BoxDecoration get card => BoxDecoration(
        color: panel,
        borderRadius: radiusMd,
        border: Border.all(color: border),
      );

  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: Colors.black,
        disabledBackgroundColor: gold.withValues(alpha: 0.35),
        disabledForegroundColor: Colors.black54,
        minimumSize: const Size.fromHeight(48),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static ButtonStyle get outlineButton => OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: borderStrong),
        minimumSize: const Size.fromHeight(46),
        backgroundColor: surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );
}

class BrandWordmark extends StatelessWidget {
  final double logoHeight;
  final bool showTagline;

  const BrandWordmark({
    super.key,
    this.logoHeight = 96,
    this.showTagline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/TATIS.png',
          height: logoHeight,
        ),
        SizedBox(height: logoHeight >= 80 ? 10 : 6),
        Text(
          'BARBERYA NI TATIS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: logoHeight >= 110 ? 20 : 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
        if (showTagline) ...[
          const SizedBox(height: 6),
          const Text(
            'AI Hairstyle Recommender',
            style: TextStyle(color: AppBrand.gold, fontSize: 12, letterSpacing: 0.4),
          ),
        ],
      ],
    );
  }
}
