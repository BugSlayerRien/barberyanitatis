import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_config.dart';

class AiChatbotService {
  static Future<Map<String, dynamic>> sendMessage({
    required String message,
    List<Map<String, dynamic>> history = const [],
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/chatbot.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        'history': history,
      }),
    );

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Chatbot request failed');
    }

    return data;
  }
}
