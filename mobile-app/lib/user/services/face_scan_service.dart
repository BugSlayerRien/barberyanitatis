import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api_config.dart';
import '../customer_api.dart';
import '../user_session.dart';

/// Thrown when the server refuses a new AI hairstyle generation because the user has
/// already used their free style quota (see AI_TRYON_STYLE_LIMIT on the server).
class FaceScanQuotaExceededException implements Exception {
  final String message;
  final int limit;
  final int used;

  FaceScanQuotaExceededException({
    required this.message,
    required this.limit,
    required this.used,
  });

  @override
  String toString() => message;
}

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

  static Future<Map<String, String>> _headers() => CustomerApi.headers();

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
      headers: await _headers(),
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

    final data = _decodeJsonMap(response.body);

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to upload face captures');
    }
    return data;
  }

  static Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      final snippet = body.length > 120 ? '${body.substring(0, 120)}...' : body;
      throw Exception(
        'Server returned an invalid response (not JSON). '
        'Check PHP error logs on the API host. Snippet: $snippet',
      );
    }
    return {};
  }

  static Map<String, dynamic> _rankingRequestBody({
    required String action,
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
    int? userId,
    List<String>? boostStyleKeys,
    List<int>? downrankVariantIds,
  }) {
    return {
      'action': action,
      'faceShape': faceShape,
      'hairTexture': hairTexture,
      if (hairDensity != null) 'hairDensity': hairDensity,
      if (userId != null) 'userID': userId,
      if (boostStyleKeys != null && boostStyleKeys.isNotEmpty)
        'boostStyleKeys': boostStyleKeys,
      if (downrankVariantIds != null && downrankVariantIds.isNotEmpty)
        'downrankVariantIds': downrankVariantIds,
    };
  }

  static List<String> boostStyleKeysFromLastScan() {
    final scan = UserSession.lastScan;
    if (scan == null) return [];
    final keys = <String>[];
    final topStyles = scan['pythonTopStyles'];
    if (topStyles is List) {
      for (final item in topStyles) {
        if (item is Map) {
          final key = item['key']?.toString() ?? '';
          if (key.isNotEmpty) keys.add(key);
        } else {
          final s = item?.toString() ?? '';
          if (s.isNotEmpty) keys.add(s);
        }
      }
    }
    final achievable = scan['achievableStyles'];
    if (achievable is List) {
      for (final item in achievable) {
        final s = item?.toString() ?? '';
        if (s.isNotEmpty && !keys.contains(s)) keys.add(s);
      }
    }
    return keys.take(8).toList();
  }

  /// Fast ranked list (no Gemini) — used for first paint on results / scanner.
  static Future<List<Map<String, dynamic>>> fetchQuickRankings({
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
    int? userId,
    List<String>? boostStyleKeys,
    List<int>? downrankVariantIds,
  }) async {
    final downrank =
        downrankVariantIds ?? await UserSession.loadLastRecommendedVariantIds(userId: userId);
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      headers: await _headers(),
      body: jsonEncode(_rankingRequestBody(
        action: 'rankByFeatures',
        faceShape: faceShape,
        hairTexture: hairTexture,
        hairDensity: hairDensity,
        userId: userId,
        boostStyleKeys: boostStyleKeys ?? boostStyleKeysFromLastScan(),
        downrankVariantIds: downrank,
      )),
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

    final seenIds = <String>{};
    final seenNames = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
      final nameKey =
          (row['style_name'] ?? row['styleName'] ?? '').toString().trim().toLowerCase();
      if (id.isEmpty || seenIds.contains(id)) {
        continue;
      }
      if (nameKey.isNotEmpty && seenNames.contains(nameKey)) {
        continue;
      }
      seenIds.add(id);
      if (nameKey.isNotEmpty) {
        seenNames.add(nameKey);
      }
      unique.add(row);
      if (unique.length >= 12) {
        break;
      }
    }
    return unique;
  }

  static String _categorizeStyleName(String name) {
    final lower = name.toLowerCase();
    if (RegExp(r'mullet|edgar|quiff|burst|messy|curtains|pompadour|curly|wavy|modern')
        .hasMatch(lower)) {
      return 'alternative';
    }
    if (RegExp(r'crop|taper|fade|buzz|caesar|french|classic|two.?block').hasMatch(lower)) {
      return 'formal';
    }
    return 'alternative';
  }

  static String _localFitReason(
    Map<String, dynamic> row,
    String faceShape,
    String hairTexture, {
    String category = '',
  }) {
    final style = row['style_name']?.toString() ?? 'This style';
    final pct = row['match_percent'] ?? row['matchPercent'];
    final rank = row['match_rank_label']?.toString() ?? row['matchRankLabel']?.toString() ?? '';
    final desc = row['description']?.toString().trim() ?? '';
    final pctText = pct != null ? ' (${pct}% match)' : '';
    final rankText = rank.isNotEmpty ? ' $rank.' : '';
    var text =
        '$style fits your $faceShape face and $hairTexture hair$pctText.$rankText';
    if (category == 'formal') {
      text += ' Clean, professional finish.';
    } else if (category == 'alternative') {
      text += ' Bolder shape with everyday wearability.';
    }
    if (desc.isNotEmpty) {
      final snippet = desc.length > 90 ? '${desc.substring(0, 87)}...' : desc;
      text += ' $snippet';
    }
    return text;
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
      topPicks.add({
        ...row,
        'fit_reason': _localFitReason(row, faceShape, hairTexture),
      });
      if (topPicks.length >= 3) break;
    }

    final categories = <String, List<Map<String, dynamic>>>{
      'formal': [],
      'alternative': [],
    };

    for (final row in rankings) {
      final id = '${row['variant_id'] ?? row['variantId'] ?? ''}'.trim();
      if (id.isEmpty || used.contains(id)) continue;
      final name = row['style_name']?.toString() ?? 'Style';
      final cat = _categorizeStyleName(name);
      if (categories[cat]!.length >= 2) continue;
      used.add(id);
      categories[cat]!.add({
        ...row,
        'category': cat,
        'fit_reason': _localFitReason(row, faceShape, hairTexture, category: cat),
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
          'Based on your $faceShape face and $hairTexture hair, we grouped styles into formal and alternative options.',
      'aiPowered': false,
    };
  }

  static Future<Map<String, dynamic>> fetchRecommendations({
    required String faceShape,
    required String hairTexture,
    String? hairDensity,
    int? userId,
    List<String>? boostStyleKeys,
    List<int>? downrankVariantIds,
  }) async {
    final downrank =
        downrankVariantIds ?? await UserSession.loadLastRecommendedVariantIds(userId: userId);
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      headers: await _headers(),
      body: jsonEncode(_rankingRequestBody(
        action: 'recommendWithInsights',
        faceShape: faceShape,
        hairTexture: hairTexture,
        hairDensity: hairDensity,
        userId: userId,
        boostStyleKeys: boostStyleKeys ?? boostStyleKeysFromLastScan(),
        downrankVariantIds: downrank,
      )),
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
    final prefix = 'uploads/face_scans/$safeId';
    return {
      'frontViewUrl': ApiConfig.resolveImageUrl('$prefix/front.jpg'),
      'sideViewUrl': ApiConfig.resolveImageUrl('$prefix/left.jpg'),
      'backViewUrl': ApiConfig.resolveImageUrl('$prefix/right.jpg'),
    };
  }

  /// Python sidecar: MediaPipe face shape + hair length from stored captures.
  static Future<Map<String, dynamic>> analyzeCaptures({
    required String scanSessionId,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
          headers: await _headers(),
          body: jsonEncode({
            'action': 'analyzeCaptures',
            'scanSessionId': scanSessionId,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Face analysis failed');
    }
    return data;
  }

  /// AI try-on (Gemini, falling back to Replicate) for all 3 capture angles
  /// (server-side; may take several minutes).
  static Future<Map<String, dynamic>> generateStylePreviews({
    required String scanSessionId,
    required int variantId,
    required String styleName,
    String? styleCode,
    int? userId,
    String? faceShape,
    String? hairTexture,
    int hairLengthLevel = 1,
    bool forceRegenerate = false,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
          headers: await _headers(),
          body: jsonEncode({
            'action': 'generateStylePreviews',
            'scanSessionId': scanSessionId,
            'variantID': variantId,
            'styleName': styleName,
            if (styleCode != null && styleCode.isNotEmpty) 'styleCode': styleCode,
            if (userId != null) 'userID': userId,
            if (faceShape != null) 'faceShape': faceShape,
            if (hairTexture != null) 'hairTexture': hairTexture,
            'hairLengthLevel': hairLengthLevel,
            'forceRegenerate': forceRegenerate,
          }),
        )
        .timeout(const Duration(minutes: 15));

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode == 429 || data['quotaExceeded'] == true) {
      final quota = data['quota'] is Map ? Map<String, dynamic>.from(data['quota'] as Map) : const {};
      throw FaceScanQuotaExceededException(
        message: data['error']?.toString() ??
            "You've reached your free AI hairstyle generation limit.",
        limit: (quota['limit'] as num?)?.toInt() ?? 2,
        used: (quota['used'] as num?)?.toInt() ?? 0,
      );
    }

    if (response.statusCode != 200) {
      final err = data['error']?.toString() ?? 'Failed to generate style previews';
      final lower = err.toLowerCase();
      if (lower.contains('402') || lower.contains('credit') || lower.contains('billing') || lower.contains('quota')) {
        throw Exception(
          'The AI provider has no credits/quota left right now. Please try again in a few minutes.\n$err',
        );
      }
      throw Exception(err);
    }
    return data;
  }

  /// Remaining free-style quota info from the last generateStylePreviews response, if any.
  static Map<String, dynamic>? quotaFromResponse(Map<String, dynamic> data) {
    final quota = data['quota'];
    return quota is Map ? Map<String, dynamic>.from(quota) : null;
  }

  static Map<String, String> previewUrlsFromResponse(Map<String, dynamic> data) {
    final urls = {
      'frontViewUrl': data['frontViewUrl']?.toString() ?? '',
      'sideViewUrl': data['sideViewUrl']?.toString() ?? '',
      'backViewUrl': data['backViewUrl']?.toString() ?? '',
    };
    if (urls.values.every((u) => u.trim().isEmpty)) {
      throw Exception(
        data['error']?.toString() ??
            'Server returned no preview image URLs. Check ai-service logs and try again.',
      );
    }
    return urls;
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
      headers: await _headers(),
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

  /// True only for a real AI-generated scan preview (saved under uploads/face_scans/...),
  /// never a catalog/library asset path (e.g. assets/images/overlays/...).
  static bool _isGeneratedPreviewUrl(String? url) {
    if (url == null) return false;
    final trimmed = url.trim();
    return trimmed.isNotEmpty && trimmed.contains('uploads/face_scans/');
  }

  /// Fields to send with booking.php create so AI previews attach server-side.
  ///
  /// Returns an empty map for pure library/catalog bookings (no real AI try-on was
  /// generated for this selection), so booking.php never attempts to attach a
  /// scanSessionId or catalog asset paths to the appointment.
  static Map<String, dynamic> bookingPreviewPayload() {
    final previews =
        UserSession.selectedPreviewImages ?? UserSession.customerPreviewImages;
    if (previews == null) {
      return <String, dynamic>{};
    }

    final front = previews['frontViewUrl'] ?? previews['front'];
    final side = previews['sideViewUrl'] ?? previews['left'];
    final back = previews['backViewUrl'] ?? previews['right'];

    final hasAiPreview = _isGeneratedPreviewUrl(front) ||
        _isGeneratedPreviewUrl(side) ||
        _isGeneratedPreviewUrl(back);
    if (!hasAiPreview) {
      return <String, dynamic>{};
    }

    final payload = <String, dynamic>{
      'scanSessionId': UserSession.ensureScanSessionId(),
    };
    if (front != null && front.trim().isNotEmpty) {
      payload['frontViewUrl'] = front.trim();
    }
    if (side != null && side.trim().isNotEmpty) {
      payload['sideViewUrl'] = side.trim();
    }
    if (back != null && back.trim().isNotEmpty) {
      payload['backViewUrl'] = back.trim();
    }
    return payload;
  }

  static Future<void> attachPreviewsToAppointment({
    required int appointmentId,
    required String scanSessionId,
    required int variantId,
  }) async {
    final previews =
        UserSession.selectedPreviewImages ?? UserSession.customerPreviewImages;
    final body = <String, dynamic>{
      'action': 'attachToAppointment',
      'appointmentID': appointmentId,
      'scanSessionId': scanSessionId,
      'variantID': variantId,
    };
    if (previews != null) {
      final front = previews['frontViewUrl'] ?? previews['front'];
      final side = previews['sideViewUrl'] ?? previews['left'];
      final back = previews['backViewUrl'] ?? previews['right'];
      if (front != null && front.trim().isNotEmpty) {
        body['frontViewUrl'] = front.trim();
      }
      if (side != null && side.trim().isNotEmpty) {
        body['sideViewUrl'] = side.trim();
      }
      if (back != null && back.trim().isNotEmpty) {
        body['backViewUrl'] = back.trim();
      }
    }

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/face_scan.php'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Could not attach haircut previews (${response.statusCode})',
      );
    }
  }
}
