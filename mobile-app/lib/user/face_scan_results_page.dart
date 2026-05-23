import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'dashboard_page.dart';
import 'haircuts_list_page.dart';
import 'saved_haircuts_page.dart';
import 'api_config.dart';
import 'scanner/scanner_layout.dart';
import 'services/booking_slots_service.dart';
import 'services/booking_draft_service.dart';
import 'services/face_scan_service.dart';
import 'suggested_appointment_page.dart';
import 'user_session.dart';
import 'widgets/ai_chatbot_fab.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';
import '../kiosk/kiosk_barber_page.dart';
import '../kiosk/kiosk_session.dart';

class FaceScanResultsPage extends StatefulWidget {
  final Map<String, String> captures;
  final String faceShape;
  final String hairTexture;
  final int hairLengthLevel;
  final String hairLengthLabel;
  final Map<String, dynamic>? presetRecommendation;
  final bool kioskMode;

  const FaceScanResultsPage({
    super.key,
    required this.captures,
    required this.faceShape,
    required this.hairTexture,
    this.hairLengthLevel = 1,
    this.hairLengthLabel = 'short',
    this.presetRecommendation,
    this.kioskMode = false,
  });

  @override
  State<FaceScanResultsPage> createState() => _FaceScanResultsPageState();
}

class _FaceScanResultsPageState extends State<FaceScanResultsPage> {
  bool _recommendationsLoading = true;
  bool _categoriesLoading = false;
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
  bool _previewGenerating = false;
  String? _previewError;
  String? _lengthNote;
  final Map<String, Map<String, String>> _replicatePreviewsByVariant = {};
  static const _angleKeys = ['front', 'left', 'right'];
  static const _angleLabels = ['Front', 'Left', 'Right'];

  Map<String, Rect> get _faceRects =>
      UserSession.captureFaceRects ?? {};

  @override
  void initState() {
    super.initState();
    _selected = widget.presetRecommendation;
    UserSession.lastRecommendations = [];
    UserSession.hasRecentRecommendations = false;
    _loadRecommendations();
  }

  void _leaveResults() {
    UserSession.resetScanState();
    Navigator.of(context).pop();
  }

