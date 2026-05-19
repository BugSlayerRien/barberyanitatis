import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String webBaseUrl = 'http://localhost/barberyanitatis/tatis_barbershop/api';
  // Local LAN address for device testing — updated to your Wi-Fi IP (192.168.1.6)
  static const String emulatorBaseUrl = 'http://192.168.1.6/barberyanitatis/tatis_barbershop/api';

  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    return kIsWeb
        ? webBaseUrl
      : emulatorBaseUrl;
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
