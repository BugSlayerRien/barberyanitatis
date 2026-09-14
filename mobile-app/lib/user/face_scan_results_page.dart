import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'app_brand.dart';
import 'feature_flags.dart';
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
import 'recommendation_match_display.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';
import '../kiosk/kiosk_barber_page.dart';
import '../kiosk/kiosk_session.dart';

enum _PreviewPromptChoice { cancel, loadSaved, generateNew }

class FaceScanResultsPage extends StatefulWidget {
  final Map<String, String> captures;
  final String faceShape;
  final String hairTexture;
  final int hairLengthLevel;
  final String hairLengthLabel;
  final String? analysisProvider;
  final double? hairTextureScore;
  final bool noHairDetected;
  final String? hairColorLabel;
  final Map<String, dynamic>? presetRecommendation;
  final bool kioskMode;

  const FaceScanResultsPage({
    super.key,
    required this.captures,
    required this.faceShape,
    required this.hairTexture,
    this.hairLengthLevel = 1,
    this.hairLengthLabel = 'short',
    this.analysisProvider,
    this.hairTextureScore,
    this.noHairDetected = false,
    this.hairColorLabel,
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
  };
  Map<String, dynamic>? _selected;
  String? _expandedVariantId;
  int _previewAngleIndex = 0;
  bool _bookingInFlight = false;
  bool _previewGenerating = false;
  String? _previewError;
  String? _lengthNote;
  late String _faceShape;
  late String _hairTexture;
  late bool _noHairDetected;
  String? _analysisProvider;
  double? _hairTextureScore;
  String? _hairColorLabel;
  final Map<String, Map<String, String>> _replicatePreviewsByVariant = {};
  Map<String, Map<String, dynamic>> _previewDiagnostics = {};
  int _previewImageCacheBuster = 0;
  static const _angleKeys = ['front', 'left', 'right'];
  static const _angleLabels = ['Front', 'Left', 'Right'];
  static const _textureOptions = ['Straight', 'Wavy', 'Curly'];

  Map<String, Rect> get _faceRects =>
      UserSession.captureFaceRects ?? {};

  @override
  void initState() {
    super.initState();
    final scan = UserSession.lastScan;
    _faceShape = widget.faceShape;
    _hairTexture = widget.hairTexture;
    _analysisProvider =
        widget.analysisProvider ?? scan?['analysisProvider']?.toString();
    _noHairDetected = _analysisProvider == 'ai-service' &&
        (widget.analysisProvider != null
            ? widget.noHairDetected
            : scan?['noHairDetected'] == true);
    _hairTextureScore = widget.hairTextureScore ??
        (scan?['hairTextureScore'] as num?)?.toDouble();
    _hairColorLabel =
        widget.hairColorLabel ?? scan?['hairColor']?.toString();
    _selected = widget.presetRecommendation;
    _restoreCachedPreviewsFromSession();
    // Re-entering this page must not re-rank. The second stage of
    // _loadRecommendations calls the AI reranker, which is non-deterministic,
    // so every return trip produced a different Top Picks order. Reuse the
    // ranking already computed for this scan; only fetch when there is none.
    if (!_restoreCachedRecommendations()) {
      _loadRecommendations();
    }
  }

  /// Rehydrate AI try-ons from session memory after navigation recreates this page.
  void _restoreCachedPreviewsFromSession() {
    final urls =
        UserSession.selectedPreviewImages ?? UserSession.customerPreviewImages;
    final variantId = UserSession.selectedVariantId;
    if (variantId == null || variantId <= 0 || urls == null) {
      return;
    }
    final front = urls['frontViewUrl']?.trim() ?? '';
    if (front.isEmpty) {
      return;
    }
    _replicatePreviewsByVariant['$variantId'] = Map<String, String>.from(urls);
  }

  Future<void> _applyHairTextureOverride(String texture) async {
    final normalized = UserSession.normalizeHairTextureLabel(texture);
    setState(() => _hairTexture = normalized);
    UserSession.lastScan = {
      ...?UserSession.lastScan,
      'userId': UserSession.userId,
      'hairTexture': normalized,
      'analysisProvider': 'manual',
      // Keep prior scanSucceeded — manual tweak is only usable after a real AI scan.
    };
    UserSession.commitCompletedScan();
    await _loadRecommendations(preserveSelection: true);
  }

  Future<bool> _confirmLeaveResults() async {
    if (widget.kioskMode) {
      return true;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Leave scan?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You can leave and return later via View results on Home. Your completed scan stays available.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _leaveResults() async {
    final leave = await _confirmLeaveResults();
    if (!leave || !mounted) {
      return;
    }
    if (UserSession.capturedFaceImages == null ||
        UserSession.capturedFaceImages!.isEmpty) {
      UserSession.capturedFaceImages = Map<String, String>.from(widget.captures);
    }
    UserSession.commitCompletedScan();
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
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        userId: UserSession.userId,
        boostStyleKeys: FaceScanService.boostStyleKeysFromLastScan(),
      );

      if (!mounted) return;

      if (quick.isNotEmpty) {
        final local = FaceScanService.buildLocalInsightsFromRankings(
          rankings: quick,
          faceShape: _faceShape,
          hairTexture: _hairTexture,
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
          };
          _aiSummary = local['aiSummary']?.toString() ?? '';
          _recommendationsLoading = false;
          _categoriesLoading = true;
          if (!preserveSelection) {
            final sessionVariantId = UserSession.selectedVariantId;
            if (sessionVariantId != null && sessionVariantId > 0) {
              for (final row in _topPicks) {
                if ((int.tryParse('${row['variant_id'] ?? row['variantId']}') ?? 0) ==
                    sessionVariantId) {
                  _selected = row;
                  break;
                }
              }
            }
            _selected ??= widget.presetRecommendation ?? _topPicks.first;
          }
        });
      }
    } catch (_) {
      // Full insights load may still succeed.
    }

