import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brilliante Barbershop brand tokens.
///
/// Derived from the shop mark: white hand-lettering and linework on black,
/// with a barber pole in red, white and blue. White is the mark's dominant
/// voice, so it is also the app's primary action fill. The pole's blue carries
/// active / selected / informational state, and the pole's red is kept for
/// brand ornament and destructive actions so that red never means both
/// "confirm" and "cancel" on the same screen.
///
/// Replaces the previous gold system from Barberya ni Tatis. The `gold*` names
/// survive as deprecated aliases pointing at the new accent, so screens that
/// have not been migrated yet shift toward the new palette instead of
/// stranding on a colour the brand no longer uses.
class AppBrand {
  AppBrand._();

  static const String name = 'Brilliante Barbershop';
  static const String shortName = 'Brilliante';
  static const String locality = 'Baliwag';

  /// Full-colour badge. Falls back to a typographic lockup when absent, so the
  /// app still renders correctly before the artwork is dropped in.
  static const String logoAsset = 'assets/images/brilliante.png';

  // --- Ground -------------------------------------------------------------
  // Deliberately not #000000: pure black smears on OLED during scroll.
  static const Color background = Color(0xFF08080A);
  static const Color panel = Color(0xFF101015);
  static const Color surface = Color(0xFF14141A);
  static const Color surfaceAlt = Color(0xFF1A1A21);
  static const Color surfaceLift = Color(0xFF22222B);

  // --- Type ---------------------------------------------------------------
  /// The mark's white, very slightly warm so it does not glare on black.
  static const Color chalk = Color(0xFFF2F0EC);
  static const Color text = chalk;
  static const Color textMuted = Color(0xFF9E9EAA);
  static const Color textSubtle = Color(0xFF6C6C78);

  // --- Pole ---------------------------------------------------------------
  /// Fill weight. 4.4:1 on [background] — do not set body text in it.
  static const Color poleRed = Color(0xFFD93B30);

  /// Text weight red, 5.6:1 on [background].
  static const Color poleRedText = Color(0xFFE8554A);

  /// Fill weight. 4.9:1 on [background].
  static const Color poleBlue = Color(0xFF3C7DD9);

  /// Text weight blue, 7.7:1 on [background].
  static const Color poleBlueText = Color(0xFF6AA3F0);

  // --- Accent role --------------------------------------------------------
  // What the old gold used to mark: eyebrows, active tabs, selected cards,
  // links, progress. Blue, because red is spoken for.
  static const Color accent = poleBlueText;
  static const Color accentFill = poleBlue;
  static const Color accentTint = Color(0x1F3C7DD9);
  static const Color accentLine = Color(0x5C3C7DD9);

  // --- Status -------------------------------------------------------------
  static const Color success = Color(0xFF5FC98A);
  static const Color successTint = Color(0x1F5FC98A);
  static const Color warning = Color(0xFFE0A23C);
  static const Color warningTint = Color(0x1FE0A23C);
  static const Color danger = poleRedText;
  static const Color dangerTint = Color(0x1FE8554A);

  // --- Hairlines ----------------------------------------------------------
  static const Color border = Color(0x14FFFFFF);
  static const Color borderStrong = Color(0x24FFFFFF);

  // --- Spacing ------------------------------------------------------------
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;

  /// Minimum comfortable tap target. Anything interactive should reach this.
  static const double tapTarget = 48;

  // --- Radius -------------------------------------------------------------
  static BorderRadius get radiusSm => BorderRadius.circular(8);
  static BorderRadius get radiusMd => BorderRadius.circular(12);
  static BorderRadius get radiusLg => BorderRadius.circular(16);
  static BorderRadius get radiusPill => BorderRadius.circular(999);

