import 'dart:convert';

import 'package:http/http.dart' as http;

import '../user/api_config.dart';

class AdminApiService {
  static Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}/$path');

  static Future<Map<String, dynamic>> fetchAnalytics({required String period}) async {
    final response = await http.post(
      _uri('admin_analytics.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'period': period}),
    );
    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to load analytics');
    }
    return data;
  }

  static Future<Map<String, dynamic>> fetchSettings() async {
    final response = await http.get(_uri('admin_settings.php'));
    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to load settings');
    }
    return Map<String, dynamic>.from(data['settings'] as Map? ?? {});
  }

  static Future<Map<String, dynamic>> postAction(Map<String, dynamic> body) async {
    final response = await http.post(
      _uri('admin_settings.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? data['message']?.toString() ?? 'Request failed');
    }
    return data;
  }

  static Future<Map<String, dynamic>> saveSettings({
    required String openTime,
    required String closeTime,
    required bool emailNotificationsEnabled,
    required bool autoBackupEnabled,
    required bool forceMfa,
    String? notificationFromEmail,
  }) async {
    return postAction({
      'action': 'update',
      'openTime': openTime,
      'closeTime': closeTime,
      'emailNotificationsEnabled': emailNotificationsEnabled,
      'autoBackupEnabled': autoBackupEnabled,
      'forceMfa': forceMfa,
      if (notificationFromEmail != null && notificationFromEmail.isNotEmpty)
        'notificationFromEmail': notificationFromEmail,
    });
  }

  static Future<Map<String, dynamic>> downloadBackup() async {
    return postAction({'action': 'downloadBackup'});
  }

  static Future<Map<String, dynamic>> sendTestEmail(String toEmail) async {
    return postAction({'action': 'sendTestEmail', 'toEmail': toEmail});
  }

  static Future<Map<String, dynamic>> processNotifications() async {
    return postAction({'action': 'processNotifications'});
  }
}
