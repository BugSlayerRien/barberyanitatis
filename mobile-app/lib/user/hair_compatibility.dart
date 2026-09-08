import 'package:flutter/material.dart';

import 'user_session.dart';

/// Soft guidance levels for hairstyle vs detected hair texture.
/// Where the texture used for compatibility guidance came from.
enum TextureSource {
  /// Measured by a successful AI face scan.
  scan,

  /// Chosen by the user in onboarding or their profile.
  selfReported,

  /// Unknown -- no scan and no selection.
  none,
}

enum HairCompatibilityLevel {
  recommended,
  possible,
  notRecommended,
}

class HairCompatibilityResult {
  final HairCompatibilityLevel level;
  final String shortLabel;
  final String detailMessage;
  final String userTexture;
  final String styleTexture;

  const HairCompatibilityResult({
    required this.level,
    required this.shortLabel,
    required this.detailMessage,
    required this.userTexture,
    required this.styleTexture,
  });

  bool get isRecommended => level == HairCompatibilityLevel.recommended;
  bool get needsWarning =>
      level == HairCompatibilityLevel.possible ||
      level == HairCompatibilityLevel.notRecommended;
}

/// Classifies Library hairstyles against the user's latest successful AI scan.
/// Soft guidance only — never blocks booking.
class HairCompatibility {
  HairCompatibility._();

  static const _adjacent = <String, Set<String>>{
    'Straight': {'Wavy'},
    'Wavy': {'Straight', 'Curly'},
    'Curly': {'Wavy'},
  };

  /// True when the latest completed/usable scan has a hair texture for claims.
  static bool hasUsableScanTexture() {
    final scan = UserSession.scanForCompatibility;
    if (scan == null) return false;

    final scanUserId = scan['userId'];
    if (scanUserId != null &&
        UserSession.userId != null &&
        scanUserId is num &&
        scanUserId.toInt() != UserSession.userId) {
      return false;
    }

    final texture = normalizeTexture(scan['hairTexture']?.toString());
    if (texture == null) return false;

    // Prefer explicit success flag from analyzeCaptures / results page.
    if (scan['scanSucceeded'] == true) return true;

    final provider =
        (scan['analysisProvider']?.toString() ?? '').trim().toLowerCase();
    // Successful sidecar analysis (or manual tweak after a successful scan).
    if (provider == 'ai-service') return true;
    return false;
  }

  static String? scanTexture() {
    if (!hasUsableScanTexture()) return null;
    return normalizeTexture(
      UserSession.scanForCompatibility?['hairTexture']?.toString(),
    );
  }

  /// Where the texture used for guidance came from.
  ///
  /// Guidance used to require a successful scan, so a user who browsed the
  /// Library without scanning saw no badges at all -- indistinguishable from
  /// "every style suits you". The onboarding picker already collects a texture,
  /// so use that when no scan exists and say which one is being used.
  static TextureSource textureSource() {
    if (scanTexture() != null) return TextureSource.scan;
    if (normalizeTexture(UserSession.preferredHairTexture) != null) {
      return TextureSource.selfReported;
    }
    return TextureSource.none;
  }

  /// Texture to judge styles against: the scan if there is one, else the
  /// user's own selection from onboarding/profile.
  static String? userTexture() {
    return scanTexture() ?? normalizeTexture(UserSession.preferredHairTexture);
  }

