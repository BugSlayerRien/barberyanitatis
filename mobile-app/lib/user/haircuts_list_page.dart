import 'dart:async';
import 'dart:convert';


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:http/http.dart' as http;
import 'customer_navigation.dart';
import 'hair_compatibility.dart';
import 'saved_haircuts_page.dart';
import 'user_session.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'api_config.dart';
import 'ai_credit_purchase_page.dart';
import 'services/face_scan_service.dart';
import 'widgets/preview_quota_pill.dart';
import 'services/style_booking_launcher.dart';
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

  List<Map<String, dynamic>> _allStyles = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _categories = const ['All'];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _loading = true;
  bool _searchLoading = false;
  String? _error;
  Timer? _searchDebounce;
  Map<String, dynamic>? _quota;

  @override
  void initState() {
    super.initState();
    _initCategory();
    _loadStyles();
    _quota = UserSession.lastQuota;
    unawaited(_refreshQuota());
  }

  /// How many AI previews are left.
  ///
  /// Shown here because the count used to live only on the scan results page:
  /// a customer browsing the library had to start a whole face scan just to
  /// find out whether they had any previews left, or whether a purchase had
  /// actually landed.
  Future<void> _refreshQuota() async {
    final quota = await FaceScanService.fetchQuotaStatus(
      userId: UserSession.userId,
      scanSessionId: UserSession.ensureScanSessionId(),
    );
    if (quota == null || !mounted) return;
    UserSession.lastQuota = quota;
    setState(() => _quota = quota);
  }

  Future<void> _openCreditPurchase() async {
    final quota = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        settings: const RouteSettings(name: AiCreditPurchasePage.routeName),
        builder: (_) => const AiCreditPurchasePage(),
      ),
    );
    if (quota != null) {
      UserSession.lastQuota = quota;
      if (mounted) setState(() => _quota = quota);
    }
    // A late deep-link return pops without a result, so re-read regardless.
    await _refreshQuota();
  }

  /// Previews left, as the identical pill the recommendations page shows.
  ///
  /// This was a full-width bar with a sentence and a "Top up" button, which
  /// read as a different feature from the pill beside Top picks. Same number,
  /// same control, same shape.
  Widget _buildQuotaPill() {
    if (UserSession.userId == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PreviewQuotaPill(
          quota: _quota,
          loading: _quota == null,
          canPurchase: true,
          onPurchase: _openCreditPurchase,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _runSearch('');
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(trimmed);
    });
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

  /// Says what the fit badges are based on, and how to improve it.
  ///
  /// The Library is deliberately NOT gated behind a scan -- forcing the scanner
  /// on every visit would make browsing unusable. The onboarding hair type
  /// drives the badges instead, and this strip states which source is in use,
  /// so a self-reported guess is never mistaken for a measurement and "no
  /// badge" is never mistaken for "every style suits you".
  Widget _buildTextureBasisBanner() {
    final source = HairCompatibility.textureSource();
    final texture = HairCompatibility.userTexture();

    final IconData icon;
    final String text;
    final String action;
    switch (source) {
      case TextureSource.scan:
        icon = Icons.verified_outlined;
        text = 'Fit guidance is based on your scan ($texture hair).';
        action = 'Rescan';
        break;
      case TextureSource.selfReported:
        icon = Icons.info_outline;
        text = 'Fit guidance uses the hair type you chose ($texture). '
            'Scan to confirm it.';
        action = 'Scan';
        break;
      case TextureSource.none:
        icon = Icons.help_outline;
        text = 'Set your hair type to see which cuts suit you.';
        action = 'Set';
        break;
    }

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white54),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12, height: 1.3),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              action,
              style: const TextStyle(
                  color: AppBrand.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  /// Explains the corner icons once, so the cards do not each have to repeat
  /// the sentence they replaced.
  Widget _buildFitLegend() {
    // One row, three equal shares.
    //
    // This was a Wrap, which fits what it can and pushes the rest onto a
    // second line: on a phone the first two labels sat together and "Not
    // recommended" dropped underneath on its own, reading like a separate
    // thing rather than the third of three. Equal columns keep the three
    // meanings side by side at any width.
    Widget item(IconData icon, Color color, String label) {
      return Expanded(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 10, color: color),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 10.5),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          item(Icons.check_rounded, const Color(0xFF8FD49A), 'Suits your hair'),
          const SizedBox(width: 6),
          item(Icons.priority_high_rounded, const Color(0xFFE0B35A), 'May need styling'),
          const SizedBox(width: 6),
          item(Icons.close_rounded, const Color(0xFFE07A7A), 'Not recommended'),
        ],
      ),
    );
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
            const SizedBox(height: 12),
            _buildTextureBasisBanner(),
            _buildFitLegend(),
            _buildQuotaPill(),
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
                          _searchDebounce?.cancel();
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
              onChanged: _onSearchChanged,
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

  /// Stands in for a haircut that has no photograph yet.
  ///
  /// The alternative was a bundled sample image, which told the customer this
  /// is what the cut looks like when it was really a different cut entirely.
  Widget _artworkPlaceholder(String styleName) {
    return Container(
      color: const Color(0xFFF2F2F2),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.content_cut, size: 30, color: Color(0xFF9E9E9E)),
          const SizedBox(height: 8),
          Text(
            styleName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF616161),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Photo coming soon',
            style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _hairStyleCard(BuildContext context, Map<String, dynamic> style) {
    final styleName = style['name']?.toString() ?? 'Style';
    final previewImage = style['image']?.toString().trim() ?? '';
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
                    if (previewImage.isEmpty)
                      _artworkPlaceholder(styleName)
                    else if (previewImage.startsWith('assets/'))
                      OverlayPreviewImage(assetPath: previewImage, fit: BoxFit.contain)
                    else
                      Image.network(
                        previewImage,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        // A broken URL used to fall back to the sample hair,
                        // which is a different haircut. Say nothing instead.
                        errorBuilder: (context, error, stackTrace) =>
                            _artworkPlaceholder(styleName),
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
                    Builder(
                      builder: (_) {
                        final compat = HairCompatibility.evaluateStyleMap(style);
                        if (compat == null) return const SizedBox.shrink();
                        // Top-right corner: a small marker that does not sit
                        // over the haircut itself.
                        return Positioned(
                          top: 6,
                          right: 6,
                          child: HairCompatibilityBadge(
                            result: compat,
                            iconOnly: true,
                          ),
                        );
                      },
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

  /// The image to draw for a style.
  ///
  /// The bundled asset was checked first and returned unconditionally, so a
  /// stored URL could never win -- every library thumbnail was a built-in PNG
  /// and an admin's upload was silently discarded. The style's own artwork now
  /// takes precedence, with the bundled set as the fallback it was meant to be.
  String _previewPath(String raw, String fallback) {
    final trimmed = raw.trim();

    if (trimmed.isNotEmpty && !trimmed.contains('/database/assets/')) {
      if (trimmed.startsWith('assets/')) return trimmed;

      final resolved = ApiConfig.resolveImageUrl(trimmed);
      if (resolved.isNotEmpty) return resolved;
    }

    return fallback;
  }

  Map<String, dynamic> _mapVariant(Map<String, dynamic> variant) {
    final confidence = double.tryParse(variant['confidence_score']?.toString() ?? '') ?? 0.0;
    final hairTexture = _normalizeTexture((variant['hair_texture'] ?? '').toString());
    final displayName = variant['style_name']?.toString().trim() ?? 'Style';
    // OverlayRegistry.resolve() answers `sample` -- Blowout Taper -- for a name
    // it does not know, so using it as a blanket fallback dressed every new
    // style in another cut's hair. Only styles that really ship with artwork
    // get the bundled set; the rest fall back to nothing and the card draws a
    // placeholder, which is honest rather than confidently wrong.
    final hasBundledArt = OverlayRegistry.hasDedicatedAssets(displayName);
    final overlay = hasBundledArt ? OverlayRegistry.resolve(displayName) : null;
    final frontRaw = variant['front_view_url']?.toString() ?? variant['frontViewUrl']?.toString() ?? '';
    final sideRaw = variant['side_view_url']?.toString() ?? variant['sideViewUrl']?.toString() ?? '';
    final backRaw = variant['back_view_url']?.toString() ?? variant['backViewUrl']?.toString() ?? '';
    final front = _previewPath(frontRaw, overlay?.front ?? '');
    final side = _previewPath(sideRaw, overlay?.left ?? '');
    final back = _previewPath(backRaw, overlay?.right ?? '');
    return {
      // The server decides both of these: whether there is a real picture, and
      // whether a preview could still be generated without one.
      'hasArtwork': front.isNotEmpty,
      'previewable': variant['previewable'] == true,
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
      'variantId': int.tryParse(variant['variant_id']?.toString() ?? '') ??
          int.tryParse(variant['variantId']?.toString() ?? ''),
      'serviceId': int.tryParse(variant['service_id']?.toString() ?? '') ??
          int.tryParse(variant['serviceID']?.toString() ?? ''),
      'estimatedMinutes': int.tryParse(variant['estimated_minutes']?.toString() ?? ''),
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

  /// Whether this style has a picture we can actually draw.
  ///
  /// This used to require artwork bundled in the app, which meant a haircut
  /// added through the portal was filtered out of the library no matter how
  /// complete its database row was -- a new style could only ever appear by
  /// shipping a new build. An uploaded photo is just as displayable; it simply
  /// arrives over the network instead of from the bundle.
  bool _hasDisplayableAssets(Map<String, dynamic> style) {
    final name = style['name']?.toString() ?? '';
    if (OverlayRegistry.hasDedicatedAssets(name)) return true;

    final image = style['image']?.toString().trim() ?? '';
    if (image.isNotEmpty && !image.startsWith('assets/')) return true;

    // No picture of its own and none bundled. A haircut the barber has
    // described well enough to generate is still a haircut the shop can cut,
    // so it belongs in the library with a placeholder -- hiding it is how the
    // panel's own addition came to be invisible.
    return style['previewable'] == true;
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

  Future<void> _useStyleDirectly(BuildContext context, Map<String, dynamic> style) =>
      launchBookingForStyle(context, style);

  String _scoreToRating(double score) {
    final stars = (score * 5).clamp(1, 5).round();
    return '★' * stars + '☆' * (5 - stars);
  }
}
