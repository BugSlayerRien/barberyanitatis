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

  /// Fast ranked list (no Gemini) — used for first paint on results / scanner.
  static Future<List<Map<String, dynamic>>> fetchQuickRankings({
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
    int? userId,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'rankByFeatures',
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
      throw Exception(data['error']?.toString() ?? 'Failed to load hairstyle rankings');
    }

    final rows = (data['recommendations'] as List<dynamic>? ??
            data['variants'] as List<dynamic>? ??
            [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
      if (id.isEmpty || seen.contains(id)) {
        continue;
      }
      seen.add(id);
      unique.add(row);
      if (unique.length >= 12) {
        break;
      }
    }
    return unique;
  }

  static String _categorizeStyleName(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'mullet|edgar|quiff|burst|messy|curtains|pompadour').hasMatch(lower)) {
      return 'alternative';
    }
    if (RegExp(r'crop|taper|fade|buzz|caesar|french|classic|two.?block').hasMatch(lower)) {
      return 'formal';
    }
    return 'youthful';
  }

  /// Client-side grouping when Gemini insights are slow or unavailable.
  static Map<String, dynamic> buildLocalInsightsFromRankings({
    required List<Map<String, dynamic>> rankings,
    required String faceShape,
    required String hairTexture,
  }) {
    if (rankings.isEmpty) {
      return {
        'topPicks': <Map<String, dynamic>>[],
        'categories': {
          'formal': <Map<String, dynamic>>[],
          'alternative': <Map<String, dynamic>>[],
          'youthful': <Map<String, dynamic>>[],
        },
        'aiSummary': '',
        'aiPowered': false,
      };
    }

    final used = <String>{};
    final topPicks = <Map<String, dynamic>>[];
    for (final row in rankings) {
      final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
      if (id.isEmpty || used.contains(id)) continue;
      used.add(id);
      final style = row['style_name']?.toString() ?? 'This style';
      topPicks.add({
        ...row,
        'fit_reason':
            '$style complements your $faceShape face and $hairTexture hair for everyday wear.',
      });
      if (topPicks.length >= 3) break;
    }

    final categories = <String, List<Map<String, dynamic>>>{
      'formal': [],
      'alternative': [],
      'youthful': [],
    };

    for (final row in rankings) {
      final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
      if (id.isEmpty || used.contains(id)) continue;
      final name = row['style_name']?.toString() ?? 'Style';
      final cat = _categorizeStyleName(name);
      if (categories[cat]!.length >= 3) continue;
      used.add(id);
      categories[cat]!.add({
        ...row,
        'category': cat,
        'fit_reason':
            '$name suits your $faceShape face and $hairTexture hair for a $cat look.',
      });
    }

    for (final cat in categories.keys) {
      if (categories[cat]!.isNotEmpty) continue;
      for (final row in rankings) {
        final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
        if (id.isEmpty || used.contains(id)) continue;
        used.add(id);
        final name = row['style_name']?.toString() ?? 'Style';
        categories[cat]!.add({
          ...row,
          'category': cat,
          'fit_reason': '$name is a strong option for your features.',
        });
        break;
      }
    }

    return {
      'topPicks': topPicks,
      'categories': categories,
      'aiSummary':
          'Based on your $faceShape face and $hairTexture hair, we grouped styles into formal, alternative, and youthful options.',
      'aiPowered': false,
    };
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

  static Future<void> ensureCapturesOnServer({
    required String scanSessionId,
    required int? userId,
    required Map<String, String> captures,
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
  }) async {
    final validation = validateCaptures(captures);
    if (!validation.ok) {
      throw Exception(validation.error ?? 'Invalid captures');
    }
    await uploadCaptures(
      scanSessionId: scanSessionId,
      userId: userId,
      captures: captures,
      faceShape: faceShape,
      hairTexture: hairTexture,
      hairDensity: hairDensity,
    );
  }

  static Map<String, String> captureFileUrls(String scanSessionId) {
    final safeId = scanSessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
    final base = '${ApiConfig.rootUrl}/uploads/face_scans/$safeId';
    return {
      'frontViewUrl': '$base/front.jpg',
      'sideViewUrl': '$base/left.jpg',
      'backViewUrl': '$base/right.jpg',
    };
  }

  static Future<Map<String, String>> saveCompositedPreviews({
    required String scanSessionId,
    required int variantId,
    required Map<String, String> previewsBase64,
    int? userId,
    String? faceShape,
    String? hairTexture,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'savePreviews',
        'scanSessionId': scanSessionId,
        'variantID': variantId,
        'previews': previewsBase64,
        if (userId != null) 'userID': userId,
        if (faceShape != null) 'faceShape': faceShape,
        if (hairTexture != null) 'hairTexture': hairTexture,
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
