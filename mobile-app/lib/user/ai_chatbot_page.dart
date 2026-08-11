import 'package:flutter/material.dart';

import 'services/ai_chatbot_service.dart';

class AiChatbotPage extends StatefulWidget {
  const AiChatbotPage({super.key});

  @override
  State<AiChatbotPage> createState() => _AiChatbotPageState();
}

class _AiChatbotPageState extends State<AiChatbotPage> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _panel = Color(0xFF111111);
  static const Color _inputFill = Color(0xFF1B1B1B);

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages.add(
      const _ChatMessage(
        text:
            'Hi! I\'m Tati AI Barber. Ask about booking, walk-ins, face scan previews, or haircut care.',
        isUser: false,
      ),
    );
    _preloadFaq();
  }

  Future<void> _preloadFaq() async {
    await AiChatbotService.ensureFaqLoaded();
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
      _inputController.clear();
    });
    _scrollToBottom();

    await AiChatbotService.ensureFaqLoaded();
    final localFaq = AiChatbotService.matchLocalFaq(text);
    if (localFaq != null) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text: localFaq.answer,
            isUser: false,
            sourceLabel: 'FAQ',
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    setState(() => _sending = true);

    try {
      final history = _messages
          .where((m) => m.text.trim().isNotEmpty)
          .take(_messages.length)
          .map((m) => {'text': m.text, 'isUser': m.isUser})
          .toList();

      final data = await AiChatbotService.requestGeminiFallback(
        message: text,
        history: history,
      );

      final reply = data['reply']?.toString().trim() ?? '';
      final source = data['source']?.toString() ?? '';

      setState(() {
        _messages.add(
          _ChatMessage(
            text: reply.isNotEmpty ? reply : AiChatbotService.safeFallbackReply,
            isUser: false,
            sourceLabel: source == 'gemini' ? 'AI' : null,
          ),
        );
      });
    } catch (e) {
      setState(() {
        _messages.add(
          _ChatMessage(
            text: AiChatbotService.safeFallbackReply,
            isUser: false,
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _panel,
        foregroundColor: Colors.white,
        title: const Text('AI Barber Chat', style: TextStyle(color: Colors.white)),
      ),
      floatingActionButton: null,
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
                final bg = message.isUser ? _inputFill : Colors.white;
                final fg = message.isUser ? Colors.white : Colors.black;

                return Align(
                  alignment: align,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: message.isUser
                          ? Border.all(color: Colors.white24)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.sourceLabel != null) ...[
                          Text(
                            message.sourceLabel!,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.45),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          message.text,
                          style: TextStyle(color: fg, fontSize: 13, height: 1.35),
                        ),
                      ],
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
                color: _panel,
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
                        hintText: 'Ask your barber AI...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: _inputFill,
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
                        backgroundColor: Colors.white,
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
  final String? sourceLabel;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.sourceLabel,
  });
}
