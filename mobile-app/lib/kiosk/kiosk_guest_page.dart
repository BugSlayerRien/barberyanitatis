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
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
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
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Your first name',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: KioskColors.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: KioskColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: KioskColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white),
                ),
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
