import 'dart:convert';


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ai_funnel_service.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'customer_navigation.dart';
import 'saved_haircuts_page.dart';
import 'suggested_appointment_page.dart';
import 'user_session.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'api_config.dart';
import 'services/booking_draft_service.dart';
import 'ai_face_scan_page.dart';
import 'hairstyle_detail_page.dart';
import 'profile_page.dart';
import 'scanner/overlay_preview_image.dart';
import 'scanner/overlay_registry.dart';

class HaircutsListPage extends StatefulWidget {
  const HaircutsListPage({super.key});

  @override
  State<HaircutsListPage> createState() => _HaircutsListPageState();
}

class _HaircutsListPageState extends State<HaircutsListPage> {
  final Map<String, Future<Uint8List>> _webImageCache = {};
  final TextEditingController _searchController = TextEditingController();
  static const String _librarySampleHairFront =
      'assets/images/overlays/blowout_taper/blowout_taper_front.png';

  List<Map<String, dynamic>> _allStyles = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _categories = const ['All'];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _loading = true;
  bool _searchLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCategory();
    _loadStyles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      final variants = (data['hairstyles'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final mapped = _dedupeStyles(
        variants.map(_mapVariant).where(_hasDisplayableAssets).toList(),
      );
      if (!mounted) return;
      setState(() {
        _searchResults = mapped;
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searchLoading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _initCategory() async {
    final preferred = await UserSession.loadPreferredHairTexture();
    if (preferred != null && preferred.isNotEmpty && mounted) {
      setState(() => _selectedCategory = preferred);
    }
  }

  Future<void> _loadStyles() async {
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
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load hairstyles.';
          _loading = false;
        });
        return;
      }

      final variants = (data['hairstyles'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      _logLibraryAudit(variants);
      final mapped = _dedupeStyles(
        variants.map(_mapVariant).where(_hasDisplayableAssets).toList(),
      );
      const ordered = ['Straight', 'Wavy', 'Curly'];
      final categories = [...ordered];

      setState(() {
        _allStyles = mapped;
        _categories = categories;
        if (!_categories.contains(_selectedCategory)) {
          _selectedCategory = _categories.isNotEmpty ? _categories.first : 'Straight';
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load hairstyles: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inSearch = _searchQuery.isNotEmpty;
    final styles = inSearch
        ? _searchResults
        : _allStyles.where((item) => item['hairTexture'] == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => navigateBackToCustomerHome(context),
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfilePage()));
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            const Text(
              'Haircut Library',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Browse every haircut in the library if the recommended styles aren\'t for you.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search haircuts by name...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _runSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              onChanged: (v) {
                if (v.trim().isEmpty && _searchQuery.isNotEmpty) {
                  _runSearch('');
                }
              },
            ),
            if (_searchController.text.trim().isNotEmpty && !_searchLoading)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _runSearch(_searchController.text),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search library'),
                ),
              ),
            const SizedBox(height: 12),

            if (!inSearch)
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = category == _selectedCategory;
                  return _buildCategoryFolder(category, selected);
                },
              ),
            ),
            const SizedBox(height: 20),

