import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai_face_scan_page.dart';
import 'api_config.dart';
import 'appointments_page.dart';
import 'customer_navigation.dart';
import 'hairstyle_detail_page.dart';
import 'profile_page.dart';
import 'scanner/overlay_preview_image.dart';
import 'scanner/overlay_registry.dart';
import 'user_session.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';

class SavedHaircutsPage extends StatefulWidget {
  const SavedHaircutsPage({super.key});

  @override
  State<SavedHaircutsPage> createState() => _SavedHaircutsPageState();
}

class _SavedHaircutsPageState extends State<SavedHaircutsPage> {
  static final Map<String, Future<Uint8List>> _webImageCache = {};

  late Future<List<Map<String, dynamic>>> _favoritesFuture;

  @override
  void initState() {
    super.initState();
    _favoritesFuture = _loadFavorites();
  }

  Future<void> _refresh() async {
    setState(() {
      _favoritesFuture = _loadFavorites();
    });
    await _favoritesFuture;
  }

  Future<List<Map<String, dynamic>>> _loadFavorites() async {
    if (UserSession.userId == null) {
      return [];
    }

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/favorites.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'listByUser', 'userID': UserSession.userId}),
    );

    if (response.statusCode != 200) {
      return [];
    }

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
    final favorites = (data['favorites'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return favorites.map(_mapFavorite).toList();
  }

  Map<String, dynamic> _mapFavorite(Map<String, dynamic> fav) {
    final name = fav['style_name']?.toString() ?? 'Style';
    final overlay = OverlayRegistry.resolve(name);
    final front = _previewPath(
      fav['front_view_url']?.toString() ?? '',
      overlay.front,
    );
    final side = _previewPath(
      fav['side_view_url']?.toString() ?? '',
      overlay.left,
    );
    final back = _previewPath(
      fav['back_view_url']?.toString() ?? '',
      overlay.right,
    );

    return {
      'name': name,
      'description': fav['description']?.toString() ?? 'Saved haircut',
      'image': front,
      'details':
          'Face shape: ${fav['face_shape'] ?? 'N/A'}\nHair texture: ${fav['hair_texture'] ?? 'N/A'}',
      'rating': '★★★★★',
      'frontViewUrl': front,
      'sideViewUrl': side,
      'backViewUrl': back,
      'variantId': fav['variant_id'],
    };
  }

  /// Prefer bundled overlay art when DB catalog URLs are missing or broken.
  String _previewPath(String raw, String fallback) {
    if (fallback.startsWith('assets/')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty ||
          trimmed.contains('/database/assets/') ||
          trimmed.contains('placeholder')) {
        return fallback;
      }
      final resolved = ApiConfig.resolveImageUrl(trimmed);
      if (resolved.startsWith('assets/')) {
        return resolved;
      }
      // Catalog URLs are often stale; use overlay assets for Saved grid reliability.
      return fallback;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }
    return ApiConfig.resolveImageUrl(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => navigateBackToCustomerHome(context),
        onProfileTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
      ),
      body: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF111111),
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Saved Haircuts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hairstyles you\'ve viewed and liked',
                style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _favoritesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  }

                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'No saved hairstyles yet.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final haircut = items[index];
                      return _HaircutCard(
                        haircut: haircut,
                        imageBuilder: _buildPreviewImage,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Book Your Favorite',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tap on any hairstyle to view details and book an appointment',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 3,
        onTap: (index) {
          if (index == 0) {
            navigateToCustomerHome(context);
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AppointmentsPage()),
            );
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
            );
          } else if (index == 3) {
            // already on Saved
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }

  Widget _buildPreviewImage(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(color: const Color(0xFF111111));
    }
    if (imageUrl.startsWith('assets/')) {
      return OverlayPreviewImage(assetPath: imageUrl, fit: BoxFit.cover);
    }
    if (kIsWeb) {
      return _buildWebImage(imageUrl);
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) {
        return OverlayPreviewImage(
          assetPath: OverlayRegistry.sample.front,
          fit: BoxFit.cover,
        );
      },
    );
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
          return OverlayPreviewImage(
            assetPath: OverlayRegistry.sample.front,
            fit: BoxFit.cover,
          );
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }
}

class _HaircutCard extends StatelessWidget {
  final Map<String, dynamic> haircut;
  final Widget Function(String imageUrl) imageBuilder;

  const _HaircutCard({
    required this.haircut,
    required this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = haircut['image']?.toString() ?? '';
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HairstyleDetailPage(style: haircut),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    imageBuilder(imageUrl),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    haircut['name']?.toString() ?? 'Style',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    haircut['description']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
