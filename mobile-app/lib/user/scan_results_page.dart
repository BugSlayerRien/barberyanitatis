
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'haircuts_list_page.dart';
import 'dashboard_page.dart';
import 'hairstyle_detail_page.dart';
import 'user_session.dart';

class ScanResultsPage extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>> recommendations;
  final String? summary;

  const ScanResultsPage({super.key, required this.imageUrl, required this.recommendations, this.summary});

  @override
  State<ScanResultsPage> createState() => _ScanResultsPageState();
}

class _ScanResultsPageState extends State<ScanResultsPage> {
  int _selectedIndex = 0;
  String _selectedView = 'front';
  final Map<String, Future<Uint8List>> _webImageCache = {};
  bool _isGenerating = false;
  String? _generatedImageUrl;
  String? _generatedImageBase64;
  bool? _aiStatusOk;

  @override
  void initState() {
    super.initState();
    _loadAiStatus();
  }

  Future<void> _loadAiStatus() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/ai_status.php'));
      if (response.statusCode != 200 || response.body.isEmpty) {
        if (!mounted) return;
        setState(() => _aiStatusOk = false);
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tryon = data['tryon'] as Map<String, dynamic>? ?? {};
      final configured = tryon['configured'] == true;
      if (!mounted) return;
      setState(() => _aiStatusOk = configured);
    } catch (_) {
      if (!mounted) return;
      setState(() => _aiStatusOk = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecommendations = widget.recommendations.isNotEmpty;
    final selected = hasRecommendations ? widget.recommendations[_selectedIndex] : null;
    final previewUrl = _generatedImageUrl ?? _resolvePreviewUrl(selected);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          ),
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
            if ((widget.summary ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Overview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(widget.summary!, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            _buildPreview(previewUrl, selected),
            const SizedBox(height: 16),
            _buildViewSelector(),
            const SizedBox(height: 12),
            if (hasRecommendations)
              const Text('Using pre-generated hairstyle images.', style: TextStyle(color: Colors.white54, fontSize: 12)),
            if (_generatedImageUrl != null || _generatedImageBase64 != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Showing AI-generated preview', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
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
    final reason = selected?['rank_reason']?.toString();
    return Container(
      height: 320,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_generatedImageBase64 != null)
              Image.memory(base64Decode(_generatedImageBase64!), fit: BoxFit.cover)
            else if (previewUrl != null)
              kIsWeb
                  ? _buildWebImage(previewUrl)
                  : Image(image: _buildImageProvider(previewUrl), fit: BoxFit.cover)
            else
              Container(color: const Color(0xFF1A1A1A)),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                ),
              ),
            ),
            Padding(
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
                    if (reason != null && reason.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(reason, style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
        Text('Top ${widget.recommendations.length} recommendations', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...List.generate(widget.recommendations.length, (index) {
          final item = widget.recommendations[index];
          final styleName = item['style_name'] ?? 'Style';
          final score = item['confidence_score'] ?? '';
          final reason = item['rank_reason']?.toString() ?? '';
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: thumbUrl != null
                          ? (kIsWeb
                              ? _buildWebImage(thumbUrl)
                              : Image(image: _buildImageProvider(thumbUrl), fit: BoxFit.cover))
                          : Container(color: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(styleName.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('Score: $score', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        if (reason.isNotEmpty)
                          Text(reason, style: const TextStyle(color: Colors.white54, fontSize: 11)),
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

  Future<void> _generateAiPreview(Map<String, dynamic> selected) async {
    if (_isGenerating) return;
    if (_aiStatusOk == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI preview is unavailable. Check AI status settings.')),
      );
      return;
    }
    final styleName = selected['style_name']?.toString() ?? 'hairstyle';
    final imageUrl = widget.imageUrl;
    if (imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing scan image for AI preview.')),
      );
      return;
    }
    setState(() => _isGenerating = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_tryon.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'instantId',
          'prompt': 'Apply hairstyle: $styleName',
          'imageUrl': imageUrl,
          'negativePrompt': 'blurry, low quality, distorted face',
        }),
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
        final error = data['error']?.toString() ?? 'AI preview failed.';
        final details = data['details']?.toString();
        final hint = data['hint']?.toString();
        final messageParts = [error];
        if (details != null && details.isNotEmpty) {
          messageParts.add(details);
        }
        if (hint != null && hint.isNotEmpty) {
          messageParts.add(hint);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${messageParts.join(' ')} (${response.statusCode})')),
        );
        return;
      }
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      final generatedUrl = data['imageUrl']?.toString();
      final generatedBase64 = data['imageBase64']?.toString();
      if ((generatedUrl == null || generatedUrl.isEmpty) && (generatedBase64 == null || generatedBase64.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI preview did not return an image.')),
        );
        return;
      }
      setState(() {
        _generatedImageUrl = generatedUrl;
        _generatedImageBase64 = generatedBase64;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI preview failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
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
      return _resolveImage(widget.imageUrl);
    }
    final key = _selectedView == 'front'
        ? 'front_view_url'
        : _selectedView == 'side'
            ? 'side_view_url'
            : 'back_view_url';
    return _resolveImage(selected[key]) ?? _resolveImage(widget.imageUrl);
  }

  String? _resolveImage(dynamic value) {
    final url = value?.toString() ?? '';
    if (url.isEmpty) {
      return null;
    }
    if (url.startsWith('assets/')) {
      return url;
    }
    return ApiConfig.resolveImageUrl(url);
  }

  ImageProvider _buildImageProvider(String url) {
    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    return NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.prefer);
  }

  Future<Uint8List> _fetchWebImageBytes(String url) {
    return _webImageCache.putIfAbsent(url, () async {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Image load failed (${response.statusCode})');
      }
      return response.bodyBytes;
    });
  }

  Widget _buildWebImage(String url) {
    return FutureBuilder<Uint8List>(
      future: _fetchWebImageBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(color: const Color(0xFF111111));
        }
        if (!snapshot.hasData) {
          return Container(color: const Color(0xFF111111));
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
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
