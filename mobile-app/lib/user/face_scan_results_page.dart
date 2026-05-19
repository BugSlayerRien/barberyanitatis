import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'api_config.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'dashboard_page.dart';
import 'haircuts_list_page.dart';
import 'saved_haircuts_page.dart';
import 'scanner/face_scan_compositor.dart';
import 'scanner/overlay_asset_cache.dart';
import 'scanner/overlay_registry.dart';
import 'scanner/scanner_layout.dart';
import 'scanner/static_face_preview.dart';
import 'services/face_scan_service.dart';
import 'suggested_appointment_page.dart';
import 'user_session.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';
import '../kiosk/kiosk_barber_page.dart';
import '../kiosk/kiosk_session.dart';

class FaceScanResultsPage extends StatefulWidget {
  final Map<String, String> captures;
  final String faceShape;
  final String hairTexture;
  final Map<String, dynamic>? presetRecommendation;
  final bool kioskMode;

  const FaceScanResultsPage({
    super.key,
    required this.captures,
    required this.faceShape,
    required this.hairTexture,
    this.presetRecommendation,
    this.kioskMode = false,
  });

  @override
  State<FaceScanResultsPage> createState() => _FaceScanResultsPageState();
}

class _FaceScanResultsPageState extends State<FaceScanResultsPage> {
  bool _recommendationsLoading = true;
  String? _error;
  String _aiSummary = '';
  bool _aiPowered = false;
  List<Map<String, dynamic>> _topPicks = [];
  Map<String, List<Map<String, dynamic>>> _categories = {
    'formal': [],
    'alternative': [],
    'youthful': [],
  };
  Map<String, dynamic>? _selected;
  int _previewAngleIndex = 0;
  bool _bookingInFlight = false;
  bool _compositingForSave = false;

  static const _angleKeys = ['front', 'left', 'right'];
  static const _angleLabels = ['Front', 'Left', 'Right'];

  Map<String, Rect> get _faceRects =>
      UserSession.captureFaceRects ?? {};

  @override
  void initState() {
    super.initState();
    _selected = widget.presetRecommendation;
    unawaited(OverlayAssetCache.preload());
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() {
      _recommendationsLoading = true;
      _error = null;
    });
    try {
      final data = await FaceScanService.fetchRecommendations(
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
        userId: UserSession.userId,
      );

      if (!mounted) return;

      final top = (data['topPicks'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final cats = data['categories'] as Map<String, dynamic>? ?? {};

      _applyRecommendationPayload(
        topPicks: top,
        categories: {
          'formal': _mapList(cats['formal']),
          'alternative': _mapList(cats['alternative']),
          'youthful': _mapList(cats['youthful']),
        },
        aiSummary: data['aiSummary']?.toString() ?? '',
        aiPowered: data['aiPowered'] == true,
        preserveSelection: false,
      );

      await AiFunnelService.trackScan(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: UserSession.userId,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        hairDensity: null,
        hairLength: null,
        recommendationCount: top.length,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _recommendationsLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _applyRecommendationPayload({
    required List<Map<String, dynamic>> topPicks,
    required Map<String, List<Map<String, dynamic>>> categories,
    required String aiSummary,
    required bool aiPowered,
    required bool preserveSelection,
  }) {
    final selectedId = preserveSelection && _selected != null
        ? '${_selected!['variant_id'] ?? _selected!['variantId']}'
        : null;

    setState(() {
      _topPicks = topPicks;
      _categories = categories;
      _aiSummary = aiSummary;
      _aiPowered = aiPowered;
      _recommendationsLoading = false;
      if (!preserveSelection) {
        _selected ??= widget.presetRecommendation ?? (topPicks.isNotEmpty ? topPicks.first : null);
      } else if (selectedId != null && selectedId.isNotEmpty) {
        for (final row in topPicks) {
          if ('${row['variant_id'] ?? row['variantId']}' == selectedId) {
            _selected = row;
            break;
          }
        }
      }
    });

    UserSession.lastScan = {
      'faceShape': widget.faceShape,
      'hairTexture': widget.hairTexture,
    };
    UserSession.lastRecommendations = List<Map<String, dynamic>>.from(topPicks);
    UserSession.hasRecentRecommendations = topPicks.isNotEmpty;
  }

  Future<void> _openLivePreview() async {
    final selectedBefore = _selected;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiFaceScanPage(
          livePreviewOnly: true,
          presetRecommendation: _selected,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (selectedBefore != null) {
      _selected = selectedBefore;
    }
    await _loadRecommendations();
  }

  void _selectStyle(Map<String, dynamic> style) {
    setState(() => _selected = style);
  }

  String get _selectedStyleName =>
      _selected?['style_name']?.toString() ??
      _selected?['styleName']?.toString() ??
      'Style';

  Future<void> _bookSelected() async {
    final selected = _selected;
    if (selected == null) return;

    final variantId = int.tryParse(
          '${selected['variant_id'] ?? selected['variantId'] ?? 0}',
        ) ??
        0;
    if (variantId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This style cannot be booked yet.')),
      );
      return;
    }

    if (widget.kioskMode) {
      KioskSession.selectedVariantId = variantId;
      KioskSession.selectedStyleName = _selectedStyleName;
      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = _selectedStyleName;
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const KioskBarberPage()),
      );
      return;
    }

    final userId = UserSession.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again.')),
      );
      return;
    }

    if (await BookingGuard.hasActiveAppointment(userId: userId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AppointmentsPage()),
      );
      return;
    }

