import 'package:flutter/material.dart';

import 'customer_api.dart';
import 'user_session.dart';

/// First-time (or missing profile) hair texture picker shown before browsing cuts.
class HairTextureOnboarding extends StatefulWidget {
  final VoidCallback onCompleted;

  const HairTextureOnboarding({super.key, required this.onCompleted});

  static const options = ['Straight', 'Wavy', 'Curly'];

  @override
  State<HairTextureOnboarding> createState() => _HairTextureOnboardingState();
}

class _HairTextureOnboardingState extends State<HairTextureOnboarding> {
  String? _selected;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await UserSession.savePreferredHairTexture(_selected!);

      final userId = UserSession.userId;
      if (userId != null && userId > 0) {
        await CustomerApi.postDecoded('profile.php', {
          'action': 'update',
          'userID': userId,
          'fullName': UserSession.fullName ?? 'Customer',
          'hairTexture': _selected!,
        });
      }

      if (!mounted) return;
      widget.onCompleted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save hair texture: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.92),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'What is your hair texture?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'We will show haircuts that work best for your texture. You can change this anytime in Profile.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  ...HairTextureOnboarding.options.map((option) {
                    final selected = _selected == option;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: _saving ? null : () => setState(() => _selected = option),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected ? Colors.white : const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected ? Colors.white : Colors.white24,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.check_circle : Icons.circle_outlined,
                                color: selected ? Colors.black : Colors.white54,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                option,
                                style: TextStyle(
                                  color: selected ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    // Disabled until a choice is made. There is no pre-selected
                    // option any more: defaulting to "Straight" meant a
                    // distracted tap on Continue silently saved a texture the
                    // user never picked, and that value then drove every
                    // recommendation and fit badge.
                    onPressed: (_saving || _selected == null) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  // Skip is a real answer: "I don't know" is common, and
                  // blocking the app behind this question is worse than having
                  // no texture. The Library then shows a "set your hair type"
                  // prompt instead of silently showing no fit guidance.
                  TextButton(
                    onPressed: _saving ? null : widget.onCompleted,
                    child: const Text(
                      "Skip — I'm not sure",
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
