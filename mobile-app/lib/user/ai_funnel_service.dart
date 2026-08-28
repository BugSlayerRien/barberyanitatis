import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'customer_api.dart';

class AiFunnelService {
  static Future<void> trackScan({
    required String scanSessionId,
    required int? userId,
    required String? faceShape,
    required String? hairTexture,
    required String? hairDensity,
    required String? hairLength,
    required int recommendationCount,
  }) async {
    await _post({
      'action': 'trackScan',
      'scanSessionId': scanSessionId,
      'userID': userId,
      'faceShape': faceShape,
      'hairTexture': hairTexture,
      'hairDensity': hairDensity,
      'hairLength': hairLength,
      'recommendationCount': recommendationCount,
    });
  }

  static Future<void> saveSelection({
    required String scanSessionId,
    required int userId,
    required int variantId,
    required String styleName,
    required String? faceShape,
    required String? hairTexture,
    required String? hairDensity,
    required String? hairLength,
    required int? estimatedMinutes,
    String? frontViewUrl,
    String? sideViewUrl,
    String? backViewUrl,
  }) async {
    await _post({
      'action': 'saveSelection',
      'scanSessionId': scanSessionId,
      'userID': userId,
      'variantID': variantId,
      'styleName': styleName,
      'faceShape': faceShape,
      'hairTexture': hairTexture,
      'hairDensity': hairDensity,
      'hairLength': hairLength,
      'estimatedMinutes': estimatedMinutes,
      'frontViewUrl': frontViewUrl,
      'sideViewUrl': sideViewUrl,
      'backViewUrl': backViewUrl,
    });
  }

  static Future<void> trackBookingCreated({
    required String scanSessionId,
    required int userId,
    required int variantId,
    required int appointmentId,
    required int? serviceId,
    required int? estimatedMinutes,
    String? frontViewUrl,
    String? sideViewUrl,
    String? backViewUrl,
  }) async {
    await _post({
      'action': 'trackBookingCreated',
      'scanSessionId': scanSessionId,
      'userID': userId,
      'variantID': variantId,
      'appointmentID': appointmentId,
      'serviceID': serviceId,
      'estimatedMinutes': estimatedMinutes,
      'frontViewUrl': frontViewUrl,
      'sideViewUrl': sideViewUrl,
      'backViewUrl': backViewUrl,
    });
  }

  static Future<void> _post(Map<String, dynamic> payload) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_funnel.php'),
        headers: await CustomerApi.headers(),
        body: jsonEncode(payload),
      );
    } catch (_) {
      // Analytics and personalization tracking should never block UX.
    }
  }
}
