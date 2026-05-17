import 'dart:convert';

import 'package:http/http.dart' as http;

import '../user/api_config.dart';

class KioskApi {
  static Future<List<Map<String, dynamic>>> loadServices() async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/kiosk.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'services'}),
    );
    final data = _decode(response);
    return (data['services'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>> loadBarberQueue() async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/kiosk.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'barberQueue'}),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> createWalkin({
    required String guestName,
    required List<int> serviceIds,
    required int barberId,
    required int variantId,
    required String styleName,
    required String scanMode,
    String entryPath = '',
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/kiosk.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'createWalkin',
        'guestName': guestName,
        'serviceIDs': serviceIds,
        'barberID': barberId,
        'variantID': variantId,
        'styleName': styleName,
        'scanMode': scanMode,
        'entryPath': entryPath,
      }),
    );
    return _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Kiosk request failed');
    }
    return data;
  }
}
