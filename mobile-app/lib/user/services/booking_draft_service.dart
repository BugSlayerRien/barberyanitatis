import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../user_session.dart';

/// Persisted in-progress booking so the dashboard can offer "Continue booking".
class BookingDraft {
  final int variantId;
  final String? styleName;
  final int? serviceId;
  final int? estimatedMinutes;
  final int? barberId;
  final String? barberName;
  /// `barber` = style chosen, pick barber; `calendar` = barber chosen, pick slot.
  final String step;
  final int updatedAtMs;

  const BookingDraft({
    required this.variantId,
    this.styleName,
    this.serviceId,
    this.estimatedMinutes,
    this.barberId,
    this.barberName,
    required this.step,
    required this.updatedAtMs,
  });

  bool get isValid => variantId > 0;

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'styleName': styleName,
        'serviceId': serviceId,
        'estimatedMinutes': estimatedMinutes,
        'barberId': barberId,
        'barberName': barberName,
        'step': step,
        'updatedAtMs': updatedAtMs,
      };

  factory BookingDraft.fromJson(Map<String, dynamic> json) {
    return BookingDraft(
      variantId: int.tryParse('${json['variantId']}') ?? 0,
      styleName: json['styleName']?.toString(),
      serviceId: int.tryParse('${json['serviceId']}'),
      estimatedMinutes: int.tryParse('${json['estimatedMinutes']}'),
      barberId: int.tryParse('${json['barberId']}'),
      barberName: json['barberName']?.toString(),
      step: json['step']?.toString() ?? 'barber',
      updatedAtMs: int.tryParse('${json['updatedAtMs']}') ?? 0,
    );
  }
}

class BookingDraftService {
  static const String _prefsKey = 'booking_draft_v1';
  static const Duration _maxAge = Duration(days: 14);

  static Future<void> saveFromSession({
    required String step,
    int? barberId,
    String? barberName,
  }) async {
    final variantId = UserSession.selectedVariantId;
    if (variantId == null || variantId <= 0) {
      return;
    }

    final draft = BookingDraft(
      variantId: variantId,
      styleName: UserSession.selectedStyleName,
      serviceId: UserSession.selectedServiceId,
      estimatedMinutes: UserSession.selectedEstimatedMinutes,
      barberId: barberId,
      barberName: barberName,
      step: step,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(draft.toJson()));
  }

  static Future<BookingDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final draft = BookingDraft.fromJson(decoded);
      if (!draft.isValid) {
        return null;
      }
      final age = DateTime.now().millisecondsSinceEpoch - draft.updatedAtMs;
      if (age > _maxAge.inMilliseconds) {
        await clear();
        return null;
      }
      return draft;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static void applyToSession(BookingDraft draft) {
    UserSession.selectedVariantId = draft.variantId;
    UserSession.selectedStyleName = draft.styleName;
    UserSession.selectedServiceId = draft.serviceId;
    UserSession.selectedEstimatedMinutes = draft.estimatedMinutes;
  }
}