  Future<void> _loadRecommendations({bool preserveSelection = false}) async {
    setState(() {
      _recommendationsLoading = true;
      _categoriesLoading = true;
      _error = null;
    });

    try {
      final quick = await FaceScanService.fetchQuickRankings(
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        userId: UserSession.userId,
      );

      if (!mounted) return;

      if (quick.isNotEmpty) {
        final local = FaceScanService.buildLocalInsightsFromRankings(
          rankings: quick,
          faceShape: widget.faceShape,
          hairTexture: widget.hairTexture,
        );
        final localCats = local['categories'] as Map<String, dynamic>? ?? {};
        setState(() {
          final topPicksRaw = List<dynamic>.from(
            local['topPicks'] as List<dynamic>? ?? quick.take(3).toList(),
          );
          _topPicks = topPicksRaw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _categories = {
            'formal': _mapList(localCats['formal']),
            'alternative': _mapList(localCats['alternative']),
            'youthful': _mapList(localCats['youthful']),
          };
          _aiSummary = local['aiSummary']?.toString() ?? '';
          _recommendationsLoading = false;
          _categoriesLoading = true;
          if (!preserveSelection) {
            _selected ??= widget.presetRecommendation ?? _topPicks.first;
          }
        });
      }
    } catch (_) {
      // Full insights load may still succeed.
    }

    try {
      final data = await FaceScanService.fetchRecommendations(
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        userId: UserSession.userId,
      );

      if (!mounted) return;

      final top = (data['topPicks'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final cats = data['categories'] as Map<String, dynamic>? ?? {};

      _applyRecommendationPayload(
        topPicks: top.isNotEmpty ? top : _topPicks,
        categories: {
          'formal': _mapList(cats['formal']),
          'alternative': _mapList(cats['alternative']),
          'youthful': _mapList(cats['youthful']),
        },
        aiSummary: data['aiSummary']?.toString() ?? '',
        aiPowered: data['aiPowered'] == true,
        preserveSelection: preserveSelection,
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
      if (_topPicks.isEmpty) {
        setState(() {
          _error = e.toString();
          _recommendationsLoading = false;
          _categoriesLoading = false;
        });
      } else if (_topPicks.isNotEmpty) {
        final local = FaceScanService.buildLocalInsightsFromRankings(
          rankings: _topPicks,
          faceShape: widget.faceShape,
          hairTexture: widget.hairTexture,
        );
        final localCats = local['categories'] as Map<String, dynamic>? ?? {};
        _applyRecommendationPayload(
          topPicks: _topPicks,
          categories: {
            'formal': _mapList(localCats['formal']),
            'alternative': _mapList(localCats['alternative']),
            'youthful': _mapList(localCats['youthful']),
          },
          aiSummary: local['aiSummary']?.toString() ?? '',
          aiPowered: false,
          preserveSelection: preserveSelection,
        );
      } else {
        setState(() {
          _categoriesLoading = false;
          _recommendationsLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _categoriesLoading = false);
      }
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
      'hairLength': widget.hairLengthLabel,
      'hairLengthLevel': widget.hairLengthLevel,
    };
    UserSession.lastRecommendations = List<Map<String, dynamic>>.from(topPicks);
    UserSession.hasRecentRecommendations = topPicks.isNotEmpty;
  }

  Future<void> _openLivePreview() async {
    UserSession.capturedFaceImages = Map<String, String>.from(widget.captures);
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
    await _loadRecommendations(preserveSelection: true);
  }

  Future<void> _selectStyle(Map<String, dynamic> style) async {
    final variantId = int.tryParse(
          '${style['variant_id'] ?? style['variantId'] ?? 0}',
        ) ??
        0;

    final alreadyCached =
        variantId > 0 && _previewUrlsForVariant(variantId) != null;

    if (!alreadyCached) {
      final styleName = style['style_name']?.toString() ??
          style['styleName']?.toString() ??
          'this style';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Generate AI preview?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Generate a preview for "$styleName"? This uses Replicate credits and can take several minutes.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Generate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    setState(() {
      _selected = style;
      _previewError = null;
    });
    unawaited(_loadReplicatePreviewsForSelected());
  }

  int? get _selectedVariantId {
    final raw = _selected?['variant_id'] ?? _selected?['variantId'];
    return int.tryParse('$raw');
  }

  Map<String, String>? _previewUrlsForVariant(int variantId) {
    return _replicatePreviewsByVariant['$variantId'];
  }

  Map<String, String> _catalogPreviewUrls(Map<String, dynamic> style) {
    String pick(List<String> keys) {
      for (final key in keys) {
        final value = style[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }

    return {
      'frontViewUrl': pick(['front_view_url', 'frontViewUrl', 'image']),
      'sideViewUrl': pick(['side_view_url', 'sideViewUrl', 'sideView']),
      'backViewUrl': pick(['back_view_url', 'backViewUrl', 'backView']),
    };
  }

  Future<bool> _confirmBookWithoutAiPreview(String styleName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Book without AI preview?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You have not generated a personalized try-on for "$styleName". '
          'You can still book using the catalog style reference. '
          'Your barber will see the standard style photos, not an AI composite.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Go back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: const Text('Continue booking'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String? _previewUrlForAngle(int variantId, String angleKey) {
    final urls = _previewUrlsForVariant(variantId);
    if (urls == null) return null;
    switch (angleKey) {
      case 'front':
        return urls['frontViewUrl'];
      case 'left':
        return urls['sideViewUrl'];
      case 'right':
        return urls['backViewUrl'];
      default:
        return null;
    }
  }

  Future<void> _loadReplicatePreviewsForSelected({bool forceRegenerate = false}) async {
    final variantId = _selectedVariantId;
    if (variantId == null || variantId <= 0) return;
    if (!forceRegenerate && _replicatePreviewsByVariant.containsKey('$variantId')) {
      return;
    }

    setState(() {
      _previewGenerating = true;
      _previewError = null;
      if (forceRegenerate) {
        _replicatePreviewsByVariant.remove('$variantId');
      }
    });

    try {
      final data = await FaceScanService.generateStylePreviews(
        scanSessionId: UserSession.ensureScanSessionId(),
        variantId: variantId,
        styleName: _selectedStyleName,
        styleCode: _selected?['style_code']?.toString() ?? _selected?['styleCode']?.toString(),
        userId: UserSession.userId,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        hairLengthLevel: widget.hairLengthLevel,
        forceRegenerate: forceRegenerate,
      );
      if (!mounted) return;
      final urls = FaceScanService.previewUrlsFromResponse(data);
      final fromCache = data['cached'] == true;
      setState(() {
        _replicatePreviewsByVariant['$variantId'] = urls;
        _lengthNote = data['lengthNote']?.toString();
        _previewGenerating = false;
      });
      UserSession.selectedPreviewImages = urls;
      UserSession.customerPreviewImages = urls;
      if (fromCache) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loaded saved preview (no new Replicate credits used).'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewError = e.toString();
        _previewGenerating = false;
      });
    }
  }

  String get _selectedStyleName =>
      _selected?['style_name']?.toString() ??
      _selected?['styleName']?.toString() ??
      'Style';

  Future<void> _bookSelected() async {
    if (_bookingInFlight) {
      return;
    }

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

    setState(() => _bookingInFlight = true);

    final userId = UserSession.userId;
    if (userId == null) {
      setState(() => _bookingInFlight = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again.')),
      );
      return;
    }

    try {
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

      final scanSessionId = UserSession.ensureScanSessionId();
      UserSession.capturedFaceImages = Map<String, String>.from(widget.captures);

      await FaceScanService.ensureCapturesOnServer(
        scanSessionId: scanSessionId,
        userId: userId,
        captures: widget.captures,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
      );

      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = _selectedStyleName;

      var previewUrls = _previewUrlsForVariant(variantId);
      if (previewUrls == null || (previewUrls['frontViewUrl'] ?? '').isEmpty) {
        final catalog = _catalogPreviewUrls(selected);
        if ((catalog['frontViewUrl'] ?? '').isEmpty) {
          if (!mounted) return;
          setState(() => _bookingInFlight = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This style has no bookable images yet.')),
          );
          return;
        }
        if (!mounted) return;
        final proceed = await _confirmBookWithoutAiPreview(_selectedStyleName);
        if (!mounted) return;
        if (!proceed) {
          setState(() => _bookingInFlight = false);
          return;
        }
        previewUrls = catalog;
      }
      UserSession.selectedPreviewImages = previewUrls;
      UserSession.customerPreviewImages = previewUrls;

      unawaited(
        AiFunnelService.saveSelection(
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
        ).catchError((_) {}),
      );

      final result = await BookingSlotsService.fetchBestSuggestion();
      if (!mounted) return;
      setState(() => _bookingInFlight = false);

      if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
        return;
      }

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No available slots found. Please choose manually.'),
          ),
        );
        await BookingDraftService.saveFromSession(step: 'barber');
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      await BookingDraftService.saveFromSession(step: 'barber');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SuggestedAppointmentPage(suggestion: result.suggestion!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bookingInFlight = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking prep failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          UserSession.resetScanState();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        showCustomerActions: !widget.kioskMode,
        onBack: _leaveResults,
      ),
      body: _error != null ? _errorView() : _content(),
      floatingActionButton: widget.kioskMode
          ? null
          : const AiChatbotFab(heroTag: 'results_ai_chat_fab'),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: widget.kioskMode
          ? null
          : AppBottomNavBar(
              currentIndex: 2,
              onTap: (index) {
                if (index == 0) {
                  UserSession.resetScanState();
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

  Widget _captureFallback(String? captureB64) {
    if (captureB64 != null && captureB64.isNotEmpty) {
      return Image.memory(
        base64Decode(captureB64),
        fit: BoxFit.cover,
        width: double.infinity,
        gaplessPlayback: true,
      );
    }
    return const Center(
      child: Icon(Icons.face, color: Colors.white38, size: 48),
    );
  }

  Widget _content() {
    final angleKey = _angleKeys[_previewAngleIndex];
    final captureB64 = widget.captures[angleKey];
    final variantId = _selectedVariantId ?? 0;
    final previewUrl = variantId > 0 ? _previewUrlForAngle(variantId, angleKey) : null;

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
                const SizedBox(width: 8),
                _chip('Length: ${widget.hairLengthLabel}'),
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
            if (_selected != null &&
                !_previewGenerating &&
                _previewUrlsForVariant(_selectedVariantId ?? 0) == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Tap a style below to generate an AI preview (uses Replicate credits once per style).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            _buildCaptureThumbnails(),
            const SizedBox(height: 10),
            if (_lengthNote != null && _lengthNote!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2208),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC9B46A)),
                ),
                child: Text(
                  _lengthNote!,
                  style: const TextStyle(color: Color(0xFFC9B46A), fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
            ScannerLayout.previewFrame(
              context: context,
              child: _previewGenerating
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Generating AI preview…\nThis can take a few minutes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : previewUrl != null && previewUrl.isNotEmpty
                      ? Image.network(
                          ApiConfig.resolveImageUrl(previewUrl),
                          key: ValueKey('replicate-$variantId-$angleKey'),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => _captureFallback(captureB64),
                        )
                      : _captureFallback(captureB64),
            ),
            if (_previewError != null) ...[
              const SizedBox(height: 8),
              Text(
                'AI preview unavailable — showing your photo.',
                style: TextStyle(color: Colors.orange.shade200, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            if (_selected != null && !_previewGenerating) ...[
              Center(
                child: TextButton.icon(
                  onPressed: _previewUrlsForVariant(variantId) != null
                      ? () => _loadReplicatePreviewsForSelected(forceRegenerate: true)
                      : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Regenerate preview'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                ),
              ),
              const SizedBox(height: 4),
            ],
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
                    Text('Finding styles for your face...', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            ] else ...[
              if (_topPicks.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionTitle('Top picks'),
                ..._topPicks.map(_styleTile),
              ],
              if (_categoriesLoading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Grouping formal, alternative, and youthful picks...',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                if (_categories['formal']!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('Formal'),
                  ..._categories['formal']!.map(_styleTile),
                ],
                if (_categories['alternative']!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Alternative'),
                  ..._categories['alternative']!.map(_styleTile),
                ],
                if (_categories['youthful']!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionTitle('Youthful'),
                  ..._categories['youthful']!.map(_styleTile),
                ],
              ],
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