            if (_loading || _searchLoading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white)))
            else if (_error != null)
              Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
            else if (inSearch && styles.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'No results for "$_searchQuery". This haircut is not in the library yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ),
              )
            else if (styles.isEmpty)
              const Center(child: Text('No hairstyles available.', style: TextStyle(color: Colors.white70)))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: styles.length,
                itemBuilder: (context, index) => _hairStyleCard(context, styles[index]),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),

      // Persistent bottom navigation
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            navigateToCustomerHome(context);
          } else if (index == 1) {
            openCustomerTab(context, CustomerTab.appointments);
          } else if (index == 2) {
            openCustomerTab(context, CustomerTab.scanner);
          } else if (index == 3) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedHaircutsPage()),
            );
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }

  void _openTryOnLive(BuildContext context, Map<String, dynamic> style) {
    final hasCaptures = UserSession.capturedFaceImages != null &&
        UserSession.capturedFaceImages!.isNotEmpty;

    if (!hasCaptures) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete a 3-angle face scan first, then try this style in the live scanner.',
          ),
        ),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AiFaceScanPage(presetRecommendation: style),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiFaceScanPage(
          livePreviewOnly: true,
          presetRecommendation: style,
        ),
      ),
    );
  }

  Widget _hairStyleCard(BuildContext context, Map<String, dynamic> style) {
    final previewImage = style['image']?.toString().trim().isNotEmpty == true
        ? style['image']?.toString() ?? ''
        : _librarySampleHairFront;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)),
        );
      },
      onLongPress: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.white),
                    previewImage.startsWith('assets/')
                        ? OverlayPreviewImage(assetPath: previewImage, fit: BoxFit.contain)
                        : Image.network(
                            previewImage,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (context, error, stackTrace) {
                              return OverlayPreviewImage(
                                assetPath: _librarySampleHairFront,
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withOpacity(0.3), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Title and rating
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(style['name']?.toString() ?? 'Style', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    style['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton(
                      onPressed: () => _openTryOnLive(context, style),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Try live', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  String _previewPath(String raw, String fallback) {
    if (fallback.startsWith('assets/')) return fallback;
    final trimmed = raw.trim();
    if (trimmed.startsWith('assets/')) return trimmed;
    final resolved = ApiConfig.resolveImageUrl(trimmed);
    if (resolved.startsWith('assets/')) return resolved;
    if (trimmed.isEmpty || trimmed.contains('/database/assets/')) return fallback;
    return fallback;
  }

  Map<String, dynamic> _mapVariant(Map<String, dynamic> variant) {
    final confidence = double.tryParse(variant['confidence_score']?.toString() ?? '') ?? 0.0;
    final hairTexture = _normalizeTexture((variant['hair_texture'] ?? '').toString());
    final displayName = variant['style_name']?.toString().trim() ?? 'Style';
    final normalizedStyleName = OverlayRegistry.normalizeStyleName(displayName);
    final overlay = OverlayRegistry.resolve(displayName);
    final frontRaw = variant['front_view_url']?.toString() ?? variant['frontViewUrl']?.toString() ?? '';
    final sideRaw = variant['side_view_url']?.toString() ?? variant['sideViewUrl']?.toString() ?? '';
    final backRaw = variant['back_view_url']?.toString() ?? variant['backViewUrl']?.toString() ?? '';
    final front = _previewPath(frontRaw, overlay.front);
    final side = _previewPath(sideRaw, overlay.left);
    final back = _previewPath(backRaw, overlay.right);
    return {
      'name': displayName.isNotEmpty ? displayName : 'Style',
      'description': (variant['description']?.toString().trim().isNotEmpty ?? false)
          ? variant['description'].toString().trim()
          : 'A versatile cut with clean lines and easy styling.',
      'image': front,
      'details': _buildDetails(variant),
      'rating': _scoreToRating(confidence),
      'hairTexture': hairTexture.isNotEmpty ? hairTexture : 'Mixed',
      'faceShape': variant['face_shape']?.toString() ?? '',
      'frontViewUrl': front,
      'sideViewUrl': side,
      'backViewUrl': back,
      'variantId': variant['variant_id'],
      'serviceId': variant['service_id'] ?? variant['serviceID'],
    };
  }

  String _styleIdentity(Map<String, dynamic> style) {
    final rawStyleName = style['name']?.toString().trim().toLowerCase() ?? '';
    final normalizedStyleName =
        rawStyleName == 'curly top fade' ? 'curly taper fade' : rawStyleName;
    return 'style:$normalizedStyleName';
  }

  List<Map<String, dynamic>> _dedupeStyles(List<Map<String, dynamic>> styles) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final style in styles) {
      final key = _styleIdentity(style);
      if (seen.add(key)) {
        deduped.add(style);
      }
    }
    return deduped;
  }

  void _logLibraryAudit(List<Map<String, dynamic>> variants) {
    final nameCounts = <String, int>{};
    final missingAssets = <String>[];
    for (final variant in variants) {
      final rawName = variant['style_name']?.toString().trim() ?? '';
      final name = rawName.toLowerCase();
      nameCounts[name] = (nameCounts[name] ?? 0) + 1;

      final front = variant['front_view_url']?.toString() ?? '';
      final side = variant['side_view_url']?.toString() ?? '';
      final back = variant['back_view_url']?.toString() ?? '';
      final hasAssets = front.isNotEmpty && side.isNotEmpty && back.isNotEmpty;
      if (!hasAssets && rawName.isNotEmpty) {
        missingAssets.add(rawName);
      }
    }

    final duplicates = nameCounts.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toList();
    if (duplicates.isNotEmpty) {
      debugPrint('[HaircutLibrary] Duplicate styles from API: ${duplicates.join(', ')}');
    }
    if (missingAssets.isNotEmpty) {
      debugPrint('[HaircutLibrary] Styles missing assets (front/side/back): ${missingAssets.join(', ')}');
    }
  }

  Widget _buildCategoryFolder(String label, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = label),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [Colors.white, Colors.white])
              : const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF252525)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.folder, color: selected ? Colors.black : Colors.white70, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildDetails(Map<String, dynamic> variant) {
    final instructions = variant['barber_instructions']?.toString();
    final faceShape = variant['face_shape']?.toString();
    final hairTexture = _normalizeTexture(variant['hair_texture']?.toString() ?? '');
    final details = <String>[];
    if (instructions != null && instructions.isNotEmpty) {
      details.add(instructions);
    }
    if (faceShape != null && faceShape.isNotEmpty) {
      details.add('Face shape: $faceShape');
    }
    if (hairTexture.isNotEmpty) {
      details.add('Hair texture: $hairTexture');
    }
    return details.join('\n');
  }

  bool _hasDisplayableAssets(Map<String, dynamic> style) {
    final name = style['name']?.toString() ?? '';
    return OverlayRegistry.hasDedicatedAssets(name);
  }

  String _normalizeTexture(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'straight':
        return 'Straight';
      case 'wavy':
        return 'Wavy';
      case 'curly':
        return 'Curly';
      case 'coily':
        return 'Curly';
      default:
        return '';
    }
  }

  Future<void> _useStyleDirectly(BuildContext context, Map<String, dynamic> style) async {
    final variantId = style['variantId'] as int?;
    if (variantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This haircut cannot be booked yet.')),
      );
      return;
    }

    final userHairTexture = (UserSession.lastScan?['hairTexture']?.toString() ?? '').trim().toLowerCase();
    final styleHairTexture = (style['hairTexture']?.toString() ?? '').trim().toLowerCase();
    final isMismatch = userHairTexture.isNotEmpty && styleHairTexture.isNotEmpty && userHairTexture != styleHairTexture;

    if (isMismatch) {
      final proceed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1A1A1A),
                title: const Text('Texture mismatch', style: TextStyle(color: Colors.white)),
                content: Text(
                  'Your current hair looks ${UserSession.lastScan?['hairTexture']?.toString() ?? 'different'} and this cut is best for ${style['hairTexture']?.toString() ?? 'another texture'}. It can still work, but styling may be needed.',
                  style: const TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Pick another', style: TextStyle(color: Colors.white70)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                    child: const Text('Use anyway', style: TextStyle(color: Colors.black)),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (!proceed) {
        return;
      }
    }

    final userId = UserSession.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again.')),
      );
      return;
    }

    if (await BookingGuard.hasActiveAppointment(userId: userId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      openCustomerTab(context, CustomerTab.appointments);
      return;
    }

    UserSession.selectedVariantId = variantId;
    UserSession.selectedStyleName = style['name']?.toString();
    UserSession.selectedEstimatedMinutes = style['estimatedMinutes'] as int?;
    UserSession.selectedPreviewImages = {
      'frontViewUrl': style['frontViewUrl']?.toString() ?? '',
      'sideViewUrl': style['sideViewUrl']?.toString() ?? '',
      'backViewUrl': style['backViewUrl']?.toString() ?? '',
    };

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
      frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
      sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
      backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
    );

    final suggestion = await _fetchSuggestedSlot();
    if (!context.mounted) {
      return;
    }
    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No available slots found. Please choose manually.')),
      );
      await BookingDraftService.saveFromSession(step: 'barber');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    await BookingDraftService.saveFromSession(step: 'barber');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuggestedAppointmentPage(suggestion: suggestion),
      ),
    );
  }

  Future<Map<String, dynamic>?> _fetchSuggestedSlot() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'suggestBestSlot'}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['suggestion'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  String _scoreToRating(double score) {
    final stars = (score * 5).clamp(1, 5).round();
    return '★' * stars + '☆' * (5 - stars);
  }
}
