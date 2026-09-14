import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final error = KioskSession.guestNameErrorFor(name);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
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
              maxLength: KioskSession.guestNameMaxLength,
              // Counter only appears as the guest nears the cap — a "0/70"
              // sitting under an empty field reads as a demand, not a hint.
              buildCounter: (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) {
                if (maxLength == null || currentLength < maxLength - 10) {
                  return null;
                }
                return Text(
                  '$currentLength/$maxLength',
                  style: TextStyle(
                    color: currentLength >= maxLength
                        ? KioskColors.accent
                        : KioskColors.textMuted,
                    fontSize: 12,
                  ),
                );
              },
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\p{L} ]', unicode: true)),
              ],
              style: const TextStyle(color: KioskColors.textPrimary),
              decoration: kioskInputDecoration(
                hintText: KioskSession.guestNameHint,
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