    try {
      final data = await FaceScanService.fetchRecommendations(
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        userId: UserSession.userId,
        boostStyleKeys: FaceScanService.boostStyleKeysFromLastScan(),
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
        },
        aiSummary: data['aiSummary']?.toString() ?? '',
        aiPowered: data['aiPowered'] == true,
        preserveSelection: preserveSelection,
      );

      final variantIds = <int>[];
      for (final row in top) {
        final id = int.tryParse('${row['variant_id'] ?? row['variantId']}') ?? 0;
        if (id > 0) variantIds.add(id);
      }
      for (final key in ['formal', 'alternative']) {
        for (final row in _mapList(cats[key])) {
          final id = int.tryParse('${row['variant_id'] ?? row['variantId']}') ?? 0;
          if (id > 0) variantIds.add(id);
        }
      }
      if (variantIds.isNotEmpty) {
        await UserSession.saveLastRecommendedVariantIds(variantIds);
      }

      await AiFunnelService.trackScan(
        scanSessionId: UserSession.ensureScanSessionId(),
        userId: UserSession.userId,
        faceShape: _faceShape,
        hairTexture: _hairTexture,
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
          faceShape: _faceShape,
          hairTexture: _hairTexture,
        );
        final localCats = local['categories'] as Map<String, dynamic>? ?? {};
        _applyRecommendationPayload(
          topPicks: _topPicks,
          categories: {
            'formal': _mapList(localCats['formal']),
            'alternative': _mapList(localCats['alternative']),
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

  /// Returns true when a ranking for this exact scan was already computed and
  /// has been restored, so no network call is needed.
  bool _restoreCachedRecommendations() {
    final key = UserSession.recommendationCacheKey(_faceShape, _hairTexture);
    final cached = UserSession.recommendationsForKey(key);
    if (cached == null) return false;

    final topPicks = _mapList(cached['topPicks']);
    if (topPicks.isEmpty) return false;

    final cats = cached['categories'] as Map<String, dynamic>? ?? {};
    _topPicks = topPicks;
    _categories = {
      'formal': _mapList(cats['formal']),
      'alternative': _mapList(cats['alternative']),
    };
    _aiSummary = cached['aiSummary']?.toString() ?? '';
    _aiPowered = cached['aiPowered'] == true;
    _recommendationsLoading = false;
    _categoriesLoading = false;

    final sessionVariantId = UserSession.selectedVariantId;
    if (sessionVariantId != null && sessionVariantId > 0) {
      for (final row in [
        ..._topPicks,
        ..._categories['formal']!,
        ..._categories['alternative']!,
      ]) {
        if ((int.tryParse('${row['variant_id'] ?? row['variantId']}') ?? 0) ==
            sessionVariantId) {
          _selected = row;
          break;
        }
      }
    }
    _selected ??= widget.presetRecommendation ?? _topPicks.first;
    return true;
  }

  void _cacheRecommendations() {
    UserSession.cacheRecommendations(
      UserSession.recommendationCacheKey(_faceShape, _hairTexture),
      {
        'topPicks': _topPicks,
        'categories': {
          'formal': _categories['formal'] ?? const <Map<String, dynamic>>[],
          'alternative':
              _categories['alternative'] ?? const <Map<String, dynamic>>[],
        },
        'aiSummary': _aiSummary,
        'aiPowered': _aiPowered,
      },
    );
  }

  void _applyRecommendationPayload({
    required List<Map<String, dynamic>> topPicks,
    required Map<String, List<Map<String, dynamic>>> categories,
    required String aiSummary,
    required bool aiPowered,
    required bool preserveSelection,
  }) {
    final sessionVariantId = UserSession.selectedVariantId;
    final selectedId = preserveSelection && _selected != null
        ? '${_selected!['variant_id'] ?? _selected!['variantId']}'
        : (sessionVariantId != null && sessionVariantId > 0
            ? '$sessionVariantId'
            : null);

    setState(() {
      _topPicks = topPicks;
      _categories = categories;
      _aiSummary = aiSummary;
      _aiPowered = aiPowered;
      _recommendationsLoading = false;
      if (selectedId != null && selectedId.isNotEmpty) {
        Map<String, dynamic>? match;
        for (final row in [
          ...topPicks,
          ...categories['formal']!,
          ...categories['alternative']!,
        ]) {
          if ('${row['variant_id'] ?? row['variantId']}' == selectedId) {
            match = row;
            break;
          }
        }
        if (match != null) {
          _selected = match;
        } else if (!preserveSelection) {
          _selected ??= widget.presetRecommendation ??
              (topPicks.isNotEmpty ? topPicks.first : null);
        }
      } else if (!preserveSelection) {
        _selected ??= widget.presetRecommendation ??
            (topPicks.isNotEmpty ? topPicks.first : null);
      }
    });

    final priorSucceeded = UserSession.lastScan?['scanSucceeded'] == true ||
        (_analysisProvider?.toLowerCase() == 'ai-service');
    UserSession.lastScan = {
      ...?UserSession.lastScan,
      'userId': UserSession.userId,
      'faceShape': _faceShape,
      'hairTexture': _hairTexture,
      'hairLength': widget.hairLengthLabel,
      'hairLengthLevel': widget.hairLengthLevel,
      'noHairDetected': _noHairDetected,
      'hairColor': _hairColorLabel,
      'analysisProvider': _analysisProvider,
      'hairTextureScore': _hairTextureScore,
      'scanSucceeded': priorSucceeded,
    };
    UserSession.lastRecommendations = List<Map<String, dynamic>>.from(topPicks);
    UserSession.hasRecentRecommendations = topPicks.isNotEmpty;
    // Freeze this ranking for the current scan so returning to the page shows
    // the same order rather than triggering another AI rerank.
    _cacheRecommendations();
    if (UserSession.capturedFaceImages == null ||
        UserSession.capturedFaceImages!.isEmpty) {
      UserSession.capturedFaceImages = Map<String, String>.from(widget.captures);
    }
    UserSession.commitCompletedScan();
  }

  Future<void> _openLivePreview() async {
    if (!kEnableLiveScanner) {
      if (_selected == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select a style below, then tap Generate preview.'),
          ),
        );
        return;
      }
      unawaited(_onRegeneratePreviewPressed());
      return;
    }

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

  String _variantKey(Map<String, dynamic> item) =>
      '${item['variant_id'] ?? item['variantId'] ?? ''}'.trim();

  void _toggleExpanded(Map<String, dynamic> style) {
    final id = _variantKey(style);
    if (id.isEmpty) return;
    setState(() {
      _expandedVariantId = _expandedVariantId == id ? null : id;
      _selected = style;
      _previewError = null;
    });
  }

  Future<_PreviewPromptChoice> _promptPreviewAction({
    required String styleName,
    required bool hasSavedPreview,
    bool regenerate = false,
  }) async {
    if (regenerate) {
      final choice = await showDialog<_PreviewPromptChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Generate a new preview?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Create a fresh AI try-on for "$styleName"? '
            'This uses one of your free style generations again and can take several minutes.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.generateNew),
              child: const Text('Generate new'),
            ),
          ],
        ),
      );
      return choice ?? _PreviewPromptChoice.cancel;
    }

    if (!hasSavedPreview) {
      final choice = await showDialog<_PreviewPromptChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Generate AI preview?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Generate a preview for "$styleName"? '
            'This uses one of your free style generations and can take several minutes.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.generateNew),
              child: const Text('Generate'),
            ),
          ],
        ),
      );
      return choice ?? _PreviewPromptChoice.cancel;
    }

    final choice = await showDialog<_PreviewPromptChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Try another cut?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You already have a saved preview for "$styleName". '
          'Load it for free, or generate a new one.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.loadSaved),
            child: const Text('View saved'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_PreviewPromptChoice.generateNew),
            child: const Text('Generate new'),
          ),
        ],
      ),
    );
    return choice ?? _PreviewPromptChoice.cancel;
  }

  Future<void> _onGeneratePreviewPressed(Map<String, dynamic> style) async {
    final variantId = int.tryParse(_variantKey(style)) ?? 0;
    if (variantId <= 0) return;

    final styleName = style['style_name']?.toString() ??
        style['styleName']?.toString() ??
        'this style';

    final hasSavedPreview = _previewUrlsForVariant(variantId) != null;
    final choice = await _promptPreviewAction(
      styleName: styleName,
      hasSavedPreview: hasSavedPreview,
    );
    if (!mounted || choice == _PreviewPromptChoice.cancel) return;

    setState(() {
      _selected = style;
      _previewError = null;
    });

    final forceRegenerate =
        choice == _PreviewPromptChoice.generateNew && hasSavedPreview;
    unawaited(_loadReplicatePreviewsForSelected(forceRegenerate: forceRegenerate));
  }

  Future<void> _onRegeneratePreviewPressed() async {
    final variantId = _selectedVariantId;
    if (variantId == null || variantId <= 0) return;

    final choice = await _promptPreviewAction(
      styleName: _selectedStyleName,
      hasSavedPreview: true,
      regenerate: true,
    );
    if (!mounted || choice != _PreviewPromptChoice.generateNew) return;

    unawaited(_loadReplicatePreviewsForSelected(forceRegenerate: true));
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

  String _resolvedPreviewNetworkUrl(String path) {
    if (path.isEmpty) return path;
    final base = ApiConfig.resolveImageUrl(path);
    if (_previewImageCacheBuster <= 0) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}t=$_previewImageCacheBuster';
  }

  Map<String, dynamic>? _diagnosticsForAngle(String angleKey) {
    return _previewDiagnostics[angleKey];
  }

  String? _previewDiagnosticWarning(String angleKey) {
    final diag = _diagnosticsForAngle(angleKey);
    if (diag == null) return null;
    final diff = (diag['compositeDiff'] as num?)?.toDouble();
    final maskMax = (diag['maskMax'] as num?)?.toDouble();
    final faceDrift = (diag['faceDrift'] as num?)?.toDouble();
    final usedRaw = diag['usedRawOutput'] == true;
    if (faceDrift != null && faceDrift > 28) {
      return 'Face region shifted in this view. Tap Regenerate preview for a cleaner hair-only result.';
    }
    if (maskMax != null && maskMax < 0.12) {
      return 'Hair region was hard to detect. Retake with hair visible or tap Regenerate.';
    }
    if (diff != null && diff >= 0 && diff < 5.0) {
      final replicateDiff = (diag['replicateHairDiff'] as num?)?.toDouble();
      if (replicateDiff != null && replicateDiff >= 8.0) {
        return 'AI changed the hair but blending kept it soft. Tap Regenerate for a stronger cut.';
      }
      if (replicateDiff != null && replicateDiff < 4.0) {
        return 'AI made a small change on this angle. Tap Regenerate or try brighter lighting.';
      }
      return 'Hair change is subtle on this angle (score ${diff.toStringAsFixed(1)}). Tap Regenerate if you want a stronger style.';
    }
    if (usedRaw) {
      return 'Preview used a fallback blend. Tap Regenerate for a hair-only composite.';
    }
    return null;
  }

  Widget _previewStatusBadge({required bool hasAiPreview}) {
    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasAiPreview ? const Color(0xFF8BC34A) : Colors.white38,
          ),
        ),
        child: Text(
          hasAiPreview ? 'AI try-on' : 'Scanned photos',
          style: TextStyle(
            color: hasAiPreview ? const Color(0xFF8BC34A) : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Future<void> _ensureCapturesUploaded() async {
    final sessionId = UserSession.ensureScanSessionId();
    final payload = <String, String>{};
    for (final angle in ['front', 'left', 'right']) {
      final raw = widget.captures[angle]?.trim() ?? '';
      if (raw.isNotEmpty) {
        payload[angle] = raw;
      }
    }
    if (payload.length < 3) return;
    await FaceScanService.uploadCaptures(
      scanSessionId: sessionId,
      userId: UserSession.userId,
      captures: payload,
      faceShape: _faceShape,
      hairTexture: _hairTexture,
    );
  }

  Future<void> _loadReplicatePreviewsForSelected({bool forceRegenerate = false}) async {
    final variantId = _selectedVariantId;
    if (variantId == null || variantId <= 0) return;

    if (!forceRegenerate && _replicatePreviewsByVariant.containsKey('$variantId')) {
      final urls = _previewUrlsForVariant(variantId);
      if (urls != null) {
        setState(() {
          _previewError = null;
          _previewGenerating = false;
        });
        UserSession.selectedVariantId = variantId;
        UserSession.selectedStyleName = _selectedStyleName;
        UserSession.selectedPreviewImages = urls;
        UserSession.customerPreviewImages = urls;
        UserSession.commitCompletedScan();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Showing saved preview for this style.'),
          ),
        );
      }
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
      await _ensureCapturesUploaded();
      final data = await FaceScanService.generateStylePreviews(
        scanSessionId: UserSession.ensureScanSessionId(),
        variantId: variantId,
        styleName: _selectedStyleName,
        styleCode: _selected?['style_code']?.toString() ?? _selected?['styleCode']?.toString(),
        userId: UserSession.userId,
        faceShape: _faceShape,
        hairTexture: _hairTexture,
        hairLengthLevel: widget.hairLengthLevel,
        forceRegenerate: forceRegenerate,
      );
      if (!mounted) return;
      final urls = FaceScanService.previewUrlsFromResponse(data);
      final fromCache = data['cached'] == true;
      final rawDiag = data['previewDiagnostics'];
      final diagnostics = <String, Map<String, dynamic>>{};
      if (rawDiag is Map) {
        rawDiag.forEach((key, value) {
          if (value is Map) {
            diagnostics['$key'] = Map<String, dynamic>.from(value);
          }
        });
      }
      setState(() {
        _replicatePreviewsByVariant['$variantId'] = urls;
        _previewDiagnostics = diagnostics;
        _previewImageCacheBuster = DateTime.now().millisecondsSinceEpoch;
        _lengthNote = data['lengthNote']?.toString();
        _previewGenerating = false;
        _previewError = null;
      });
      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = _selectedStyleName;
      UserSession.selectedPreviewImages = urls;
      UserSession.customerPreviewImages = urls;
      UserSession.commitCompletedScan();
      final quota = FaceScanService.quotaFromResponse(data);
      if (fromCache) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loaded saved preview (free — no new generation used).'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_generationSuccessMessage(quota))),
        );
      }
    } on FaceScanQuotaExceededException catch (e) {
      if (!mounted) return;
      setState(() {
        _previewGenerating = false;
        _previewError = null;
      });
      await _showQuotaExceededDialog(e);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewError = e.toString();
        _previewGenerating = false;
      });
    }
  }

  String _generationSuccessMessage(Map<String, dynamic>? quota) {
    if (quota == null || quota['unlimited'] == true) {
      return 'AI preview ready — swipe angles to compare.';
    }
    final limit = (quota['limit'] as num?)?.toInt();
    final used = (quota['used'] as num?)?.toInt();
    if (limit == null || used == null) {
      return 'AI preview ready — swipe angles to compare.';
    }
    return 'AI preview ready — swipe angles to compare. ($used of $limit free styles used)';
  }

  Future<void> _showQuotaExceededDialog(FaceScanQuotaExceededException e) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Free style limit reached',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${e.message}\n\nYou can still view and book any style you already generated.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
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
        setState(() => _bookingInFlight = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active appointment.')),
        );
        // Keep this results page under Appointments so generated previews stay in memory.
        await Navigator.of(context).push(
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
        faceShape: _faceShape,
        hairTexture: _hairTexture,
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
          faceShape: _faceShape,
          hairTexture: _hairTexture,
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
          builder: (_) => SuggestedAppointmentPage(
            suggestion: result.suggestion!,
            alternatives: result.alternatives,
          ),
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
      canPop: widget.kioskMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_leaveResults());
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        showCustomerActions: !widget.kioskMode,
        onBack: () => unawaited(_leaveResults()),
      ),
      body: _error != null ? _errorView() : _content(),
      floatingActionButton: widget.kioskMode
          ? null
          : const AiChatbotFab(heroTag: 'results_ai_chat_fab', bottomPadding: 8),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: widget.kioskMode
          ? null
          : AppBottomNavBar(
              currentIndex: 2,
              onTap: (index) {
                if (index == 0) {
                  if (UserSession.capturedFaceImages == null ||
                      UserSession.capturedFaceImages!.isEmpty) {
                    UserSession.capturedFaceImages =
                        Map<String, String>.from(widget.captures);
                  }
                  UserSession.commitCompletedScan();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const DashboardPage()),
                  );
                } else if (index == 1) {
                  // Push (not replace) so generated previews survive when user backs out.
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                  );
                } else if (index == 2) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AiFaceScanPage(startFresh: false),
                    ),
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
              'AI Hair Recommendations',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Face: $_faceShape'),
                _chip('Hair: $_hairTexture'),
                _chip('Length: ${widget.hairLengthLabel}'),
                // Colour chip removed: the detected value is sampled from a
                // geometric hair mask that also picks up background, so it was
                // frequently wrong. The try-on model reads colour straight from
                // the photo, so nothing downstream depends on showing it.
              ],
            ),
            const SizedBox(height: 8),
            _buildHairTypeAdjustment(),
            if (_noHairDetected && _analysisProvider == 'ai-service') ...[
              const SizedBox(height: 10),
              _buildLowHairNotice(),
            ],
            const SizedBox(height: 8),
            const Text(
              'Pick a style below → Generate preview',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
              const SizedBox(height: 12),
            if (_lengthNote != null && _lengthNote!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2208),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppBrand.accent),
                ),
                child: Text(
                  _lengthNote!,
                  style: const TextStyle(color: AppBrand.accent, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
            ScannerLayout.previewFrame(
              context: context,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _previewGenerating
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
                              _resolvedPreviewNetworkUrl(previewUrl),
                              key: ValueKey(
                                'replicate-$variantId-$angleKey-$_previewImageCacheBuster',
                              ),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          gaplessPlayback: true,
                              errorBuilder: (_, error, ___) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  final msg =
                                      'Preview image failed to load. Check that Apache can serve uploads/face_scans.';
                                  if (_previewError != msg) {
                                    setState(() => _previewError = msg);
                                  }
                                });
                                return _captureFallback(captureB64);
                              },
                            )
                          : _captureFallback(captureB64),
                  if (!_previewGenerating)
                    _previewStatusBadge(
                      hasAiPreview: previewUrl != null && previewUrl.isNotEmpty,
                    ),
                ],
              ),
            ),
            if (_previewError != null) ...[
            const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1A10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Text(
                  _previewError!,
                  style: TextStyle(color: Colors.orange.shade200, fontSize: 12, height: 1.35),
                ),
              ),
            ] else if (_previewDiagnosticWarning(angleKey) != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2208),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppBrand.accent),
                ),
                child: Text(
                  _previewDiagnosticWarning(angleKey)!,
                  style: const TextStyle(color: AppBrand.accent, fontSize: 12, height: 1.35),
                ),
              ),
            ],
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
            if (_selected == null)
              const Text(
                'Select a style below, expand for details, then tap Generate preview.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
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
                        'Grouping formal and alternative picks...',
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
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected == null || _bookingInFlight ? null : _bookSelected,
                style: widget.kioskMode
                    ? AppBrand.primaryButton.copyWith(
                        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)),
                      )
                    : ElevatedButton.styleFrom(
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
            if (!widget.kioskMode && kEnableLiveScanner) ...[
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

  Widget _buildHairTypeAdjustment() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.white12),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: const Text(
          'Adjust hair type',
          style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        iconColor: Colors.white54,
        collapsedIconColor: Colors.white38,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _textureOptions.map((texture) {
              final selected = _hairTexture == texture;
              return ChoiceChip(
                label: Text(texture, style: const TextStyle(fontSize: 11)),
                selected: selected,
                onSelected: (_) => _applyHairTextureOverride(texture),
                selectedColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
                backgroundColor: const Color(0xFF1E1E1E),
                side: const BorderSide(color: Colors.white24),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
    );
  }

  Widget _buildLowHairNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'Little or no visible hair was detected. You can still browse and try styles — '
        'previews may look more aspirational until hair grows in.',
        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
      ),
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
    final variantId = _variantKey(item);
    final name = item['style_name']?.toString() ?? item['styleName']?.toString() ?? 'Style';
    final reason = item['fit_reason']?.toString() ?? '';
    final catalogDesc = item['description']?.toString().trim() ?? '';
    final rankLabel = RecommendationMatchDisplay.rankLabel(item);
    final selected = _selected != null && _variantKey(_selected!) == variantId;
    final expanded = _expandedVariantId == variantId && variantId.isNotEmpty;
    final variantIdInt = int.tryParse(variantId) ?? 0;
    final previewReady =
        variantIdInt > 0 && _previewUrlsForVariant(variantIdInt) != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? (widget.kioskMode ? AppBrand.goldTint : const Color(0xFF1F1F1F))
                : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? (widget.kioskMode ? AppBrand.gold : Colors.white)
                  : Colors.white10,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => _toggleExpanded(item),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white54,
                      size: 22,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (rankLabel != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              rankLabel,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                            ),
                          ],
                          if (!expanded) ...[
                            const SizedBox(height: 4),
                            Text(
                              RecommendationMatchDisplay.fitReasonTeaser(item),
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1, color: Colors.white12),
                Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reason.isNotEmpty)
                      Text(
                        reason,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    if (catalogDesc.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        catalogDesc,
                        style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _previewGenerating
                            ? null
                            : () => _onGeneratePreviewPressed(item),
                        icon: Icon(
                          previewReady ? Icons.check_circle_outline : Icons.auto_awesome,
                          size: 18,
                          color: previewReady ? const Color(0xFF8BC34A) : Colors.white,
                        ),
                        label: Text(
                          previewReady ? 'View / regenerate preview' : 'Generate preview',
                          style: TextStyle(
                            color: previewReady ? const Color(0xFF8BC34A) : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: previewReady ? const Color(0xFF8BC34A) : Colors.white38,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
