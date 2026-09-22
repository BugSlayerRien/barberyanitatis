import 'package:flutter/material.dart';

import '../api_config.dart';
import '../app_brand.dart';
import '../customer_api.dart';
import '../scanner/overlay_preview_image.dart';

/// Bottom sheet listing library styles that suit [hairTexture], minus the ones
/// already recommended ([excludeStyleNames], compared lowercase). Returns the
/// picked library row, or null if dismissed.
Future<Map<String, dynamic>?> showLibraryStylePicker(
  BuildContext context, {
  required String hairTexture,
  Set<String> excludeStyleNames = const {},
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _LibraryStylePickerSheet(
      hairTexture: hairTexture,
      excludeStyleNames: excludeStyleNames,
    ),
  );
}

class _LibraryStylePickerSheet extends StatefulWidget {
  final String hairTexture;
  final Set<String> excludeStyleNames;

  const _LibraryStylePickerSheet({
    required this.hairTexture,
    required this.excludeStyleNames,
  });

  @override
  State<_LibraryStylePickerSheet> createState() => _LibraryStylePickerSheetState();
}

class _LibraryStylePickerSheetState extends State<_LibraryStylePickerSheet> {
  List<Map<String, dynamic>> _styles = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await CustomerApi.postDecoded('haircuts.php', {
        'action': 'listLibrary',
        'hairTexture': widget.hairTexture,
      });
      final rows = (data['hairstyles'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) {
            final variantId = int.tryParse('${row['variant_id'] ?? ''}') ?? 0;
            final name = row['style_name']?.toString().trim().toLowerCase() ?? '';
            return variantId > 0 &&
                name.isNotEmpty &&
                !widget.excludeStyleNames.contains(name);
          })
          .toList();
      if (!mounted) return;
      setState(() {
        _styles = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the library. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleStyles {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _styles;
    return _styles
        .where((row) => (row['style_name']?.toString().toLowerCase() ?? '').contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.grid_view_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Library',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Styles for ${widget.hairTexture.toLowerCase()} hair, generated on your current scan.',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search styles',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _body(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(ScrollController scrollController) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final styles = _visibleStyles;
    if (styles.isEmpty) {
      return Center(
        child: Text(
          _styles.isEmpty
              ? 'Every style for your hair texture is already in your recommendations.'
              : 'No styles match "$_query".',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: styles.length,
      itemBuilder: (context, index) => _card(styles[index]),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final name = row['style_name']?.toString() ?? 'Style';
    final image = row['front_view_url']?.toString().trim() ?? '';
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(row),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.white,
                child: _thumbnail(image),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(String image) {
    const fallback = Center(child: Icon(Icons.content_cut, color: AppBrand.textMuted));
    if (image.isEmpty) return fallback;
    if (image.startsWith('assets/')) {
      return OverlayPreviewImage(assetPath: image, fit: BoxFit.contain, errorWidget: fallback);
    }
    return Image.network(
      ApiConfig.resolveImageUrl(image),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
