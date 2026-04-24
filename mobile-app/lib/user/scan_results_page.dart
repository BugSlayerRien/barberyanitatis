import 'package:flutter/material.dart';

import 'api_config.dart';
import 'ai_funnel_service.dart';
import 'dashboard_page.dart';
import 'hairstyle_detail_page.dart';
import 'haircuts_list_page.dart';
import 'user_session.dart';

class ScanResultsPage extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>> recommendations;
  final String? summary;

  const ScanResultsPage({
    super.key,
    required this.imageUrl,
    required this.recommendations,
    this.summary,
  });

  @override
  State<ScanResultsPage> createState() => _ScanResultsPageState();
}

class _ScanResultsPageState extends State<ScanResultsPage> {
  int _selectedIndex = 0;
  String _selectedView = 'front';

  @override
  Widget build(BuildContext context) {
    final hasItems = widget.recommendations.isNotEmpty;
    final current = hasItems ? widget.recommendations[_selectedIndex] : null;
    final previewUrl = _selectedPreviewUrl(current);

    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'AI Hair Recommendations',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((widget.summary ?? '').trim().isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF131313),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  widget.summary!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ),
            if ((widget.summary ?? '').trim().isNotEmpty) const SizedBox(height: 14),
            _previewCard(previewUrl, current),
            const SizedBox(height: 12),
            _viewSelector(),
            const SizedBox(height: 14),
            const Text(
              'Recommended styles',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: hasItems ? _listRecommendations() : _emptyState(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: hasItems
                  ? () async {
                      final style = _toStyleMap(widget.recommendations[_selectedIndex]);
                      UserSession.selectedVariantId = style['variantId'] as int?;
                      UserSession.selectedStyleName = style['name']?.toString();
                      UserSession.selectedEstimatedMinutes = style['estimatedMinutes'] as int?;

                      final userId = UserSession.userId;
                      final variantId = UserSession.selectedVariantId;
                      if (userId != null && variantId != null) {
                        await AiFunnelService.saveSelection(
                          scanSessionId: UserSession.ensureScanSessionId(),
                          userId: userId,
                          variantId: variantId,
                          styleName: UserSession.selectedStyleName ?? 'Style',
                          faceShape: UserSession.lastScan?['faceShape']?.toString(),
                          hairTexture: UserSession.lastScan?['hairTexture']?.toString(),
                          hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
                          hairLength: UserSession.lastScan?['hairLength']?.toString(),
                          estimatedMinutes: UserSession.selectedEstimatedMinutes,
                        );
                      }

                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)),
                      );
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Use selected style'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HaircutsListPage()),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: Colors.white,
              ),
              child: const Text('Browse full library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(String? previewUrl, Map<String, dynamic>? current) {
    final styleName = current?['style_name']?.toString() ?? current?['styleName']?.toString() ?? 'No style selected';
    final confidence = _asDouble(current?['confidence_score']);

    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (previewUrl != null && previewUrl.isNotEmpty)
              Image.network(
                previewUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.65), Colors.transparent],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      styleName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    if (confidence != null)
                      Text(
                        'Match confidence: ${(confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewSelector() {
    return Row(
      children: [
        _viewButton('Front', 'front'),
        const SizedBox(width: 8),
        _viewButton('Right', 'right'),
        const SizedBox(width: 8),
        _viewButton('Left', 'left'),
      ],
    );
  }

  Widget _viewButton(String label, String value) {
    final selected = _selectedView == value;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _selectedView = value),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.transparent,
          foregroundColor: selected ? Colors.black : Colors.white,
          side: BorderSide(color: selected ? Colors.white : Colors.white24),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _listRecommendations() {
    return ListView.separated(
      itemCount: widget.recommendations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = widget.recommendations[index];
        final selected = index == _selectedIndex;
        final title = item['style_name']?.toString() ?? item['styleName']?.toString() ?? 'Style';
        final subtitle = item['hair_texture']?.toString() ?? item['face_shape']?.toString() ?? 'Recommended style';

        return InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1C1C1C) : const Color(0xFF121212),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Colors.white54 : Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: Center(
                    child: Text('${index + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: const Text(
        'No recommendations available yet. Try scanning again with better lighting or choose from library.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  String? _selectedPreviewUrl(Map<String, dynamic>? item) {
    if (item == null) {
      return null;
    }

    if (_selectedView == 'front') {
      return _resolveImage(item['front_view_url'] ?? item['frontViewUrl']);
    }
    if (_selectedView == 'left') {
      return _resolveImage(item['side_view_url'] ?? item['sideViewUrl']);
    }
    return _resolveImage(item['back_view_url'] ?? item['backViewUrl'] ?? item['side_view_url'] ?? item['sideViewUrl']);
  }

  String? _resolveImage(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return ApiConfig.resolveImageUrl(raw);
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  Map<String, dynamic> _toStyleMap(Map<String, dynamic> recommendation) {
    return {
      'name': recommendation['style_name']?.toString() ?? recommendation['styleName']?.toString() ?? 'Style',
      'description': recommendation['description']?.toString() ?? 'AI recommended style',
      'image': _resolveImage(recommendation['front_view_url'] ?? recommendation['frontViewUrl']) ?? '',
      'details': 'Face shape: ${recommendation['face_shape'] ?? 'N/A'}\nHair texture: ${recommendation['hair_texture'] ?? 'N/A'}',
      'rating': _asDouble(recommendation['confidence_score']) ?? 4.0,
      'frontViewUrl': _resolveImage(recommendation['front_view_url'] ?? recommendation['frontViewUrl']) ?? '',
      'sideViewUrl': _resolveImage(recommendation['side_view_url'] ?? recommendation['sideViewUrl']) ?? '',
      'backViewUrl': _resolveImage(recommendation['back_view_url'] ?? recommendation['backViewUrl']) ?? '',
      'variantId': recommendation['variant_id'] ?? recommendation['variantId'],
      'estimatedMinutes': _asInt(recommendation['estimated_minutes'] ?? recommendation['estimatedMinutes']),
    };
  }

  int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }
}
