import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Result of `time_slots.php` → `suggestBestSlot`.
class SuggestSlotResult {
  final Map<String, dynamic>? suggestion;
  final String? errorMessage;
  final bool isConnectionError;

  const SuggestSlotResult._({
    this.suggestion,
    this.errorMessage,
    this.isConnectionError = false,
  });

  bool get isSuccess => suggestion != null && errorMessage == null;

  factory SuggestSlotResult.success(Map<String, dynamic> suggestion) =>
      SuggestSlotResult._(suggestion: suggestion);

  factory SuggestSlotResult.noSlots() => const SuggestSlotResult._();

  factory SuggestSlotResult.apiError(String message) =>
      SuggestSlotResult._(errorMessage: message);

  factory SuggestSlotResult.connectionError(String message) =>
      SuggestSlotResult._(errorMessage: message, isConnectionError: true);

  factory SuggestSlotResult.timeout() => const SuggestSlotResult._(
        errorMessage:
            'Checking times took too long. Make sure Apache is running and the API is reachable.',
      );
}

class BookingSlotsService {
  static const Duration _timeout = Duration(seconds: 45);

  static Future<SuggestSlotResult> fetchBestSuggestion() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/time_slots.php');
    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'action': 'suggestBestSlot'}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final suggestion = data['suggestion'];
        if (suggestion is Map<String, dynamic>) {
          return SuggestSlotResult.success(suggestion);
        }
        return SuggestSlotResult.noSlots();
      }

      if (response.statusCode == 404) {
        return SuggestSlotResult.noSlots();
      }

      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final err = data['error']?.toString();
          if (err != null && err.isNotEmpty) {
            return SuggestSlotResult.apiError(err);
          }
        } catch (_) {}
      }

      return SuggestSlotResult.apiError(
        'Unable to check available times (HTTP ${response.statusCode}).',
      );
    } on TimeoutException {
      return SuggestSlotResult.timeout();
    } on SocketException catch (e) {
      if (kDebugMode) {
        debugPrint('[BookingSlots] SocketException: $e → ${ApiConfig.baseUrl}');
      }
      return SuggestSlotResult.connectionError(
        'Cannot reach the API at ${ApiConfig.baseUrl}. '
        'On a phone: same Wi‑Fi as this PC, Apache running, and correct IP in api_config.dart '
        '(run ipconfig, use IPv4 like 192.168.1.x).',
      );
    } catch (e) {
      return SuggestSlotResult.apiError(
        'Unable to check available times right now. Please try again.',
      );
    }
  }
}
