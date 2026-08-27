import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_config.dart';

/// Shared customer API client. Attaches the current Supabase access token.
/// Body `userID` is still sent by callers as a hint; PHP does not treat it as identity.
class CustomerApi {
  CustomerApi._();

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
    }
    return headers;
  }

  static Future<http.Response> postJson(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final cleaned = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return http.post(
      Uri.parse('${ApiConfig.baseUrl}/$cleaned'),
      headers: await headers(),
      body: jsonEncode(body),
    );
  }
}
