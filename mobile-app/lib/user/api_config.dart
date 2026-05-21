import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Resolves where the PHP API lives (XAMPP) for web vs emulator vs physical phone.
class ApiConfig {
  static const String _apiPath = '/barberyanitatis/tatis_barbershop/api';
  static const String webBaseUrl = 'http://localhost$_apiPath';

  /// PC Wi‑Fi IPv4 from `ipconfig` (override: `--dart-define=LAN_HOST=192.168.1.x`).
  static const String defaultLanHost =
      String.fromEnvironment('LAN_HOST', defaultValue: '192.168.1.4');

  static const String androidEmulatorBaseUrl = 'http://10.0.2.2$_apiPath';
  static String lanBaseUrl(String host) => 'http://$host$_apiPath';

  static String? _cachedBaseUrl;
  static Future<void>? _initFuture;

  /// Call once from `main()` before `runApp` so physical vs emulator URL is correct.
  static Future<void> ensureInitialized() {
    _initFuture ??= _resolveAndCache();
    return _initFuture!;
  }

  static Future<void> _resolveAndCache() async {
    _cachedBaseUrl = await _resolveBaseUrl();
  }

  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (_cachedBaseUrl != null && _cachedBaseUrl!.isNotEmpty) {
      return _cachedBaseUrl!;
    }
    return _resolveBaseUrlSync();
  }

  static String _resolveBaseUrlSync() {
    if (kIsWeb) {
      return webBaseUrl;
    }
    if (Platform.isAndroid) {
      return lanBaseUrl(defaultLanHost);
    }
    if (Platform.isIOS) {
      return lanBaseUrl(defaultLanHost);
    }
    return webBaseUrl;
  }

  static Future<String> _resolveBaseUrl() async {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb) {
      return webBaseUrl;
    }
    if (Platform.isAndroid) {
      try {
        final android = await DeviceInfoPlugin().androidInfo;
        if (!android.isPhysicalDevice) {
          return androidEmulatorBaseUrl;
        }
      } catch (_) {}
      return lanBaseUrl(defaultLanHost);
    }
    if (Platform.isIOS) {
      try {
        final ios = await DeviceInfoPlugin().iosInfo;
        if (!ios.isPhysicalDevice) {
          return webBaseUrl;
        }
      } catch (_) {}
      return lanBaseUrl(defaultLanHost);
    }
    return webBaseUrl;
  }

  static String get rootUrl {
    final base = baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  static String resolveImageUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      if (kIsWeb && url.startsWith(rootUrl)) {
        final path = url.substring(rootUrl.length);
        final cleaned = path.startsWith('/') ? path : '/$path';
        return '$baseUrl/image_proxy.php?path=${Uri.encodeComponent(cleaned)}';
      }
      return url;
    }
    if (url.startsWith('/')) {
      if (kIsWeb) {
        return '$baseUrl/image_proxy.php?path=${Uri.encodeComponent(url)}';
      }
      return '$rootUrl$url';
    }
    if (kIsWeb) {
      return '$baseUrl/image_proxy.php?path=${Uri.encodeComponent('/$url')}';
    }
    return '$rootUrl/$url';
  }
}
