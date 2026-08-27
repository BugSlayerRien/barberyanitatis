import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_config.dart';

class CustomerApiException implements Exception {
  final int statusCode;
  final String message;

  const CustomerApiException(this.message, {this.statusCode = 0});

  @override
  String toString() => message;
}

/// Shared customer API client. Attaches the current Supabase access token.
/// Body `userID` is still sent by callers as a hint; PHP does not treat it as identity.
class CustomerApi {
  CustomerApi._();

  static const Duration defaultTimeout = Duration(seconds: 45);

  static Future<String?> currentAccessToken() async {
    final auth = Supabase.instance.client.auth;
    var session = auth.currentSession;
    if (session == null) {
      return null;
    }

    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final remaining = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000)
          .difference(DateTime.now());
      if (remaining.inSeconds < 60) {
        try {
          final refreshed = await auth.refreshSession();
          session = refreshed.session ?? auth.currentSession;
        } catch (_) {
          session = auth.currentSession;
        }
      }
    }

    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }

  static Future<Map<String, String>> headers() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final token = await currentAccessToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
      // Apache/CGI often drops Authorization; PHP also reads this fallback.
      headers['X-Supabase-Access-Token'] = token;
    }
    return headers;
  }

  static Future<http.Response> postJson(
    String endpoint,
    Map<String, dynamic> body, {
    Duration timeout = defaultTimeout,
  }) async {
    final cleaned = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    try {
      return await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/$cleaned'),
            headers: await headers(),
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const CustomerApiException(
        'The request timed out. Please try again.',
      );
    } on http.ClientException catch (e) {
      throw CustomerApiException('Network error: ${e.message}');
    } catch (e) {
      if (e is CustomerApiException) {
        rethrow;
      }
      throw CustomerApiException('Network error: $e');
    }
  }

  /// POST and decode JSON. Throws [CustomerApiException] for HTML, empty, or error status.
  static Future<Map<String, dynamic>> postDecoded(
    String endpoint,
    Map<String, dynamic> body, {
    Duration timeout = defaultTimeout,
    Set<int> okStatusCodes = const {200, 201},
  }) async {
    final response = await postJson(endpoint, body, timeout: timeout);
    return decodeJsonObject(response, okStatusCodes: okStatusCodes);
  }

  static Map<String, dynamic> decodeJsonObject(
    http.Response response, {
    Set<int> okStatusCodes = const {200, 201},
  }) {
    final raw = response.body.trim();
    if (raw.isEmpty) {
      throw CustomerApiException(
        'The API returned an empty response (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (raw.startsWith('<')) {
      throw CustomerApiException(
        'The API returned a web page instead of JSON (HTTP ${response.statusCode}). '
        'If this just went live, wait a moment for the server to finish starting and try again.',
        statusCode: response.statusCode,
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw CustomerApiException(
        'The API returned an invalid response (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map) {
      throw CustomerApiException(
        'Unexpected API response (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    final map = Map<String, dynamic>.from(decoded);
    if (!okStatusCodes.contains(response.statusCode)) {
      throw CustomerApiException(
        map['error']?.toString() ??
            'Request failed (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    return map;
  }
}
