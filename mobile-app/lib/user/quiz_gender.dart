import 'package:flutter/material.dart';
import 'quiz_hairtype.dart';

class QuizGenderPage extends StatefulWidget {
  const QuizGenderPage({super.key});

  @override
  State<QuizGenderPage> createState() => _QuizGenderPageState();
}

class _QuizGenderPageState extends State<QuizGenderPage> {
  String? _gender; // 'boy' or 'girl'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizHairTypePage()));
                        },
                        child: const Text('Skip', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ],
                  ),
                  // Progress bar
                  const LinearProgressIndicator(
                    value: 1 / 3,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('Step 1 of 3', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text('WELCOME', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  const Text('Tell us about you', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 18),

                  // Option tiles
                  _optionTile('Boy', 'boy', Icons.male),
                  const SizedBox(height: 10),
                  _optionTile('Girl', 'girl', Icons.female),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _gender == null
                              ? null
                              : () {
                                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizHairTypePage()));
                                },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile(String label, String value, IconData icon) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2A2A) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.white : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white70),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 16))),
            if (selected) const Icon(Icons.check_circle, color: Colors.white)
          ],
        ),
      ),
    );
  }
}

// End of file
