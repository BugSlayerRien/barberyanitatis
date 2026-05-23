import 'package:flutter/material.dart';

import '../ai_chatbot_page.dart';

/// White FAB matching the live face scanner chat button.
class AiChatbotFab extends StatelessWidget {
  final String heroTag;
  final double bottomPadding;

  const AiChatbotFab({
    super.key,
    required this.heroTag,
    this.bottomPadding = 70,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: FloatingActionButton(
        heroTag: heroTag,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        tooltip: 'Open AI Barber Chat',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AiChatbotPage()),
          );
        },
        child: const Icon(Icons.support_agent_rounded),
      ),
    );
  }
}
