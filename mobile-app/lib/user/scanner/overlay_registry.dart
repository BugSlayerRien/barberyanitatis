import 'package:flutter/material.dart';

import 'overlay_models.dart';

/// Central catalog of hairstyle overlay assets (front / left / right).
class OverlayRegistry {
  OverlayRegistry._();

  static const OverlayImageSet sample = OverlayImageSet(
    front: 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
    left: 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
    right: 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
  );

  static const Map<String, OverlayImageSet> _sets = {
    'blowout taper': OverlayImageSet(
      front: 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
      left: 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
      right: 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
    ),
    'buzz cut': OverlayImageSet(
      front: 'assets/images/overlays/buzz_cut/buzz_cut_front.png',
      left: 'assets/images/overlays/buzz_cut/buzz_cut_left.png',
      right: 'assets/images/overlays/buzz_cut/buzz_cut_right.png',
    ),
    'caesar cut': OverlayImageSet(
      front: 'assets/images/overlays/caesar_cut/caesar_front.png',
      left: 'assets/images/overlays/caesar_cut/caesar_left.png',
      right: 'assets/images/overlays/caesar_cut/caesar_right.png',
    ),
    'crew cut': OverlayImageSet(
      front: 'assets/images/overlays/crew_cut/crew_front.png',
      left: 'assets/images/overlays/crew_cut/crew_left.png',
      right: 'assets/images/overlays/crew_cut/crew_right.png',
    ),
    'curly burst fade': OverlayImageSet(
      front: 'assets/images/overlays/curly_burst_fade/curly_burst_front.png',
      left: 'assets/images/overlays/curly_burst_fade/curly_burst_left.png',
      right: 'assets/images/overlays/curly_burst_fade/curly_burst_right.png',
    ),
    'curly crew cut': OverlayImageSet(
      front: 'assets/images/overlays/curly_crew_cut/curly_crew_front.png',
      left: 'assets/images/overlays/curly_crew_cut/curly_crew_left.png',
      right: 'assets/images/overlays/curly_crew_cut/curly_crew_right.png',
    ),
    'curly drop fade': OverlayImageSet(
      front: 'assets/images/overlays/curly_drop_fade/curly_drop_front.png',
      left: 'assets/images/overlays/curly_drop_fade/curly_drop_left.png',
      right: 'assets/images/overlays/curly_drop_fade/curly_drop_right.png',
    ),
    'curly mid fade': OverlayImageSet(
      front: 'assets/images/overlays/curly_mid_fade/curly_mid_front.png',
      left: 'assets/images/overlays/curly_mid_fade/curly_mid_left.png',
      right: 'assets/images/overlays/curly_mid_fade/curly_mid_right.png',
    ),
    'curly modern mullet': OverlayImageSet(
      front: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_front.png',
      left: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_left.png',
      right: 'assets/images/overlays/curly_modern_mullet/curly_modern_mullet_right.png',
    ),
    'curly taper fade': OverlayImageSet(
      front: 'assets/images/overlays/curly_taper/curly_taper_fade_front.png',
      left: 'assets/images/overlays/curly_taper/curly_taper_fade_left.png',
      right: 'assets/images/overlays/curly_taper/curly_taper_fade_right.png',
    ),
    'edgar cut': OverlayImageSet(
      front: 'assets/images/overlays/edgar_cut/edgar_front.png',
      left: 'assets/images/overlays/edgar_cut/edgar_left.png',
      right: 'assets/images/overlays/edgar_cut/edgar_right.png',
    ),
    'french crop': OverlayImageSet(
      front: 'assets/images/overlays/french_crop/french_crop_front.png',
      left: 'assets/images/overlays/french_crop/french_crop_left.png',
      right: 'assets/images/overlays/french_crop/french_crop_right.png',
    ),
    'low fade': OverlayImageSet(
      front: 'assets/images/overlays/low_fade/low_fade_front.png',
      left: 'assets/images/overlays/low_fade/low_fade_left.png',
      right: 'assets/images/overlays/low_fade/low_fade_right.png',
    ),
    'messy quiff': OverlayImageSet(
      front: 'assets/images/overlays/messy_quiff/messy_quiff_front.png',
      left: 'assets/images/overlays/messy_quiff/messy_quiff_left.png',
      right: 'assets/images/overlays/messy_quiff/messy_quiff_right.png',
    ),
    'modern curtains': OverlayImageSet(
      front: 'assets/images/overlays/modern_curtains/modern_curtains_front.png',
      left: 'assets/images/overlays/modern_curtains/modern_curtains_left.png',
      right: 'assets/images/overlays/modern_curtains/modern_curtains_right.png',
    ),
    'modern mullet': OverlayImageSet(
      front: 'assets/images/overlays/modern_mullet/modern_mullet_front.png',
      left: 'assets/images/overlays/modern_mullet/modern_mullet_left.png',
      right: 'assets/images/overlays/modern_mullet/modern_mullet_right.png',
    ),
    'pompadour': OverlayImageSet(
      front: 'assets/images/overlays/pompadour/pompadour_front.png',
      left: 'assets/images/overlays/pompadour/pompadour_left.png',
      right: 'assets/images/overlays/pompadour/pompadour_right.png',
    ),
    'textured crop': OverlayImageSet(
      front: 'assets/images/overlays/textured_crop/textured_crop_front.png',
      left: 'assets/images/overlays/textured_crop/textured_crop_left.png',
      right: 'assets/images/overlays/textured_crop/textured_crop_right.png',
    ),
    'two block': OverlayImageSet(
      front: 'assets/images/overlays/two_block/two_block_front.png',
      left: 'assets/images/overlays/two_block/two_block_left.png',
      right: 'assets/images/overlays/two_block/two_block_right.png',
    ),
    'wavy burst fade': OverlayImageSet(
      front: 'assets/images/overlays/wavy_burst_fade/wavy_burst_front.png',
      left: 'assets/images/overlays/wavy_burst_fade/wavy_burst_left.png',
      right: 'assets/images/overlays/wavy_burst_fade/wavy_burst_right.png',
    ),
    'wavy fringe': OverlayImageSet(
      front: 'assets/images/overlays/wavy_fringe/wavy_fringe_front.png',
      left: 'assets/images/overlays/wavy_fringe/wavy_fringe_left.png',
      right: 'assets/images/overlays/wavy_fringe/wavy_fringe_right.png',
    ),
    'wavy messy top': OverlayImageSet(
      front: 'assets/images/overlays/wavy_messy_top/wavy_messy_front.png',
      left: 'assets/images/overlays/wavy_messy_top/wavy_messy_left.png',
      right: 'assets/images/overlays/wavy_messy_top/wavy_messy_right.png',
    ),
    'wavy mod cut': OverlayImageSet(
      front: 'assets/images/overlays/wavy_mod_cut/wavy_mod_front.png',
      left: 'assets/images/overlays/wavy_mod_cut/wavy_mod_left.png',
      right: 'assets/images/overlays/wavy_mod_cut/wavy_mod_right.png',
    ),
    'wavy side sweep': OverlayImageSet(
      front: 'assets/images/overlays/wavy_side_sweep/wavy_sweep_front.png',
      left: 'assets/images/overlays/wavy_side_sweep/wavy_sweep_left.png',
      right: 'assets/images/overlays/wavy_side_sweep/wavy_sweep_right.png',
    ),
  };

