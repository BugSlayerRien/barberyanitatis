import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AiChatbotPage extends StatefulWidget {
  const AiChatbotPage({super.key});

  @override
  State<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends State<AiChatbotPage> {
  static const String _apiKey =
      'REMOVED_GEMINI_KEY';
  static const String _modelName = 'gemini-2.5-flash';

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  String? _startupHint;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        text:
            'Yo, I am AI Assitant! Ask me for haircut ideas, maintenance tips, or what style fits your face shape.',
        isUser: false,
      ),
    );

    if (!_apiKey.startsWith('AIza')) {
      _startupHint =
          'Warning: this key format may be invalid for Gemini API. Typical Gemini API keys start with AIza.';
      _messages.add(
        _ChatMessage(
          text: _startupHint!,
          isUser: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _sending = true;
      _inputController.clear();
    });
    _scrollToBottom();

    try {
      final history = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .take(_messages.length - 1)
          .map((m) => '${m.isUser ? 'Customer' : 'Barber AI'}: ${m.text}')
          .join('\n');

      final prompt = '''
You are Tati AI Barber, a friendly and skilled barber assistant.
Use a confident barber tone, practical advice, and concise responses.
Focus on haircut fit, maintenance, styling, and booking prep.
If needed, ask one short follow-up question.

Conversation so far:
$history

Customer: $text
Barber AI:
''';

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_modelName:generateContent?key=$_apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.7,
            'topP': 0.9,
            'maxOutputTokens': 512,
          }
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final candidates = data['candidates'] as List<dynamic>? ?? const [];
      final first = candidates.isNotEmpty
          ? (candidates.first as Map<String, dynamic>)
          : <String, dynamic>{};
      final content = first['content'] as Map<String, dynamic>? ?? const {};
      final parts = content['parts'] as List<dynamic>? ?? const [];
      final reply = parts.isNotEmpty
          ? (parts.first as Map<String, dynamic>)['text']?.toString().trim() ?? ''
          : '';

      setState(() {
        _messages.add(
          _ChatMessage(
            text: reply.isEmpty
                ? 'I could not generate a response right now. Try again in a bit.'
                : reply,
            isUser: false,
          ),
        );
      });
    } catch (e) {
        final details = e.toString();
      final looksLikePermissionIssue = details.contains('403') ||
          details.toLowerCase().contains('permission') ||
          details.toLowerCase().contains('forbidden');
      final looksLikeBadKey = details.contains('400') ||
          details.toLowerCase().contains('api key') ||
          details.toLowerCase().contains('invalid');
        final looksLikeModelIssue = details.contains('404') ||
          details.toLowerCase().contains('not found') ||
          details.toLowerCase().contains('model');

      final message = looksLikePermissionIssue
          ? 'Gemini denied access (403). Check API restrictions, allowed origins, and if Generative Language API is enabled.\n$details'
          : looksLikeBadKey
              ? 'Gemini rejected the key/request (400). Verify key type and value.\n$details'
            : looksLikeModelIssue
              ? 'Model endpoint issue. Check model name and API version.\n$details'
              : 'Connection issue with Gemini.\n$details';

      setState(() {
        _messages.add(
          _ChatMessage(
            text: message,
            isUser: false,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('AI Barber Chat', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final align =
                    message.isUser ? Alignment.centerRight : Alignment.centerLeft;
                final bg = message.isUser
                    ? const Color(0xFFA99941)
                    : const Color(0xFF1A1A1A);
                final fg = message.isUser ? Colors.black : Colors.white;

                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(color: fg, fontSize: 13, height: 1.35),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask your barber AI... ',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1B1B1B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 46,
                    width: 46,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _send,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: const Color(0xFFA99941),
                        foregroundColor: Colors.black,
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String text;
  final bool isUser;

  const _ChatMessage({required this.text, required this.isUser});
}
