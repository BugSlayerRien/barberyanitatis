import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  static const String _userCalibrationKey = 'user_hair_calibration';
  static const String _preferredHairTextureKey = 'preferred_hair_texture';
  static const String _lastRecommendedVariantsKey = 'last_recommended_variant_ids';

  static int? userId;
  /// Straight, Wavy, or Curly — set during onboarding and editable in profile.
  static String? preferredHairTexture;
  static String? fullName;
  static String? email;
  static List<String> roles = [];

  static String? selectedStyleName;
  static int? selectedVariantId;
  static int? selectedServiceId;
  static int? selectedEstimatedMinutes;
  static Map<String, String>? selectedPreviewImages;
  /// Customer-specific composited previews (face + chosen haircut overlay).
  static Map<String, String>? customerPreviewImages;
  static Map<String, String>? capturedFaceImages;
  /// Normalized face rectangles per capture angle (front/left/right).
  static Map<String, Rect>? captureFaceRects;
  static String? activeScanSessionId;
  static bool hasRecentRecommendations = false;

  static Map<String, dynamic>? lastScan;
  static List<Map<String, dynamic>> lastRecommendations = [];
  static UserCalibration? _cachedUserCalibration;

  /// Snapshot of the latest *completed* scan (captures, analysis, recs, previews).
  /// Survives leaving results and opening AI Scan entry without "New scan".
  static Map<String, dynamic>? _completedScanSnapshot;

  static UserCalibration? get userCalibration => _cachedUserCalibration;

  static Map<String, dynamic>? get completedScanSummary {
    final snap = _completedScanSnapshot;
    if (snap == null) return null;
    final scan = snap['lastScan'];
    if (scan is Map<String, dynamic>) return scan;
    if (scan is Map) return Map<String, dynamic>.from(scan);
    return null;
  }

  static String? get completedScanSessionId =>
      _completedScanSnapshot?['activeScanSessionId']?.toString();

  static bool get hasCompletedScanResults {
    final caps = _completedScanSnapshot?['captures'];
    return caps is Map && caps.isNotEmpty;
  }

  /// Analysis map used for Library compatibility + Home chips.
  static Map<String, dynamic>? get scanForCompatibility {
    if (lastScan != null) return lastScan;
    return completedScanSummary;
  }

  static Map<String, String>? _stringMapOrNull(dynamic raw) {
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
  }

  /// Persist the current in-memory session as the latest completed scan.
  static void commitCompletedScan() {
    if (lastScan == null) return;
    final captures = capturedFaceImages;
    if (captures == null || captures.isEmpty) return;

    _completedScanSnapshot = {
      'lastScan': Map<String, dynamic>.from(lastScan!),
      'captures': Map<String, String>.from(captures),
      'recommendations': lastRecommendations
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      'activeScanSessionId': activeScanSessionId ?? lastScan!['scanSessionId'],
      'selectedPreviewImages': selectedPreviewImages == null
          ? null
          : Map<String, String>.from(selectedPreviewImages!),
      'customerPreviewImages': customerPreviewImages == null
          ? null
          : Map<String, String>.from(customerPreviewImages!),
      'selectedVariantId': selectedVariantId,
      'selectedStyleName': selectedStyleName,
      'selectedServiceId': selectedServiceId,
      'selectedEstimatedMinutes': selectedEstimatedMinutes,
      'hasRecentRecommendations': hasRecentRecommendations,
    };
  }

  /// Restore completed scan into live session fields. Returns false if none.
  static bool restoreCompletedScan() {
    final snap = _completedScanSnapshot;
    if (snap == null) return false;

    final caps = _stringMapOrNull(snap['captures']);
    if (caps == null || caps.isEmpty) return false;

    final scanRaw = snap['lastScan'];
    lastScan = scanRaw is Map ? Map<String, dynamic>.from(scanRaw) : null;
    capturedFaceImages = caps;
    activeScanSessionId =
        snap['activeScanSessionId']?.toString() ?? lastScan?['scanSessionId']?.toString();

    final recs = snap['recommendations'];
    if (recs is List) {
      lastRecommendations = recs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else {
      lastRecommendations = [];
    }
    hasRecentRecommendations =
        snap['hasRecentRecommendations'] == true || lastRecommendations.isNotEmpty;

    selectedPreviewImages = _stringMapOrNull(snap['selectedPreviewImages']);
    customerPreviewImages = _stringMapOrNull(snap['customerPreviewImages']);
    selectedVariantId = snap['selectedVariantId'] is int
        ? snap['selectedVariantId'] as int
        : int.tryParse('${snap['selectedVariantId'] ?? ''}');
    selectedStyleName = snap['selectedStyleName']?.toString();
    selectedServiceId = snap['selectedServiceId'] is int
        ? snap['selectedServiceId'] as int
        : int.tryParse('${snap['selectedServiceId'] ?? ''}');
    selectedEstimatedMinutes = snap['selectedEstimatedMinutes'] is int
        ? snap['selectedEstimatedMinutes'] as int
        : int.tryParse('${snap['selectedEstimatedMinutes'] ?? ''}');
    return true;
  }

  /// Clears working/in-progress scan fields but keeps [_completedScanSnapshot].
  static void beginNewScanWorkingState() {
    selectedStyleName = null;
    selectedVariantId = null;
    selectedServiceId = null;
    selectedEstimatedMinutes = null;
    selectedPreviewImages = null;
    customerPreviewImages = null;
    capturedFaceImages = null;
    captureFaceRects = null;
    activeScanSessionId = null;
    hasRecentRecommendations = false;
    lastRecommendations = [];
    lastScan = null;
  }

  /// Before capturing a new full scan while a completed session may still be live.
  static void prepareNewCaptureSessionKeepingCompleted() {
    if (_completedScanSnapshot == null &&
        lastScan != null &&
        capturedFaceImages != null &&
        capturedFaceImages!.isNotEmpty) {
      commitCompletedScan();
    }
    beginNewScanWorkingState();
  }

  /// After discarding an in-progress capture, put completed results back on session.
  static void discardInProgressAndRestoreCompleted() {
    beginNewScanWorkingState();
    restoreCompletedScan();
  }

  static Future<String?> loadPreferredHairTexture() async {
    if (preferredHairTexture != null && preferredHairTexture!.trim().isNotEmpty) {
      return preferredHairTexture;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_preferredHairTextureKey)?.trim();
    if (stored != null && stored.isNotEmpty) {
      preferredHairTexture = _normalizeHairTexture(stored);
    }
    return preferredHairTexture;
  }

  static Future<void> savePreferredHairTexture(String texture) async {
    final normalized = _normalizeHairTexture(texture);
    if (normalized == null) {
      return;
    }
    preferredHairTexture = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferredHairTextureKey, normalized);
  }

  static String? _normalizeHairTexture(String raw) {
    final value = raw.trim().toLowerCase();
    switch (value) {
      case 'straight':
        return 'Straight';
      case 'wavy':
        return 'Wavy';
      case 'curly':
      case 'coily':
        return 'Curly';
      default:
        return null;
    }
  }

  /// Normalizes API/profile texture labels to Straight, Wavy, or Curly.
  static String normalizeHairTextureLabel(String? raw, {String fallback = 'Wavy'}) {
    return _normalizeHairTexture(raw ?? '') ?? fallback;
  }

  static Future<UserCalibration?> loadUserCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userCalibrationKey);
    if (raw == null || raw.isEmpty) {
      _cachedUserCalibration = null;
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedUserCalibration = UserCalibration.fromJson(decoded);
        return _cachedUserCalibration;
      }
    } catch (_) {
      // Ignore bad payloads and keep app functional.
    }

    _cachedUserCalibration = null;
    return null;
  }

  static Future<void> saveUserCalibration(UserCalibration cal) async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUserCalibration = cal;
    await prefs.setString(_userCalibrationKey, jsonEncode(cal.toJson()));
  }

  static Future<void> clearUserCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedUserCalibration = null;
    await prefs.remove(_userCalibrationKey);
  }

  static Future<UserCalibration> mergeServerCalibration({
    required double offsetX,
    required double offsetY,
    required double scale,
    required double foreheadOffset,
    double alpha = 0.4,
  }) async {
    final current = _cachedUserCalibration ?? await loadUserCalibration() ??
        UserCalibration.defaults();
    final weight = alpha.clamp(0.0, 1.0);

    final merged = UserCalibration(
      offsetX: ((1 - weight) * current.offsetX) + (weight * offsetX),
      offsetY: ((1 - weight) * current.offsetY) + (weight * offsetY),
      scale: (((1 - weight) * current.scale) + (weight * scale))
          .clamp(0.7, 1.5)
          .toDouble(),
      foreheadOffset:
          (((1 - weight) * current.foreheadOffset) + (weight * foreheadOffset))
              .clamp(-0.12, 0.12)
              .toDouble(),
      lastUpdated: DateTime.now(),
    );

    await saveUserCalibration(merged);
    return merged;
  }

  static String ensureScanSessionId() {
    final existing = activeScanSessionId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final uid = userId ?? 0;
    activeScanSessionId = 'scan_${uid}_$stamp';
    return activeScanSessionId!;
  }

  static Future<List<int>> loadLastRecommendedVariantIds({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_lastRecommendedVariantsKey}_${userId ?? UserSession.userId ?? 0}';
    final raw = prefs.getStringList(key) ?? [];
    return raw.map((e) => int.tryParse(e) ?? 0).where((id) => id > 0).toList();
  }

  static Future<void> saveLastRecommendedVariantIds(
    List<int> variantIds, {
    int? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_lastRecommendedVariantsKey}_${userId ?? UserSession.userId ?? 0}';
    final unique = variantIds.where((id) => id > 0).take(12).map((id) => '$id').toList();
    await prefs.setStringList(key, unique);
  }

  /// Full clear of working + completed scan state (explicit discard / settings / logout).
  ///
  /// When [preserveCompatibility] is true, keeps a lightweight [lastScan]
  /// summary only (no captures) for Library badges.
  static void resetScanState({bool preserveCompatibility = false}) {
    Map<String, dynamic>? summary;
    if (preserveCompatibility) {
      summary = scanForCompatibility;
      if (summary != null) {
        summary = {
          'userId': summary['userId'],
          'scanSessionId': summary['scanSessionId'],
          'faceShape': summary['faceShape'],
          'hairTexture': summary['hairTexture'],
          'hairLength': summary['hairLength'],
          'hairLengthLevel': summary['hairLengthLevel'],
          'analysisProvider': summary['analysisProvider'],
          'hairTextureScore': summary['hairTextureScore'],
          'scanSucceeded': summary['scanSucceeded'],
          'noHairDetected': summary['noHairDetected'],
          'hairColor': summary['hairColor'],
        };
      }
    }

    _completedScanSnapshot = null;

    selectedStyleName = null;
    selectedVariantId = null;
    selectedServiceId = null;
    selectedEstimatedMinutes = null;
    selectedPreviewImages = null;
    customerPreviewImages = null;
    capturedFaceImages = null;
    captureFaceRects = null;
    activeScanSessionId = null;
    hasRecentRecommendations = false;
    lastRecommendations = [];
    lastScan = summary;
  }

  static Future<void> clear() async {
    userId = null;
    fullName = null;
    email = null;
    roles = [];
    selectedStyleName = null;
    selectedVariantId = null;
    selectedServiceId = null;
    selectedEstimatedMinutes = null;
    selectedPreviewImages = null;
    customerPreviewImages = null;
    capturedFaceImages = null;
    captureFaceRects = null;
    activeScanSessionId = null;
    hasRecentRecommendations = false;
    lastScan = null;
    lastRecommendations = [];
    _completedScanSnapshot = null;
    preferredHairTexture = null;
    _cachedUserCalibration = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_preferredHairTextureKey);
    await clearUserCalibration();
  }
}

class UserCalibration {
  final double offsetX;
  final double offsetY;
  final double scale;
  final double foreheadOffset;
  final DateTime lastUpdated;

  const UserCalibration({
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
    this.foreheadOffset = 0,
    required this.lastUpdated,
  });

  UserCalibration copyWith({
    double? offsetX,
    double? offsetY,
    double? scale,
    double? foreheadOffset,
    DateTime? lastUpdated,
  }) {
    return UserCalibration(
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      foreheadOffset: foreheadOffset ?? this.foreheadOffset,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() => {
        'offsetX': offsetX,
        'offsetY': offsetY,
        'scale': scale,
        'foreheadOffset': foreheadOffset,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory UserCalibration.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic value, double fallback) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    return UserCalibration(
      offsetX: toDouble(json['offsetX'], 0),
      offsetY: toDouble(json['offsetY'], 0),
      scale: toDouble(json['scale'], 1.0),
      foreheadOffset: toDouble(json['foreheadOffset'], 0),
      lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static UserCalibration defaults() =>
      UserCalibration(lastUpdated: DateTime.now());
}