  static const Map<String, String> _aliases = {
    'curly top fade': 'curly taper fade',
    'curly taper': 'curly taper fade',
    'caesar': 'caesar cut',
    'edgar': 'edgar cut',
    'crew': 'crew cut',
    'quiff': 'messy quiff',
    'messy quiff fade': 'messy quiff',
    'side sweep': 'wavy side sweep',
    'wavy sweep': 'wavy side sweep',
  };

  static const Map<String, OverlayCalibration> calibrations = {
    'blowout taper': OverlayCalibration(
      widthScale: 1.18,
      heightScale: 1.28,
      xOffset: 0,
      yOffset: -0.22,
      hairClipFactor: 0.58,
      visualScale: 1.18,
    ),
    'buzz cut': OverlayCalibration(
      widthScale: 0.96,
      heightScale: 0.94,
      xOffset: 0,
      yOffset: -0.08,
      hairClipFactor: 0.60,
      visualScale: 0.98,
    ),
    'low fade': OverlayCalibration(
      widthScale: 1.04,
      heightScale: 1.06,
      xOffset: 0,
      yOffset: -0.16,
      hairClipFactor: 0.58,
      visualScale: 1.04,
    ),
    'french crop': OverlayCalibration(
      widthScale: 1.06,
      heightScale: 1.08,
      xOffset: 0,
      yOffset: -0.18,
      hairClipFactor: 0.58,
      visualScale: 1.06,
    ),
    'curly taper fade': OverlayCalibration(
      widthScale: 1.10,
      heightScale: 1.12,
      xOffset: 0,
      yOffset: -0.14,
      hairClipFactor: 0.58,
      visualScale: 1.06,
    ),
    'textured crop': OverlayCalibration(
      widthScale: 1.02,
      heightScale: 1.04,
      xOffset: 0,
      yOffset: -0.12,
      hairClipFactor: 0.60,
      visualScale: 1.03,
    ),
    'curly modern mullet': OverlayCalibration(
      widthScale: 1.12,
      heightScale: 1.18,
      xOffset: 0,
      yOffset: -0.16,
      hairClipFactor: 0.59,
      visualScale: 1.08,
    ),
    'pompadour': OverlayCalibration(
      widthScale: 1.14,
      heightScale: 1.22,
      xOffset: 0,
      yOffset: -0.20,
      hairClipFactor: 0.57,
      visualScale: 1.12,
    ),
    'edgar cut': OverlayCalibration(
      widthScale: 1.08,
      heightScale: 1.10,
      xOffset: 0,
      yOffset: -0.16,
      hairClipFactor: 0.58,
      visualScale: 1.06,
    ),
  };

