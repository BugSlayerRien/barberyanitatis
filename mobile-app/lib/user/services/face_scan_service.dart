import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';

class FaceScanService {
  static const String _consentKey = 'face_scan_consent_accepted_v1';

  static bool isValidJpeg(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }

  static ({bool ok, String? error}) validateCaptures(Map<String, String> captures) {
    const required = ['front', 'right', 'left'];
    for (final angle in required) {
      final raw = captures[angle];
      if (raw == null || raw.trim().isEmpty) {
        return (ok: false, error: 'Missing $angle capture.');
      }
      try {
        final bytes = base64Decode(raw);
        if (!isValidJpeg(bytes)) {
          return (ok: false, error: '$angle capture is not a valid JPEG. Please retake.');
        }
        if (bytes.length < 8000) {
          return (ok: false, error: '$angle capture looks too small. Please retake with better lighting.');
        }
      } catch (_) {
        return (ok: false, error: '$angle capture could not be decoded.');
      }
    }
    return (ok: true, error: null);
  }

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> saveConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
  }

  static Future<Map<String, dynamic>> uploadCaptures({
    required String scanSessionId,
    required int? userId,
    required Map<String, String> captures,
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'uploadCaptures',
        'scanSessionId': scanSessionId,
        'userID': userId,
        'captures': captures,
        'faceShape': faceShape,
        'hairTexture': hairTexture,
        'hairDensity': hairDensity,
        'consentAt': DateTime.now().toIso8601String(),
      }),
    );

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to upload face captures');
    }
    return data;
  }

  static Future<Map<String, dynamic>> fetchRecommendations({
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
    int? userId,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'recommendWithInsights',
        'faceShape': faceShape,
        'hairTexture': hairTexture,
        'hairDensity': hairDensity,
        'userID': userId,
      }),
    );

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to load AI recommendations');
    }
    return data;
  }

  static Future<Map<String, String>> saveCompositedPreviews({
    required String scanSessionId,
    required int variantId,
    required Map<String, String> previewsBase64,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'savePreviews',
        'scanSessionId': scanSessionId,
        'variantID': variantId,
        'previews': previewsBase64,
      }),
    );

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to save haircut previews');
    }

    return {
      'frontViewUrl': data['frontViewUrl']?.toString() ?? '',
      'sideViewUrl': data['sideViewUrl']?.toString() ?? '',
      'backViewUrl': data['backViewUrl']?.toString() ?? '',
    };
  }

  static Future<void> attachPreviewsToAppointment({
    required int appointmentId,
    required String scanSessionId,
    required int variantId,
  }) async {
    await http.post(
      Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'attachToAppointment',
        'appointmentID': appointmentId,
        'scanSessionId': scanSessionId,
        'variantID': variantId,
      }),
    );
  }
}
