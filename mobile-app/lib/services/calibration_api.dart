import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CalibrationApi {
  static DateTime? _disabledUntil;
  static DateTime? _lastLogAt;

  static String get endpoint {
    const configured = String.fromEnvironment(
      'CALIBRATION_API_ENDPOINT',
      defaultValue: '',
    );
    return configured;
  }

  static Future<Map<String, dynamic>?> computeCalibration({
    required Map<String, dynamic> faceData,
    required String styleId,
    required String styleFamily,
  }) async {
    final resolvedEndpoint = endpoint;
    if (resolvedEndpoint.isEmpty) {
      return null;
    }

    final disabledUntil = _disabledUntil;
    if (disabledUntil != null && DateTime.now().isBefore(disabledUntil)) {
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse(resolvedEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ...faceData,
          'styleId': styleId,
          'styleFamily': styleFamily,
        }),
      );

      if (response.statusCode != 200 || response.body.isEmpty) {
        if (response.statusCode == 404 || response.statusCode == 405 || response.statusCode >= 500) {
          _markTemporarilyUnavailable();
          _throttledLog(
            'Calibration API unavailable (HTTP ${response.statusCode}) at $resolvedEndpoint. Temporarily paused.',
          );
        }
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['success'] == true && data['calibration'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data['calibration'] as Map);
      }
    } catch (e) {
      _markTemporarilyUnavailable();
      _throttledLog('Calibration API error: $e, uri=$resolvedEndpoint');
    }

    return null;
  }

  static void _markTemporarilyUnavailable() {
    _disabledUntil = DateTime.now().add(const Duration(minutes: 2));
  }

  static void _throttledLog(String message) {
    final now = DateTime.now();
    final lastLogAt = _lastLogAt;
    if (lastLogAt != null && now.difference(lastLogAt) < const Duration(seconds: 20)) {
      return;
    }
    _lastLogAt = now;
    debugPrint(message);
  }
}
