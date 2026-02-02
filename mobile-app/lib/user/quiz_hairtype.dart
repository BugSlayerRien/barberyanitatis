import 'package:flutter/material.dart';
import 'quiz_upload.dart';

class QuizHairTypePage extends StatefulWidget {
  const QuizHairTypePage({super.key});

  @override
  State<QuizHairTypePage> createState() => _QuizHairTypePageState();
}

class _QuizHairTypePageState extends State<QuizHairTypePage> {
  String? _hairType; // 'straight', 'curly', 'wavy'

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
                  // Progress bar
                  const LinearProgressIndicator(
                    value: 2 / 3,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('Step 2 of 3', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text('HAIR TYPE', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  _option('Straight', 'straight'),
                  const SizedBox(height: 10),
                  _option('Curly', 'curly'),
                  const SizedBox(height: 10),
                  _option('Wavy', 'wavy'),
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
                          onPressed: _hairType == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizUploadPage())),
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

  Widget _option(String label, String value) {
    final selected = _hairType == value;
    return GestureDetector(
      onTap: () => setState(() => _hairType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A2A2A) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.white : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(
              value == 'straight' ? Icons.horizontal_rule : (value == 'curly' ? Icons.auto_fix_normal : Icons.waves),
              color: selected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 16))),
            if (selected) const Icon(Icons.check_circle, color: Colors.white)
          ],
        ),
      ),
    );
  }
}
