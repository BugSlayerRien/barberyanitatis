import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'kiosk_api.dart';
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
  bool _checking = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_checking) return;
    final name = _nameController.text.trim();
    final error = KioskSession.guestNameErrorFor(name);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    // Three Marks in one afternoon is ordinary, and the barber calling "Mark"
    // then gets two people standing up. Ask the second one for a surname now,
    // while they are still here -- it is the only moment we can ask anything.
    setState(() => _checking = true);
    try {
      final result = await KioskApi.checkGuestName(name);
      if (!mounted) return;
      if (result['duplicate'] == true) {
        final accepted = await _askForFullerName(name, result['message']?.toString());
        if (!mounted || !accepted) return;
      }
    } catch (_) {
      // The queue works without this check; never block someone joining it
      // because the duplicate lookup could not be reached.
    } finally {
      if (mounted) setState(() => _checking = false);
    }

    if (!mounted) return;
    KioskSession.guestName = _nameController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskIntentPage()),
    );
  }

  /// Returns true once the guest has a name we can call them by.
  Future<bool> _askForFullerName(String current, String? message) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: KioskColors.panel,
        title: const Text('Add your last name', style: TextStyle(color: KioskColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ?? 'Someone with that name is already waiting.',
              style: const TextStyle(color: KioskColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              maxLength: KioskSession.guestNameMaxLength,
              style: const TextStyle(color: KioskColors.textPrimary),
              decoration: const InputDecoration(hintText: 'First and last name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Keep just my first name'),
          ),
          TextButton(
            onPressed: () {
              final updated = controller.text.trim();
              if (KioskSession.guestNameErrorFor(updated) != null) return;
              _nameController.text = updated;
              Navigator.of(dialogCtx).pop(true);
            },
            child: const Text('Use this name'),
          ),
        ],
      ),
    );
    controller.dispose();

    return result ?? false;
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
