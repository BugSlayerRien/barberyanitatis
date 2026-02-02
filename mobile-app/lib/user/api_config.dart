import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    return kIsWeb
        ? 'http://localhost/barberyanitatis/tatis_barbershop/api'
        : 'http://10.0.2.2/tatis_barbershop/api';
  }

  static String get rootUrl {
    final base = baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  static String resolveImageUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (url.startsWith('/')) {
      return '$rootUrl$url';
    }
    return '$rootUrl/$url';
  }
}
