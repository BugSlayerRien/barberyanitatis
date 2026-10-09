import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../user/api_config.dart';
import '../user/app_brand.dart';
import '../user/user_session.dart';

/// Where a barber adds a haircut to the shop's catalogue.
///
/// The panel's objection was that the admin portal belongs to the owner, who
/// may not know haircuts — the barber does. So the questions here are the ones
/// a barber already answers at the chair: how high the fade sits, which
/// guards, how much is left on top, what happens at the back. The server
/// composes the AI prompt from those answers, so nobody writes a prompt.
///
/// A submission lands as "Pending review": the knowledge comes from the
/// barber, the decision about what the shop sells stays with the owner.
class BarberHairstyleFormPage extends StatefulWidget {
  const BarberHairstyleFormPage({super.key});

  @override
  State<BarberHairstyleFormPage> createState() => _BarberHairstyleFormPageState();
}

class _BarberHairstyleFormPageState extends State<BarberHairstyleFormPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _sides = TextEditingController();
  final _guards = TextEditingController();
  final _top = TextEditingController();
  final _fringe = TextEditingController();
  final _back = TextEditingController();
  final _neckline = TextEditingController();
  final _finish = TextEditingController();
  final _instructions = TextEditingController();
  final _minutes = TextEditingController(text: '40');

  final Set<String> _textures = {};
  int _minLengthLevel = 1;
  final Map<String, XFile> _photos = {};

  bool _submitting = false;
  bool _loadingMine = true;
  List<Map<String, dynamic>> _mine = [];
  String? _error;

  static const _slots = ['front', 'side', 'back'];

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _description, _sides, _guards, _top, _fringe,
      _back, _neckline, _finish, _instructions, _minutes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _identity() => {
        'barberID': UserSession.userId ?? 0,
        'email': (UserSession.email ?? '').trim(),
      };

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/barber_hairstyles.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({...body, ..._identity()}),
    );
    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Request failed');
    }
    return data;
  }

  Future<void> _loadMine() async {
    try {
      final data = await _post({'action': 'listMyHairstyles'});
      if (!mounted) return;
      setState(() {
        _mine = (data['hairstyles'] as List<dynamic>? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _loadingMine = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMine = false);
    }
  }

  Future<void> _pickPhoto(String slot) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() => _photos[slot] = image);
  }

  /// The same rules the server enforces, checked here first so the barber is
  /// told what is missing instead of watching a request fail.
  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Give the haircut a name.';
    if (_textures.isEmpty) return 'Pick at least one hair texture this suits.';
    if (_sides.text.trim().isEmpty) {
      return 'Describe the sides — the fade or taper decides the cut.';
    }
    if (_top.text.trim().isEmpty) {
      return 'Say how much length is left on top.';
    }
    // Photos are optional. A described cut already works: the app shows a
    // placeholder tile and the AI preview is built from the description, so
    // turning away a barber who has the knowledge but not three photos would
    // cost the shop a haircut for no reason.
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final photos = <String, String>{};
      for (final slot in _slots) {
        final picked = _photos[slot];
        if (picked == null) continue;
        photos[slot] = base64Encode(await picked.readAsBytes());
      }

      final data = await _post({
        'action': 'submitHairstyle',
        'styleName': _name.text.trim(),
        'description': _description.text.trim(),
        'hairTextures': _textures.toList(),
        'sides': _sides.text.trim(),
        'guards': _guards.text.trim(),
        'top': _top.text.trim(),
        'fringe': _fringe.text.trim(),
        'back': _back.text.trim(),
        'neckline': _neckline.text.trim(),
        'finish': _finish.text.trim(),
        'barberInstructions': _instructions.text.trim(),
        'minLengthLevel': _minLengthLevel,
        'estimatedMinutes': int.tryParse(_minutes.text.trim()) ?? 40,
        'photos': photos,
      });
      if (!mounted) return;

      setState(() => _submitting = false);
      await _showSubmittedDialog(data['aiPrompt']?.toString() ?? '');
      if (!mounted) return;

      _clearForm();
      await _loadMine();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _clearForm() {
    for (final c in [
      _name, _description, _sides, _guards, _top, _fringe,
      _back, _neckline, _finish, _instructions,
    ]) {
      c.clear();
    }
    setState(() {
      _textures.clear();
      _photos.clear();
      _minLengthLevel = 1;
      _minutes.text = '40';
    });
  }

  /// Shows the barber the prompt their answers produced.
  ///
  /// They described the cut; this is what the image model will be told. Worth
  /// seeing, because it is the one place a wrong answer becomes visible before
  /// a customer gets an odd preview.
  Future<void> _showSubmittedDialog(String prompt) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppBrand.surface,
        title: const Text(
          'Sent to the owner',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The owner reviews it before customers see it. You can follow '
                'its status at the bottom of this page.',
                style: TextStyle(color: Colors.white70, height: 1.45),
              ),
              if (prompt.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'What the AI will be told',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppBrand.panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppBrand.border),
                  ),
                  child: Text(
                    prompt,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppBar(
        backgroundColor: AppBrand.panel,
        foregroundColor: Colors.white,
        title: const Text('Suggest a haircut'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _intro(),
            const SizedBox(height: 16),
            _section('The cut', [
              _field(_name, 'Name', hint: 'Pineapple, Low Taper, Two Block…'),
              _field(_description, 'Short description for customers',
                  hint: 'Who it suits and how it wears', lines: 2),
            ]),
            const SizedBox(height: 14),
            _section('How you cut it', [
              _field(_sides, 'Sides and back *',
                  hint: 'low fade from the temple down, clean taper at the ear',
                  lines: 2),
              _field(_guards, 'Clipper guards', hint: 'a #1 blending to a #3'),
              _field(_top, 'Length on top *',
                  hint: 'three inches left on top, point-cut for texture',
                  lines: 2),
              _field(_fringe, 'Fringe or part', hint: 'blunt fringe to the brow'),
              _field(_back, 'What happens at the back',
                  hint: 'tapered to the nape, nothing over the collar',
                  lines: 2,
                  note: 'Left blank we assume the back matches the sides. '
                      'Saying it is better — an unsaid back is where the AI '
                      'invents length.'),
              _field(_neckline, 'Neckline', hint: 'blocked / tapered / rounded'),
              _field(_finish, 'Finish and product', hint: 'matte clay, dried forward'),
            ]),
            const SizedBox(height: 14),
            _section('Who it suits', [
              const Text(
                'Hair texture *',
                style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final texture in ['Straight', 'Wavy', 'Curly'])
                    FilterChip(
                      label: Text(texture),
                      selected: _textures.contains(texture),
                      onSelected: (on) => setState(() {
                        on ? _textures.add(texture) : _textures.remove(texture);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Pick every texture you would actually cut this on. A customer '
                'whose texture is not here will not be recommended it.',
                style: TextStyle(color: AppBrand.textMuted, fontSize: 11.5, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Shortest hair this works on',
                style: TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Any')),
                  ButtonSegment(value: 1, label: Text('Short')),
                  ButtonSegment(value: 2, label: Text('Medium')),
                  ButtonSegment(value: 3, label: Text('Long')),
                ],
                selected: {_minLengthLevel},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _minLengthLevel = s.first),
              ),
              const SizedBox(height: 6),
              const Text(
                'Customers with shorter hair are warned, never blocked.',
                style: TextStyle(color: AppBrand.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              _field(_minutes, 'Chair time in minutes', keyboard: TextInputType.number),
              _field(_instructions, 'Notes for whoever cuts it',
                  hint: 'Anything you would tell another barber', lines: 3),
            ]),
            const SizedBox(height: 14),
            _photoSection(),
            const SizedBox(height: 18),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x1FD93B30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppBrand.poleRedText.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppBrand.poleRedText, fontSize: 12.5, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_submitting ? 'Sending…' : 'Send to the owner'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 28),
            _mineSection(),
          ],
        ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.accentTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppBrand.accent.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Describe the cut the way you would to another barber. We build the AI '
        'preview from your answers — you never have to write a prompt. The '
        'owner publishes it before customers see it.',
        style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? note,
    int lines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            maxLines: lines,
            keyboardType: keyboard,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              labelStyle: const TextStyle(color: AppBrand.textMuted, fontSize: 13),
              hintStyle: const TextStyle(color: AppBrand.textSubtle, fontSize: 12.5),
              filled: true,
              fillColor: AppBrand.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppBrand.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppBrand.border),
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note,
              style: const TextStyle(color: AppBrand.textMuted, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _photoSection() {
    final missing = _slots.where((slot) => !_photos.containsKey(slot)).length;

    return _section('Reference photos', [
      const Text(
        'One of each angle, from a cut you have done. Customers see these in '
        'the library.',
        style: TextStyle(color: AppBrand.textMuted, fontSize: 11.5, height: 1.4),
      ),
      if (missing > 0) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppBrand.accentTint,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppBrand.accent.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'Optional — you can send this without photos. The haircut shows a '
            'placeholder until someone adds them, and the AI preview works '
            'either way.',
            style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          for (final slot in _slots) ...[
            Expanded(child: _photoTile(slot)),
            if (slot != _slots.last) const SizedBox(width: 8),
          ],
        ],
      ),
    ]);
  }

  Widget _photoTile(String slot) {
    final picked = _photos[slot];
    return InkWell(
      onTap: () => _pickPhoto(slot),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppBrand.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: picked == null ? AppBrand.border : AppBrand.success,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              picked == null ? Icons.add_a_photo_outlined : Icons.check_circle,
              color: picked == null ? AppBrand.textMuted : AppBrand.success,
              size: 22,
            ),
            const SizedBox(height: 6),
            Text(
              slot[0].toUpperCase() + slot.substring(1),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (picked != null)
              const Text(
                'Tap to change',
                style: TextStyle(color: AppBrand.textMuted, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mineSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your submissions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
        if (_loadingMine)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(color: Colors.white24),
            ),
          )
        else if (_mine.isEmpty)
          const Text(
            'Nothing yet. The haircuts you send appear here with their status.',
            style: TextStyle(color: AppBrand.textMuted, fontSize: 12.5),
          )
        else
          ..._mine.map(_submissionCard),
      ],
    );
  }

  Widget _submissionCard(Map<String, dynamic> row) {
    final status = row['review_status']?.toString() ?? 'PendingReview';
    final (label, color) = switch (status) {
      'Published' => ('Published', AppBrand.success),
      'Rejected' => ('Rejected', AppBrand.poleRedText),
      _ => ('Pending review', AppBrand.warning),
    };
    final variants = (row['variant_count'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppBrand.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['style_name']?.toString() ?? 'Haircut',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['style_code'] ?? ''} · $variants '
                  '${variants == 1 ? 'variant' : 'variants'}',
                  style: const TextStyle(color: AppBrand.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
