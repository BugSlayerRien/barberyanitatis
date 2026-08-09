import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Locks device orientation for customer (portrait) vs kiosk (landscape).
class AppOrientation {
  AppOrientation._();

  static Future<void> lockForCustomer() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  static Future<void> lockForKiosk() async {
    if (kIsWeb) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}