    setState(() {
      _bookingInFlight = true;
      _compositingForSave = true;
    });

    try {
      Map<String, String> previewUrls = {};
      final composited = await FaceScanCompositor.compositeAllAngles(
        capturesBase64: widget.captures,
        styleName: _selectedStyleName,
        faceRectsByAngle: _faceRects,
      );
      if (composited.isNotEmpty) {
        previewUrls = await FaceScanService.saveCompositedPreviews(
          scanSessionId: UserSession.ensureScanSessionId(),
          variantId: variantId,
          previewsBase64: composited,
        );
      }

      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = _selectedStyleName;
      UserSession.selectedPreviewImages = previewUrls.isNotEmpty
          ? previewUrls
          : {
              'frontViewUrl': selected['front_view_url']?.toString() ?? '',
              'sideViewUrl': selected['side_view_url']?.toString() ?? '',
              'backViewUrl': selected['back_view_url']?.toString() ?? '',
            };
      UserSession.customerPreviewImages = UserSession.selectedPreviewImages;

      await AiFunnelService.saveSelection(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: userId,
        variantId: variantId,
        styleName: UserSession.selectedStyleName ?? 'Style',
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        hairDensity: null,
        hairLength: null,
        estimatedMinutes: int.tryParse(
          '${selected['estimated_minutes'] ?? selected['estimatedMinutes'] ?? 60}',
        ),
        frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
        sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
        backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
      );

      final suggestion = await _fetchSuggestedSlot();
      if (!mounted) return;
      setState(() {
        _bookingInFlight = false;
        _compositingForSave = false;
      });

      if (suggestion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No available slots found. Please choose manually.'),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SuggestedAppointmentPage(suggestion: suggestion),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingInFlight = false;
        _compositingForSave = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking prep failed: $e')),
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchSuggestedSlot() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'suggestBestSlot'}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['suggestion'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: const AppTopBar(showBack: true),
      body: _error != null ? _errorView() : _content(),
      bottomNavigationBar: widget.kioskMode
          ? null
          : AppBottomNavBar(
              currentIndex: 2,
              onTap: (index) {
                if (index == 0) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const DashboardPage()),
                  );
                } else if (index == 1) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                  );
                } else if (index == 2) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
                  );
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

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadRecommendations, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final angleKey = _angleKeys[_previewAngleIndex];
    final captureB64 = widget.captures[angleKey];
    final styleName = _selectedStyleName;
    final yaw = OverlayRegistry.yawForCaptureAngle(angleKey);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const Text(
              'Your AI Hair Recommendations',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _chip('Face: ${widget.faceShape}'),
                const SizedBox(width: 8),
                _chip('Hair: ${widget.hairTexture}'),
                if (_aiPowered) ...[
                  const SizedBox(width: 8),
                  _chip('AI', highlight: true),
                ],
              ],
            ),
            if (_aiSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_aiSummary, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            _buildCaptureThumbnails(),
            const SizedBox(height: 10),
            ScannerLayout.previewFrame(
              context: context,
              child: captureB64 != null && _selected != null
                  ? StaticFacePreview(
                      key: ValueKey('$styleName-$angleKey'),
                      captureBase64: captureB64,
                      angleKey: angleKey,
                      styleName: styleName,
                      normalizedFaceRect: _faceRects[angleKey],
                      headYaw: yaw,
                    )
                  : captureB64 != null
                      ? Image.memory(
                          base64Decode(captureB64),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          gaplessPlayback: true,
                        )
                      : const Center(
                          child: Icon(Icons.face, color: Colors.white38, size: 48),
                        ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_angleLabels.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(_angleLabels[i]),
                    selected: _previewAngleIndex == i,
                    onSelected: (_) => setState(() => _previewAngleIndex = i),
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _previewAngleIndex == i ? Colors.black : Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _selected?['fit_reason']?.toString() ?? 'Select a style to see why it fits you.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_recommendationsLoading) ...[
              const SizedBox(height: 20),
              const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 10),
                    Text('Loading AI suggestions...', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 18),
              _sectionTitle('Top picks'),
              ..._topPicks.map(_styleTile),
              const SizedBox(height: 16),
              _sectionTitle('Formal'),
              ..._categories['formal']!.map(_styleTile),
              const SizedBox(height: 12),
              _sectionTitle('Alternative'),
              ..._categories['alternative']!.map(_styleTile),
              const SizedBox(height: 12),
              _sectionTitle('Youthful'),
              ..._categories['youthful']!.map(_styleTile),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected == null || _bookingInFlight ? null : _bookSelected,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white24,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: _bookingInFlight
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        widget.kioskMode ? 'Continue to barber selection' : 'Book this haircut',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            if (!widget.kioskMode) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openLivePreview,
                icon: const Icon(Icons.videocam_outlined, color: Colors.white),
                label: const Text('Try live preview (optional)', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HaircutsListPage()),
                  );
                },
                child: const Text('Browse all haircuts', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ],
        ),
        if (_compositingForSave)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 12),
                Text('Preparing your haircut preview...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCaptureThumbnails() {
    return SizedBox(
      height: 88,
      child: Row(
        children: List.generate(_angleKeys.length, (index) {
          final key = _angleKeys[index];
          final b64 = widget.captures[key];
          final selected = index == _previewAngleIndex;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
              child: GestureDetector(
                onTap: () => setState(() => _previewAngleIndex = index),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: b64 != null && b64.isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              base64Decode(b64),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                            Container(
                              alignment: Alignment.bottomCenter,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              color: Colors.black54,
                              child: Text(
                                _angleLabels[index],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Text(
                            _angleLabels[index],
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
    );
  }

  Widget _chip(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight ? Colors.white : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: highlight ? Colors.black : Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _styleTile(Map<String, dynamic> item) {
    final name = item['style_name']?.toString() ?? item['styleName']?.toString() ?? 'Style';
    final reason = item['fit_reason']?.toString() ?? '';
    final selected = _selected != null &&
        '${_selected!['variant_id'] ?? _selected!['variantId']}' ==
            '${item['variant_id'] ?? item['variantId']}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectStyle(item),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1F1F1F) : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.white : Colors.white10, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(reason, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