  static String? normalizeTexture(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'straight':
        return 'Straight';
      case 'wavy':
        return 'Wavy';
      case 'curly':
      case 'coily':
        return 'Curly';
      default:
        return null;
    }
  }

  /// Returns null when no compatibility claim should be shown.
  static HairCompatibilityResult? evaluateStyle({
    required String? styleHairTexture,
    String? styleName,
  }) {
    final user = userTexture();
    if (user == null) return null;
    final fromScan = textureSource() == TextureSource.scan;
    // Self-reported textures get the same guidance, worded as the user's own
    // answer rather than a measurement.
    final basis = fromScan
        ? 'Your latest scan detected $user hair'
        : 'You told us your hair is $user';

    final style = normalizeTexture(styleHairTexture);
    final name = (styleName ?? '').trim().toLowerCase();

    // Align with api/ai_scan.php length/style penalties for non-curly hair.
    if (user != 'Curly' &&
        (name.contains('afro') ||
            name.contains('dread') ||
            name.contains('twist') ||
            name.contains('locs'))) {
      return HairCompatibilityResult(
        level: HairCompatibilityLevel.notRecommended,
        shortLabel: 'Not recommended for your hair texture',
        detailMessage:
            'This style usually needs curly or coily hair to look as intended. '
            '$basis, so results may not match the preview. '
            'You can still book — your barber can advise in person.',
        userTexture: user,
        styleTexture: style ?? '',
      );
    }

    if (style == null) {
      return HairCompatibilityResult(
        level: HairCompatibilityLevel.possible,
        shortLabel: 'May require styling',
        detailMessage:
            'This cut is not tagged for a specific hair texture. '
            'It can still work with your $user hair, but extra styling or product may be needed.',
        userTexture: user,
        styleTexture: '',
      );
    }

    if (style == user) {
      return HairCompatibilityResult(
        level: HairCompatibilityLevel.recommended,
        shortLabel: 'Recommended for your hair texture',
        detailMessage:
            'This style is tagged for $user hair, matching your latest scan.',
        userTexture: user,
        styleTexture: style,
      );
    }

    if (_adjacent[user]?.contains(style) == true) {
      return HairCompatibilityResult(
        level: HairCompatibilityLevel.possible,
        shortLabel: 'May require styling',
        detailMessage:
            'Your scan detected $user hair, while this style is best for $style hair. '
            'It can still work, but additional styling or treatment may be required.',
        userTexture: user,
        styleTexture: style,
      );
    }

    return HairCompatibilityResult(
      level: HairCompatibilityLevel.notRecommended,
      shortLabel: 'Not recommended for your hair texture',
      detailMessage:
          'Your latest scan detected $user hair, but this style is intended for $style hair. '
          'It may not produce the expected result. You can still continue and discuss options with your barber.',
      userTexture: user,
      styleTexture: style,
    );
  }

  static HairCompatibilityResult? evaluateStyleMap(Map<String, dynamic> style) {
    return evaluateStyle(
      styleHairTexture: style['hairTexture']?.toString() ??
          style['hair_texture']?.toString(),
      styleName: style['name']?.toString() ?? style['style_name']?.toString(),
    );
  }

  /// Soft booking gate. Returns true if the user may continue.
  static Future<bool> confirmBookingIfNeeded(
    BuildContext context,
    HairCompatibilityResult? result,
  ) async {
    if (result == null || !result.needsWarning) return true;

    final isHard = result.level == HairCompatibilityLevel.notRecommended;
    final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: Text(
                isHard ? 'Not the best match' : 'May need extra styling',
                style: const TextStyle(color: Colors.white),
              ),
              content: Text(
                result.detailMessage,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(
                    isHard ? 'Pick another' : 'Go back',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                  child: Text(
                    isHard ? 'Book anyway' : 'Continue',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
    return proceed;
  }
}

/// Compact badge for Library cards / detail.
class HairCompatibilityBadge extends StatelessWidget {
  final HairCompatibilityResult result;
  final bool compact;

  const HairCompatibilityBadge({
    super.key,
    required this.result,
    this.compact = true,
  });

  Color get _accent {
    switch (result.level) {
      case HairCompatibilityLevel.recommended:
        return const Color(0xFF8FD49A);
      case HairCompatibilityLevel.possible:
        return const Color(0xFFE0B35A);
      case HairCompatibilityLevel.notRecommended:
        return const Color(0xFFE07A7A);
    }
  }

  IconData get _icon {
    switch (result.level) {
      case HairCompatibilityLevel.recommended:
        return Icons.check_circle_outline;
      case HairCompatibilityLevel.possible:
        return Icons.info_outline;
      case HairCompatibilityLevel.notRecommended:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _accent;
    return Container(
      width: compact ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              result.shortLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
