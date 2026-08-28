import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/ai_face_scan_page.dart';
import '../user/api_config.dart';
import '../user/feature_flags.dart';
import '../user/scanner/overlay_preview_image.dart';
import '../user/scanner/overlay_registry.dart';
import '../user/user_session.dart';
import 'kiosk_barber_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// Simplified style list for live-preview kiosk path.
class KioskStylePickPage extends StatefulWidget {
  final bool livePreviewNext;

  const KioskStylePickPage({super.key, this.livePreviewNext = false});

  @override
  State<KioskStylePickPage> createState() => _KioskStylePickPageState();
}

class _KioskStylePickPageState extends State<KioskStylePickPage> {
  final _searchController = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _styles = [];
  List<Map<String, dynamic>> _searchResults = [];
  String _searchQuery = '';
  bool _searchLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleStyles =>
      _searchQuery.isNotEmpty ? _searchResults : _styles;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/haircuts.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'listLibrary'}),
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        throw Exception(data['error']?.toString() ?? 'Failed to load styles');
      }
      final raw = (data['hairstyles'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _styles = _mapLibraryRows(raw);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mapLibraryRows(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final mapped = <Map<String, dynamic>>[];
    for (final row in raw) {
      final name = row['style_name']?.toString() ?? 'Style';
      final key = name.toLowerCase();
      if (!seen.add(key)) continue;
      final overlay = OverlayRegistry.resolve(name);
      final frontUrl = row['front_view_url']?.toString() ?? '';
      final image = overlay.front.isNotEmpty
          ? overlay.front
          : (frontUrl.isNotEmpty ? frontUrl : '');
      mapped.add({
        'name': name,
        'description': row['description']?.toString() ?? '',
        'variant_id': row['variant_id'],
        'image': image,
      });
    }
    return mapped;
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    setState(() {
      _searchQuery = trimmed;
      _searchLoading = true;
      _error = null;
    });

    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchLoading = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/haircuts.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'searchLibrary', 'query': trimmed}),
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        throw Exception(data['error']?.toString() ?? 'Search failed');
      }
      final raw = (data['hairstyles'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _searchResults = _mapLibraryRows(raw);
        _searchLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchResults = [];
        _searchLoading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  void _onStyleTap(Map<String, dynamic> style) {
    final variantId = style['variant_id'] as int?;
    if (variantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This style is not available yet')),
      );
      return;
    }

    KioskSession.selectedVariantId = variantId;
    KioskSession.selectedStyleName = style['name']?.toString();
    UserSession.selectedVariantId = variantId;
    UserSession.selectedStyleName = KioskSession.selectedStyleName;

    final preset = {
      'style_name': style['name'],
      'variant_id': variantId,
      'variantId': variantId,
    };

    if (widget.livePreviewNext && kEnableLiveScanner) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AiFaceScanPage(
            kioskMode: true,
            livePreviewOnly: true,
            presetRecommendation: preset,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const KioskBarberPage()),
      );
    }
  }

  Widget _styleImage(String image) {
    if (image.startsWith('assets/')) {
      return OverlayPreviewImage(assetPath: image, fit: BoxFit.contain);
    }
    if (image.startsWith('http')) {
      return Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
        return const Icon(Icons.image_not_supported_outlined, color: Colors.black38);
      });
    }
    return const Icon(Icons.image_not_supported_outlined, color: Colors.black38);
  }

  @override
  Widget build(BuildContext context) {
    final styles = _visibleStyles;

    return KioskScaffold(
      title: widget.livePreviewNext && kEnableLiveScanner
          ? 'Pick a style to preview'
          : 'Pick your haircut',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: KioskColors.textPrimary),
              decoration: kioskInputDecoration(
                hintText: 'Search hairstyles',
                prefixIcon: const Icon(Icons.search, color: KioskColors.textMuted),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: KioskColors.textMuted),
                        onPressed: () {
                          _searchController.clear();
                          _runSearch('');
                        },
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              onChanged: (v) {
                if (v.trim().isEmpty && _searchQuery.isNotEmpty) {
                  _runSearch('');
                }
              },
            ),
          ),
          if (_searchLoading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(color: KioskColors.gold, minHeight: 2),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: KioskColors.gold))
                : _error != null && styles.isEmpty
                    ? Center(child: Text(_error!, style: const TextStyle(color: KioskColors.textMuted)))
                    : styles.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'No styles match "$_searchQuery".'
                                  : 'No hairstyles available.',
                              style: const TextStyle(color: KioskColors.textMuted),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.82,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: styles.length,
                            itemBuilder: (context, index) {
                              final style = styles[index];
                              final image = style['image']?.toString() ?? '';
                              return InkWell(
                                onTap: () => _onStyleTap(style),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: KioskColors.panel,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: KioskColors.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                          child: ColoredBox(
                                            color: Colors.white,
                                            child: image.isNotEmpty
                                                ? _styleImage(image)
                                                : const Icon(Icons.image_not_supported_outlined, color: Colors.black38),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Text(
                                          style['name']?.toString() ?? 'Style',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: KioskColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
