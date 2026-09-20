import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'app_brand.dart';
import 'services/saved_previews_service.dart';
import 'widgets/app_top_bar.dart';

/// Full view of one saved AI look: all three generated angles, not just the
/// front thumbnail the Saved grid shows.
///
/// Images live under the scan session that produced them, so a look can outlive
/// its files. A missing image is reported plainly rather than falling back to a
/// catalog photo -- showing a stock haircut where the customer expects their own
/// face would be worse than an honest empty state.
class SavedLookDetailPage extends StatefulWidget {
  final Map<String, dynamic> look;

  const SavedLookDetailPage({super.key, required this.look});

  @override
  State<SavedLookDetailPage> createState() => _SavedLookDetailPageState();
}

class _SavedLookDetailPageState extends State<SavedLookDetailPage> {
  static final Map<String, Future<Uint8List>> _webImageCache = {};

  static const _angleLabels = ['Front', 'Left', 'Right'];

  int _angleIndex = 0;
  bool _deleting = false;

  String get _styleName {
    final name = widget.look['style_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Saved look' : name;
  }

  /// Angle URLs in [_angleLabels] order. An entry is empty when that angle was
  /// never stored.
  List<String> get _angleUrls => [
        widget.look['front_url']?.toString().trim() ?? '',
        widget.look['left_url']?.toString().trim() ?? '',
        widget.look['right_url']?.toString().trim() ?? '',
      ];

  Future<void> _confirmDelete() async {
    final savedId = (widget.look['saved_preview_id'] as num?)?.toInt() ?? 0;
    if (savedId <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppBrand.panel,
        shape: RoundedRectangleBorder(
          borderRadius: AppBrand.radiusMd,
          side: const BorderSide(color: AppBrand.border),
        ),
        title: const Text(
          'Remove saved look?',
          style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove "$_styleName" from your saved looks?',
          style: const TextStyle(color: AppBrand.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppBrand.accent),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppBrand.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await SavedPreviewsService.delete(savedId);
      if (!mounted) return;
      // true tells the Saved page to refresh its list.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove the saved look: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = _angleUrls;
    final current = urls[_angleIndex];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(false),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _styleName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(),
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF111111),
                  child: _buildAngleImage(current),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 8,
                children: List.generate(_angleLabels.length, (i) {
                  final hasImage = urls[i].isNotEmpty;
                  return ChoiceChip(
                    label: Text(_angleLabels[i]),
                    selected: _angleIndex == i,
                    // A never-stored angle is not selectable: switching to it
                    // would show the empty state for no reason.
                    onSelected: hasImage ? (_) => setState(() => _angleIndex = i) : null,
                    selectedColor: Colors.white,
                    disabledColor: const Color(0xFF151515),
                    backgroundColor: const Color(0xFF1A1A1A),
                    labelStyle: TextStyle(
                      color: !hasImage
                          ? Colors.white24
                          : (_angleIndex == i ? Colors.black : Colors.white70),
                      fontSize: 12,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _deleting ? null : _confirmDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppBrand.danger,
                  side: const BorderSide(color: AppBrand.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppBrand.danger,
                        ),
                      )
                    : const Icon(Icons.delete_outline, size: 18),
                label: Text(_deleting ? 'Removing...' : 'Remove from saved'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    final face = widget.look['face_shape']?.toString().trim() ?? '';
    final texture = widget.look['hair_texture']?.toString().trim() ?? '';
    if (face.isNotEmpty) parts.add('Face: $face');
    if (texture.isNotEmpty) parts.add('Hair: $texture');
    final created = widget.look['created_at']?.toString() ?? '';
    final day = DateTime.tryParse(created);
    if (day != null) {
      parts.add('Saved ${day.year}-${_two(day.month)}-${_two(day.day)}');
    }
    return parts.isEmpty ? 'AI try-on preview' : parts.join('  ·  ');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  Widget _buildAngleImage(String rawUrl) {
    if (rawUrl.isEmpty) {
      return _unavailable('This angle was not saved for this look.');
    }
    final url = ApiConfig.resolveImageUrl(rawUrl);
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: _webImageCache.putIfAbsent(url, () async {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode != 200) {
            throw Exception('HTTP ${response.statusCode}');
          }
          return response.bodyBytes;
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _unavailable('This preview is no longer available.');
          }
          return Image.memory(snapshot.data!, fit: BoxFit.contain);
        },
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(color: Colors.white24));
      },
      errorBuilder: (_, __, ___) => _unavailable('This preview is no longer available.'),
    );
  }

  Widget _unavailable(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: Colors.white24, size: 40),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
