import 'package:flutter/material.dart';

import 'kiosk_intent_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

class KioskGuestPage extends StatefulWidget {
  const KioskGuestPage({super.key});

  @override
  State<KioskGuestPage> createState() => _KioskGuestPageState();
}

class _KioskGuestPageState extends State<KioskGuestPage> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _continue() {
    final name = _nameController.text.trim();
    if (name.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least 4 letters for your name')),
      );
      return;
    }
    KioskSession.guestName = name;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskIntentPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: 'Welcome',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What should we call you?',
              style: TextStyle(color: KioskColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: KioskColors.textPrimary),
              decoration: kioskInputDecoration(
                hintText: 'Your name (at least 4 letters)',
              ),
              onSubmitted: (_) => _continue(),
            ),
          ],
        ),
      ),
      bottomBar: KioskPrimaryButton(label: 'Continue', onPressed: _continue),
    );
  }
}
