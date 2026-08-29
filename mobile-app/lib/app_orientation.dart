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

  static Future<void> lockForKiosk() async {
    if (kIsWeb) return;
    if (kioskAllowsPortraitRotation()) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      return;
    }
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