  // --- Motion -------------------------------------------------------------
  /// Expo-out. Fast departure, long settle — reads as weight rather than speed.
  static const Curve ease = Cubic(0.16, 1, 0.3, 1);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);

  // --- Surfaces -----------------------------------------------------------
  static BoxDecoration get card => BoxDecoration(
        color: surface,
        borderRadius: radiusMd,
        border: Border.all(color: border),
      );

  static BoxDecoration get cardRaised => BoxDecoration(
        color: surface,
        borderRadius: radiusLg,
        border: Border.all(color: borderStrong),
      );

  /// Card that is currently the point of the screen.
  static BoxDecoration get cardAccent => BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF141A24), Color(0xFF11131A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: radiusLg,
        border: Border.all(color: accentLine),
      );

  // --- Controls -----------------------------------------------------------
  /// White on black, the way the mark itself is set.
  static ButtonStyle get primaryButton => ElevatedButton.styleFrom(
        backgroundColor: chalk,
        foregroundColor: const Color(0xFF0B0B0E),
        disabledBackgroundColor: const Color(0xFF2A2A32),
        disabledForegroundColor: const Color(0xFF71717D),
        minimumSize: const Size.fromHeight(tapTarget),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.4),
      );

  static ButtonStyle get outlineButton => OutlinedButton.styleFrom(
        foregroundColor: text,
        side: const BorderSide(color: borderStrong),
        minimumSize: const Size.fromHeight(tapTarget),
        backgroundColor: surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  /// Destructive. Outlined rather than filled so it can never be mistaken for
  /// the primary action, even at a glance.
  static ButtonStyle get dangerButton => OutlinedButton.styleFrom(
        foregroundColor: danger,
        side: const BorderSide(color: Color(0x5CE8554A)),
        minimumSize: const Size.fromHeight(tapTarget),
        backgroundColor: dangerTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  static InputDecoration field(
    String hint, {
    Widget? suffix,
    Widget? prefix,
    String? helperText,
    String? errorText,
  }) {
    OutlineInputBorder line(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: textSubtle),
      helperText: helperText,
      helperStyle: const TextStyle(color: textSubtle, fontSize: 11),
      errorText: errorText,
      errorStyle: const TextStyle(color: danger, fontSize: 11.5),
      filled: true,
      fillColor: panel,
      isDense: false,
      border: line(border),
      enabledBorder: line(border),
      focusedBorder: line(accent, 1.5),
      errorBorder: line(danger),
      focusedErrorBorder: line(danger, 1.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      prefixIcon: prefix,
      suffixIcon: suffix,
    );
  }

  // --- Deprecated: Barberya ni Tatis gold ---------------------------------
  // Kept so unmigrated screens follow the new accent instead of stranding on
  // a colour the brand no longer uses. Remove once every call site is moved.

  @Deprecated('Brilliante rebrand — use AppBrand.accent')
  static const Color gold = accent;
  @Deprecated('Brilliante rebrand — use AppBrand.accentFill')
  static const Color goldMuted = accentFill;
  @Deprecated('Brilliante rebrand — use AppBrand.accentTint')
  static const Color goldTint = accentTint;
  @Deprecated('Brilliante rebrand — use AppBrand.accentLine')
  static const Color goldLine = accentLine;
}

/// The barber pole, drawn rather than loaded.
///
/// The badge artwork is unreadable much below 64px — the arched lettering
/// collapses — so small placements (app bar, chips, empty states) get this
/// instead of a shrunken logo.
class BrilliantePole extends StatelessWidget {
  final double height;

  const BrilliantePole({super.key, this.height = 34});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height * 0.42,
      child: CustomPaint(painter: _PolePainter()),
    );
  }
}

