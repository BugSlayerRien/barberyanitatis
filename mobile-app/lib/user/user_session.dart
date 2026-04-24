import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserSession {
  static const String _userCalibrationKey = 'user_hair_calibration';

  static int? userId;
  static String? fullName;
  static String? email;
  static List<String> roles = [];

  static String? selectedStyleName;
  static int? selectedVariantId;
  static int? selectedServiceId;
  static int? selectedEstimatedMinutes;
  static String? activeScanSessionId;

  static Map<String, dynamic>? lastScan;
  static List<Map<String, dynamic>> lastRecommendations = [];
  static UserCalibration? _cachedUserCalibration;

  static UserCalibration? get userCalibration => _cachedUserCalibration;

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

  static void clear() {
    userId = null;
    fullName = null;
    email = null;
    roles = [];
    selectedStyleName = null;
    selectedVariantId = null;
    selectedServiceId = null;
    selectedEstimatedMinutes = null;
    activeScanSessionId = null;
    lastScan = null;
    lastRecommendations = [];
    _cachedUserCalibration = null;
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
