import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Resolves where the PHP API lives (XAMPP local vs production Render).
class ApiConfig {
  static const String _apiPath = '/barberyanitatis/tatis_barbershop/api';
  static const String webBaseUrl = 'http://localhost$_apiPath';

  /// Production Render API. Build with either:
  /// `flutter run --dart-define=USE_PRODUCTION_API=true`
  /// or `flutter run --dart-define=API_BASE_URL=https://barberyanitatis.onrender.com`
  static const String productionBaseUrl = 'https://barberyanitatis.onrender.com';

  /// When true (release/testing against live API), uses [productionBaseUrl]
  /// unless [API_BASE_URL] is set explicitly.
  static const bool useProductionApi =
      bool.fromEnvironment('USE_PRODUCTION_API', defaultValue: false);

  /// PC Wi‑Fi IPv4 from `ipconfig` (override: `--dart-define=LAN_HOST=192.168.1.x`).
  /// Update this whenever your PC's LAN IP changes (router DHCP).
  static const String defaultLanHost =
      String.fromEnvironment('LAN_HOST', defaultValue: '192.168.1.3');

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
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (useProductionApi) {
      return productionBaseUrl;
    }
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
    if (useProductionApi) {
      return productionBaseUrl;
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

  static String _imageProxyUrl(String path) {
    final cleaned = path.startsWith('/') ? path : '/$path';
    return '$baseUrl/image_proxy.php?path=${Uri.encodeComponent(cleaned)}';
  }

  static bool _isServerUploadPath(String path) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    return relative.startsWith('uploads/');
  }

  /// Turns DB relative paths (and same-origin /uploads URLs) into a fetchable URL.
  ///
  /// Native production used `{host}/uploads/...` which 404s on Render after the
  /// Storage cutover. `image_proxy.php` reads disk first (XAMPP unchanged), then
  /// Supabase. Flutter `assets/` paths stay bundled on mobile.
  static String resolveImageUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (trimmed.contains('image_proxy.php')) {
      return trimmed;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      for (final origin in <String>[rootUrl, baseUrl, productionBaseUrl]) {
        if (origin.isEmpty || !trimmed.startsWith(origin)) {
          continue;
        }
        var path = trimmed.substring(origin.length);
        final queryAt = path.indexOf('?');
        if (queryAt >= 0) {
          path = path.substring(0, queryAt);
        }
        if (kIsWeb || _isServerUploadPath(path)) {
          return _imageProxyUrl(path);
        }
        return trimmed;
      }
      return trimmed;
    }

    if (!kIsWeb && trimmed.startsWith('assets/')) {
      return trimmed;
    }
    if (kIsWeb || _isServerUploadPath(trimmed)) {
      return _imageProxyUrl(trimmed);
    }
    if (trimmed.startsWith('/')) {
      return '$rootUrl$trimmed';
    }
    return '$rootUrl/$trimmed';
  }
}