  static List<String> allAssetPaths() {
    final paths = <String>{};
    for (final set in _sets.values) {
      paths.add(set.front);
      paths.add(set.left);
      paths.add(set.right);
    }
    return paths.toList();
  }

  static String normalizeStyleName(String raw) {
    var name = raw.trim().toLowerCase();
    if (name.isEmpty) return name;
    return _aliases[name] ?? name;
  }

  static OverlayImageSet resolve(String styleName) {
    final normalized = normalizeStyleName(styleName);
    if (normalized.isEmpty) return sample;
    if (_sets.containsKey(normalized)) return _sets[normalized]!;

    for (final entry in _sets.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }
    return sample;
  }

  static OverlayCalibration calibrationFor(String styleName) {
    final normalized = normalizeStyleName(styleName);
    for (final entry in calibrations.entries) {
      if (normalized.contains(entry.key) || entry.key.contains(normalized)) {
        return entry.value;
      }
    }
    return OverlayCalibration.defaults;
  }

  /// Yaw hint per captured angle key (front / left / right).
  static double yawForCaptureAngle(String angleKey) {
    switch (angleKey) {
      case 'left':
        return 35;
      case 'right':
        return -35;
      default:
        return 0;
    }
  }

  /// Fallback normalized face box when no detector rect was stored at capture.
  static Rect normalizedFaceFallback(String angleKey) {
    switch (angleKey) {
      case 'left':
        return const Rect.fromLTWH(0.22, 0.14, 0.56, 0.50);
      case 'right':
        return const Rect.fromLTWH(0.22, 0.14, 0.56, 0.50);
      default:
        return const Rect.fromLTWH(0.18, 0.12, 0.64, 0.52);
    }
  }
}
