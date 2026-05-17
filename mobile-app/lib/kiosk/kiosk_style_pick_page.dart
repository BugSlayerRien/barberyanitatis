import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/ai_face_scan_page.dart';
import '../user/api_config.dart';
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
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _styles = [];

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
      final seen = <String>{};
      final mapped = <Map<String, dynamic>>[];
      for (final row in raw) {
        final name = row['style_name']?.toString() ?? 'Style';
        final key = name.toLowerCase();
        if (!seen.add(key)) continue;
        final overlay = OverlayRegistry.resolve(name);
        mapped.add({
          'name': name,
          'description': row['description']?.toString() ?? '',
          'variant_id': row['variant_id'],
          'image': overlay.front,
        });
      }
      setState(() {
        _styles = mapped;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
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

    if (widget.livePreviewNext) {
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

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: widget.livePreviewNext ? 'Pick a style to preview' : 'Pick your haircut',
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _styles.length,
                  itemBuilder: (context, index) {
                    final style = _styles[index];
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
                                  child: image.startsWith('assets/')
                                      ? OverlayPreviewImage(assetPath: image, fit: BoxFit.contain)
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
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