class _PolePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final capH = size.height * 0.13;
    final barrel = Rect.fromLTWH(0, capH, size.width, size.height - (capH * 2));
    final barrelRRect = RRect.fromRectAndRadius(barrel, Radius.circular(size.width * 0.18));

    canvas.save();
    canvas.clipRRect(barrelRRect);
    canvas.drawRect(barrel, Paint()..color = AppBrand.chalk);

    // Diagonal stripes, red then blue, sweeping the length of the barrel.
    final stripe = size.height * 0.15;
    final slant = size.width * 1.15;
    final paint = Paint()..style = PaintingStyle.fill;
    var i = 0;
    for (double y = -slant; y < size.height + slant; y += stripe) {
      paint.color = i.isEven ? AppBrand.poleRed : AppBrand.poleBlue;
      final path = Path()
        ..moveTo(-1, y)
        ..lineTo(size.width + 1, y - slant)
        ..lineTo(size.width + 1, y - slant + (stripe * 0.62))
        ..lineTo(-1, y + (stripe * 0.62))
        ..close();
      canvas.drawPath(path, paint);
      i++;
    }
    canvas.restore();

    canvas.drawRRect(
      barrelRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.07)
        ..color = const Color(0xFF0B0B0E),
    );

    final cap = Paint()..color = AppBrand.chalk;
    final capRadius = Radius.circular(size.width * 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-size.width * 0.08, 0, size.width * 1.16, capH * 1.1), capRadius),
      cap,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-size.width * 0.08, size.height - (capH * 1.1), size.width * 1.16,
              capH * 1.1),
          capRadius),
      cap,
    );
  }

  @override
  bool shouldRepaint(covariant _PolePainter oldDelegate) => false;
}

/// The shop badge, at any size.
///
/// Single place the logo artwork is loaded, so the asset path lives in exactly
/// one constant. Falls back to the drawn pole if the artwork is missing or
/// fails to decode, which keeps every screen rendering either way.
class BrandMark extends StatelessWidget {
  final double size;
  final BoxFit fit;

  const BrandMark({super.key, required this.size, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${AppBrand.name} logo',
      image: true,
      child: Image.asset(
        AppBrand.logoAsset,
        height: size,
        width: size,
        fit: fit,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => BrilliantePole(height: size),
      ),
    );
  }
}

/// Full brand lockup: the badge, and optionally a caption beneath it.
///
/// The badge artwork already contains the wordmark, so this no longer prints
/// the shop name underneath — that repetition read as a stutter. Pass
/// [tagline] for a caption, or [showTagline] for the product one.
class BrandWordmark extends StatelessWidget {
  final double logoHeight;
  final bool showTagline;
  final String? tagline;

  const BrandWordmark({
    super.key,
    this.logoHeight = 96,
    this.showTagline = false,
    this.tagline,
  });

  @override
  Widget build(BuildContext context) {
    final caption = tagline ?? (showTagline ? 'AI Hairstyle Recommender' : null);
    return Semantics(
      label: '${AppBrand.name} logo',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            AppBrand.logoAsset,
            height: logoHeight,
            errorBuilder: (_, __, ___) => _TypographicLockup(height: logoHeight),
          ),
          if (caption != null) ...[
            SizedBox(height: logoHeight >= 80 ? AppBrand.s3 : AppBrand.s2),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppBrand.accent,
                fontSize: 12,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Stand-in lockup used until `brilliante.png` is added, and as the permanent
/// fallback if the asset ever fails to decode.
class _TypographicLockup extends StatelessWidget {
  final double height;

  const _TypographicLockup({required this.height});

  @override
  Widget build(BuildContext context) {
    final scale = (height / 104).clamp(0.55, 1.35);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrilliantePole(height: height * 0.52),
        SizedBox(height: height * 0.1),
        Text(
          'BRILLIANTE',
          style: TextStyle(
            color: AppBrand.chalk,
            fontSize: 22 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 3.2 * scale,
            height: 1,
          ),
        ),
        SizedBox(height: height * 0.045),
        Text(
          'BARBERSHOP',
          style: TextStyle(
            color: AppBrand.textMuted,
            fontSize: 10.5 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: 6.0 * scale,
            height: 1,
          ),
        ),
      ],
    );
  }
}
