import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_funnel_service.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'customer_navigation.dart';
import 'dashboard_page.dart';
import 'hair_compatibility.dart';
import 'profile_page.dart';
import 'ai_face_scan_page.dart';
import 'feature_flags.dart';
import 'saved_haircuts_page.dart';
import 'suggested_appointment_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'user_session.dart';
import 'api_config.dart';
import 'services/booking_slots_service.dart';
import 'scanner/overlay_preview_image.dart';
import 'scanner/overlay_registry.dart';

class HairstyleDetailPage extends StatefulWidget {
  final Map<String, dynamic> style;

  const HairstyleDetailPage({required this.style, super.key});

  @override
  State<HairstyleDetailPage> createState() => _HairstyleDetailPageState();
}

class _HairstyleDetailPageState extends State<HairstyleDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late PageController _imagePageController;
  int _currentImagePage = 0;
  final Map<String, Future<Uint8List>> _webImageCache = {};
  bool _isFavorite = false;
  bool _savingFavorite = false;
  bool _bookingInFlight = false;

  @override
  void initState() {
    super.initState();
    _imagePageController = PageController();
    UserSession.selectedPreviewImages = {
      'frontViewUrl': widget.style['image']?.toString() ?? widget.style['frontViewUrl']?.toString() ?? '',
      'sideViewUrl': widget.style['sideViewUrl']?.toString() ?? '',
      'backViewUrl': widget.style['backViewUrl']?.toString() ?? '',
    };
    _animationController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _loadFavoriteStatus();
  }

  @override
  void dispose() {
    _imagePageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  bool _hasImage(String? url) {
    return url != null && url.isNotEmpty;
  }

  ImageProvider _buildImageProvider(String url) {
    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    return NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.prefer);
  }

  Future<Uint8List> _fetchWebImageBytes(String url) {
    return _webImageCache.putIfAbsent(url, () async {
      // If it's an asset path, fetch from the web assets directory
      final fetchUrl = url.startsWith('assets/')
          ? '/assets/${url.replaceFirst('assets/', '')}'
          : url;
      final response = await http.get(Uri.parse(fetchUrl));
      if (response.statusCode != 200) {
        throw Exception('Image load failed (${response.statusCode}) from $fetchUrl');
      }
      return response.bodyBytes;
    });
  }

  Widget _buildWebImage(String url) {
    return FutureBuilder<Uint8List>(
      future: _fetchWebImageBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(color: Colors.white);
        }
        if (!snapshot.hasData) {
          debugPrint('[HairstyleDetail] Failed to load web image: ${snapshot.error}');
          return Container(color: Colors.white);
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }

  Map<String, String>? _styleAssetSet() {
    final styleName = widget.style['name']?.toString() ?? '';
    final overlay = OverlayRegistry.resolve(styleName);
    return {
      'front': overlay.front,
      'left': overlay.left,
      'right': overlay.right,
    };
  }

  String? _resolveDetailImage(String? raw) {
    final assetSet = _styleAssetSet();
    if (assetSet != null) {
      final front = assetSet['front'];
      final left = assetSet['left'];
      final right = assetSet['right'];
      if (raw == widget.style['image']?.toString() || raw == widget.style['frontViewUrl']?.toString()) {
        return front;
      }
      if (raw == widget.style['sideViewUrl']?.toString()) {
        return left;
      }
      if (raw == widget.style['backViewUrl']?.toString()) {
        return right;
      }
      return front;
    }

    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw;
  }

  List<_DetailImageEntry> _detailImageEntries() {
    final entries = <_DetailImageEntry>[];
    final seen = <String>{};

    void addEntry(String label, String? raw) {
      final resolved = _resolveDetailImage(raw);
      if (resolved == null || resolved.isEmpty) {
        return;
      }
      if (seen.add(resolved)) {
        entries.add(_DetailImageEntry(label: label, url: resolved));
      }
    }

    addEntry('Front', widget.style['image']?.toString() ?? widget.style['frontViewUrl']?.toString());
    addEntry('Left', widget.style['sideViewUrl']?.toString());
    addEntry('Right', widget.style['backViewUrl']?.toString());

    if (entries.isEmpty) {
      final fallback = _resolveDetailImage(widget.style['image']?.toString());
      if (fallback != null && fallback.isNotEmpty) {
        entries.add(_DetailImageEntry(label: 'Front', url: fallback));
      }
    }

    return entries;
  }

  Widget _buildDetailImage(String url) {
    if (url.startsWith('assets/')) {
      return OverlayPreviewImage(assetPath: url, fit: BoxFit.contain);
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('[HairstyleDetail] Network load failed for $url: $error');
        return Container(color: Colors.white);
      },
    );
  }

  Widget _buildDetailCarousel() {
    final images = _detailImageEntries();
    if (images.isEmpty) {
      return Container(color: Colors.white);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _imagePageController,
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _currentImagePage = index);
          },
          itemCount: images.length,
          itemBuilder: (context, index) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(child: _buildDetailImage(images[index].url)),
                Positioned(
                  left: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.90),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      images[index].label,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (images.length > 1)
          Positioned(
            left: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                onPressed: _currentImagePage > 0
                    ? () => _imagePageController.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        )
                    : null,
                icon: const Icon(Icons.chevron_left, color: Colors.black87),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.85),
                ),
              ),
            ),
          ),
        if (images.length > 1)
          Positioned(
            right: 12,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                onPressed: _currentImagePage < images.length - 1
                    ? () => _imagePageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        )
                    : null,
                icon: const Icon(Icons.chevron_right, color: Colors.black87),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.85),
                ),
              ),
            ),
          ),
        if (images.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                final active = index == _currentImagePage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 12 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Colors.black87 : Colors.black26,
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildDetailSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.white),
        _buildDetailCarousel(),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.16)],
            ),
          ),
        ),
      ],
    );
  }

  int? _getVariantId() {
    final value = widget.style['variantId'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _loadFavoriteStatus() async {
    final userId = UserSession.userId;
    final variantId = _getVariantId();
    if (userId == null || variantId == null) {
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'status', 'userID': userId, 'variantID': variantId}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _isFavorite = data['isFavorite'] == true);
    }
    catch (_) {
      // Ignore favorite status errors so the page still loads.
    }
  }

  void _openTryHaircut() {
    if (!kEnableLiveScanner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Run a 3-angle face scan, then use Generate preview on your results.',
          ),
        ),
      );
      return;
    }

    final hasCaptures = UserSession.capturedFaceImages != null &&
        UserSession.capturedFaceImages!.isNotEmpty;

    if (!hasCaptures) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete a 3-angle face scan first, then use Try Haircut for live preview.',
          ),
        ),
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AiFaceScanPage(
            presetRecommendation: widget.style,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiFaceScanPage(
          livePreviewOnly: true,
          presetRecommendation: widget.style,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    final userId = UserSession.userId;
    final variantId = _getVariantId();
    if (userId == null || variantId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login required to save haircuts.')),
      );
      return;
    }
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      final action = _isFavorite ? 'remove' : 'add';
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'userID': userId, 'variantID': variantId}),
      );
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() => _isFavorite = !_isFavorite);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFavorite ? 'Saved to bookmarks.' : 'Removed from bookmarks.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update saved haircuts.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update saved haircuts: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingFavorite = false);
      }
    }
  }

  void _trackSelectionInBackground({
    required int userId,
    required int variantId,
  }) {
    unawaited(
      AiFunnelService.saveSelection(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: userId,
        variantId: variantId,
        styleName: UserSession.selectedStyleName ?? 'Style',
        faceShape: UserSession.lastScan?['faceShape']?.toString(),
        hairTexture: UserSession.lastScan?['hairTexture']?.toString(),
        hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
        hairLength: UserSession.lastScan?['hairLength']?.toString(),
        estimatedMinutes: UserSession.selectedEstimatedMinutes,
      ).catchError((_) {}),
    );
  }

  Future<void> _proceedToBookingFlow() async {
    if (!_bookingInFlight) {
      setState(() => _bookingInFlight = true);
    }

    try {
      final hasActive = await BookingGuard.hasActiveAppointment(
        userId: UserSession.userId,
      ).timeout(const Duration(seconds: 8));
      if (!mounted) {
        return;
      }
      if (hasActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active appointment.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AppointmentsPage()),
        );
        return;
      }

      final result = await BookingSlotsService.fetchBestSuggestion();
      if (!mounted) {
        return;
      }

      if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
        return;
      }

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No open times available right now. You can still pick a barber manually.',
            ),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SuggestedAppointmentPage(suggestion: result.suggestion!),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bookingInFlight = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large image with gradient overlay
              Container(
                height: 380,
                decoration: const BoxDecoration(color: Color(0xFF0A0A0A)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.white),
                    _buildDetailCarousel(),
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.28)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with icon
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.style['name']?.toString() ?? 'Style',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _savingFavorite ? null : _toggleFavorite,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isFavorite ? Colors.white : Colors.transparent,
                                      foregroundColor: _isFavorite ? Colors.black : Colors.white,
                                      side: const BorderSide(color: Colors.white, width: 1),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                    icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border, size: 18),
                                    label: Text(_isFavorite ? 'Saved' : 'Save'),
                                  ),
                                  if (_savingFavorite)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 10),
                                      child: SizedBox(
                                        height: 14,
                                        width: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      widget.style['description']?.toString().trim().isNotEmpty == true
                          ? widget.style['description'].toString().trim()
                          : 'A clean, modern haircut selected for your look.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    Builder(
                      builder: (_) {
                        final compat =
                            HairCompatibility.evaluateStyleMap(widget.style);
                        if (compat == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: HairCompatibilityBadge(
                            result: compat,
                            compact: false,
                          ),
                        );
                      },
                    ),
                    if ((widget.style['details']?.toString().trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 12),
                      Text(
                        widget.style['details']!.toString().trim(),
                        style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.45),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // Buttons
                    ElevatedButton(
                      onPressed: _bookingInFlight
                          ? null
                          : () async {
                        final variantId = widget.style['variantId'] ?? widget.style['variantID'];
                        int? normalizedVariantId;
                        if (variantId is int) {
                          normalizedVariantId = variantId;
                        } else {
                          normalizedVariantId = int.tryParse(variantId?.toString() ?? '');
                        }

                        if (normalizedVariantId == null || normalizedVariantId <= 0) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('This haircut cannot be booked yet. Please choose another style.')),
                          );
                          return;
                        }

                        final compat =
                            HairCompatibility.evaluateStyleMap(widget.style);
                        final mayProceed =
                            await HairCompatibility.confirmBookingIfNeeded(
                          context,
                          compat,
                        );
                        if (!mayProceed || !context.mounted) {
                          return;
                        }

                        UserSession.selectedVariantId = normalizedVariantId;
                        final serviceIdValue = widget.style['serviceId'] ?? widget.style['service_id'] ?? widget.style['serviceID'];
                        UserSession.selectedServiceId = int.tryParse(serviceIdValue?.toString() ?? '');
                        UserSession.selectedStyleName = widget.style['name']?.toString();
                        UserSession.selectedEstimatedMinutes = int.tryParse(widget.style['estimatedMinutes']?.toString() ?? '');

                        final userId = UserSession.userId;
                        if (userId != null) {
                          _trackSelectionInBackground(
                            userId: userId,
                            variantId: normalizedVariantId,
                          );
                        }

                        if (!context.mounted) {
                          return;
                        }
                        setState(() => _bookingInFlight = true);
                        await _proceedToBookingFlow();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: Colors.white.withOpacity(0.3),
                      ),
                      child: Text(
                        _bookingInFlight ? 'Checking slots...' : 'Confirm and Proceed',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (kEnableLiveScanner) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _openTryHaircut,
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(56),
                          side: const BorderSide(color: Colors.white54, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Try Haircut',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // Bottom Navigation
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
}

class _DetailImageEntry {
  final String label;
  final String url;

  const _DetailImageEntry({required this.label, required this.url});
}
