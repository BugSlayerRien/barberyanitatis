import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Locks device orientation for customer (portrait) vs kiosk.
///
/// Raspberry Pi kiosk displays (7" 800×480 and larger) stay landscape-only.
/// Phones running the same kiosk APK can rotate so portrait layouts work.
class AppOrientation {
  AppOrientation._();

  /// Below a 7" Pi panel (shortest side 480). Typical phones are 360–430.
  static const double kioskLandscapeMinShortestSide = 480;

  static double kioskShortestSideLogical() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return kioskLandscapeMinShortestSide;
    }
    return views.first.physicalSize.shortestSide / views.first.devicePixelRatio;
  }

  /// Phones may rotate; Raspberry Pi panels stay landscape-only.
  static bool kioskAllowsPortraitRotation() {
    return kioskShortestSideLogical() < kioskLandscapeMinShortestSide;
  }

  static bool kioskShouldLockCaptureToLandscape() {
    return !kioskAllowsPortraitRotation();
  }

  static Future<void> lockForCustomer() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  /// Kiosk rotates freely.
  ///
  /// Previously this pinned Pi-sized panels to landscape. That branch bought
  /// nothing — a fixed panel never rotates regardless of what is permitted —
  /// while making a portrait-mounted panel unusable. Allowing all four lets the
  /// scanner follow however the hardware is actually installed; the ML Kit
  /// rotation is recomputed per frame from [DeviceOrientationTracker], so the
  /// detector keeps up with the change.
  static Future<void> lockForKiosk() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
