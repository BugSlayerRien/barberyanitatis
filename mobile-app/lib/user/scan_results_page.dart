import 'package:flutter/material.dart';
import 'api_config.dart';
import 'haircuts_list_page.dart';
import 'hairstyle_detail_page.dart';
import 'user_session.dart';

class ScanResultsPage extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>> recommendations;

  const ScanResultsPage({super.key, required this.imageUrl, required this.recommendations});

  @override
  State<ScanResultsPage> createState() => _ScanResultsPageState();
}

class _ScanResultsPageState extends State<ScanResultsPage> {
  int _selectedIndex = 0;
  String _selectedView = 'front';

  @override
  Widget build(BuildContext context) {
    final hasRecommendations = widget.recommendations.isNotEmpty;
    final selected = hasRecommendations ? widget.recommendations[_selectedIndex] : null;
    final previewUrl = _resolvePreviewUrl(selected);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('AI Recommendations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your AI hairstyle preview',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Preview the recommended hairstyle from different angles. You can also choose another style below.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 20),
            _buildPreview(previewUrl, selected),
            const SizedBox(height: 16),
            _buildViewSelector(),
            const SizedBox(height: 20),
            if (!hasRecommendations)
              _buildEmptyState(context)
            else
              _buildRecommendationsList(context),
            const SizedBox(height: 24),
            if (hasRecommendations)
              ElevatedButton(
                onPressed: () {
                  final style = _toStyleMap(selected!);
                  UserSession.selectedVariantId = style['variantId'] as int?;
                  UserSession.selectedStyleName = style['name'] as String?;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Use this hairstyle'),
              ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HaircutsListPage()),
                );
              },
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Choose from full library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(String? previewUrl, Map<String, dynamic>? selected) {
    final styleName = (selected?['style_name'] ?? 'Preview') as String;
    final score = selected?['confidence_score'];
    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        image: previewUrl != null
            ? DecorationImage(
                image: NetworkImage(previewUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.55), Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(styleName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              if (score != null)
                Text('Match: ${(double.tryParse(score.toString()) ?? 0) * 100.0 ~/ 1}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewSelector() {
    return Row(
      children: [
        _viewButton('Front', 'front'),
        const SizedBox(width: 8),
        _viewButton('Side', 'side'),
        const SizedBox(width: 8),
        _viewButton('Back', 'back'),
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

  Widget _buildRecommendationsList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Top 5 recommendations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...List.generate(widget.recommendations.length, (index) {
          final item = widget.recommendations[index];
          final styleName = item['style_name'] ?? 'Style';
          final score = item['confidence_score'] ?? '';
          final thumbUrl = _resolveImage(item['front_view_url']);

          return GestureDetector(
            onTap: () => setState(() => _selectedIndex = index),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: index == _selectedIndex ? Colors.white10 : const Color(0xFF161616),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: index == _selectedIndex ? Colors.white24 : Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      image: thumbUrl != null
                          ? DecorationImage(image: NetworkImage(thumbUrl), fit: BoxFit.cover)
                          : null,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(styleName.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('Score: $score', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No recommendations returned', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Choose from the haircut library to preview a style.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String? _resolvePreviewUrl(Map<String, dynamic>? selected) {
    if (selected == null) {
      return null;
    }
    final key = _selectedView == 'front'
        ? 'front_view_url'
        : _selectedView == 'side'
            ? 'side_view_url'
            : 'back_view_url';
    return _resolveImage(selected[key]);
  }

  String? _resolveImage(dynamic value) {
    final url = value?.toString() ?? '';
    if (url.isEmpty) {
      return null;
    }
    return ApiConfig.resolveImageUrl(url);
  }

  Map<String, dynamic> _toStyleMap(Map<String, dynamic> recommendation) {
    return {
      'name': recommendation['style_name']?.toString() ?? 'Style',
      'description': 'AI recommended based on your scan',
      'image': _resolveImage(recommendation['front_view_url']) ?? '',
      'details': 'Face shape: ${recommendation['face_shape'] ?? 'N/A'}\nHair texture: ${recommendation['hair_texture'] ?? 'N/A'}',
      'rating': _scoreToRating(recommendation['confidence_score']),
      'frontViewUrl': _resolveImage(recommendation['front_view_url']) ?? '',
      'sideViewUrl': _resolveImage(recommendation['side_view_url']) ?? '',
      'backViewUrl': _resolveImage(recommendation['back_view_url']) ?? '',
      'variantId': recommendation['variant_id'],
    };
  }

  String _scoreToRating(dynamic score) {
    final value = double.tryParse(score?.toString() ?? '') ?? 0.0;
    final stars = (value * 5).clamp(1, 5).round();
    return '★' * stars + '☆' * (5 - stars);
  }
}
