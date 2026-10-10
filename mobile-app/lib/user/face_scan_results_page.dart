import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'ai_credit_purchase_page.dart';
import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'app_brand.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'saved_haircuts_page.dart';
import 'api_config.dart';
import 'scanner/scanner_layout.dart';
import 'services/booking_slots_service.dart';
import 'services/booking_draft_service.dart';
import 'services/face_scan_service.dart';
import 'services/saved_previews_service.dart';
import 'suggested_appointment_page.dart';
import 'user_session.dart';
import 'widgets/ai_chatbot_fab.dart';
import 'widgets/library_style_picker_sheet.dart';
import 'recommendation_match_display.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/menu_sheet.dart';
import 'widgets/scan_progress_panel.dart';
import 'widgets/style_length_warning.dart';
import 'widgets/style_view_thumbnail.dart';
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
  /// Styles the customer picked from the Library sheet (not recommended),
  /// newest first. Rendered with the same tile so generate/book work as usual.
  final List<Map<String, dynamic>> _libraryPicks = [];
  Map<String, List<Map<String, dynamic>>> _categories = {
    'formal': [],
    'alternative': [],
  };
  Map<String, dynamic>? _selected;
  String? _expandedVariantId;
  int _previewAngleIndex = 0;
  bool _bookingInFlight = false;
  bool _previewGenerating = false;

  /// True when the preview on screen shows the style grown out rather than
  /// what the barber could cut today. Drives the amber badge and the caption.
  bool _previewIsGrowOutGoal = false;

  /// The hair length the page works from.
  ///
  /// `widget.hairLengthLevel` is what the scan measured, and that is the
  /// weakest thing the scan produces -- it defaults to "short" whenever the
  /// measurement fails. A customer who says the scan got it wrong overrides it
  /// here, exactly as they can already override hair texture.
  int? _lengthOverride;

  int get _effectiveLengthLevel => _lengthOverride ?? widget.hairLengthLevel;

  /// Variants whose generated preview the customer has explicitly saved, and
  /// the saved-row ids needed to unsave them without re-fetching the list.
  final Set<int> _savedVariantIds = <int>{};
  final Map<int, int> _savedLookIds = <int, int>{};
  bool _savingLook = false;
  String? _previewError;
  /// Last quota the server reported for this account (from a successful
  /// generation, a cache hit, or a 429). Kept across calls so a persistent
  /// indicator can show "X of Y used" without waiting for the next attempt.
  /// Seeded from [UserSession.lastQuota] in initState so the pill has
  /// something to show immediately instead of blanking out while the fresh
  /// fetch below is in flight.
  Map<String, dynamic>? _lastQuota;
  bool _quotaRefreshRetried = false;
  /// True only until the very first quota fetch of this process settles (with
  /// its one retry). Distinguishes "still loading, nothing cached yet" (show a
  /// skeleton) from "loaded and unlimited/errored" (show nothing).
  bool _quotaLoading = true;
  late String _faceShape;
  late String _hairTexture;
  late bool _noHairDetected;
  String _hairVisibility = 'ok';
  bool _textureFromProfile = false;
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
    // 'ok' | 'none' (bald/shaved) | 'obstructed' (cap, hood, hand).
    _hairVisibility = scan?['hairVisibility']?.toString() ?? 'ok';
    _hairTextureScore = widget.hairTextureScore ??
        (scan?['hairTextureScore'] as num?)?.toDouble();
    // Fall back to what the customer already told us about themselves, rather
    // than to a guess. Labelled as coming from their profile, not the scan.
    if (_hairTexture.trim().isEmpty) {
      _textureFromProfile = true;
      unawaited(_fillTextureFromProfile());
    }
    _hairColorLabel =
        widget.hairColorLabel ?? scan?['hairColor']?.toString();
    _selected = widget.presetRecommendation;
    _lastQuota = UserSession.lastQuota;
    _quotaLoading = _lastQuota == null;
    _restoreCachedPreviewsFromSession();
    // Re-entering this page must not re-rank. The second stage of
    // _loadRecommendations calls the AI reranker, which is non-deterministic,
    // so every return trip produced a different Top Picks order. Reuse the
    // ranking already computed for this scan; only fetch when there is none.
    if (!_restoreCachedRecommendations()) {
      _loadRecommendations();
    }
    // So the "X of Y" chip is visible immediately, not only after the first
    // generate attempt on this visit.
    unawaited(_refreshQuotaStatus());
    // The bookmark state was previously only ever set by taps on this page, so
    // it drifted from the server the moment a look was saved or deleted
    // anywhere else -- the Saved tab most obviously. One list call sets both
    // maps from the truth.
    unawaited(_hydrateSavedLooks());
  }

  Future<void> _hydrateSavedLooks() async {
    if (UserSession.userId == null) return;
    try {
      final saved = await SavedPreviewsService.list();
      if (!mounted) return;
      setState(() {
        _savedVariantIds.clear();
        _savedLookIds.clear();
        for (final row in saved) {
          final variantId = int.tryParse('${row['variant_id']}') ?? 0;
          final savedId = int.tryParse('${row['saved_preview_id']}') ?? 0;
          if (variantId <= 0 || savedId <= 0) continue;
          _savedVariantIds.add(variantId);
          _savedLookIds[variantId] = savedId;
        }
      });
    } catch (_) {
      // Bookmarks stay as they were; the unsave path re-resolves the id
      // anyway, so a failure here costs accuracy, never correctness.
    }
  }

  Future<void> _refreshQuotaStatus() async {
    final quota = await FaceScanService.fetchQuotaStatus(
      userId: UserSession.userId,
      scanSessionId: UserSession.userId == null ? UserSession.ensureScanSessionId() : null,
    );
    if (quota != null) {
      UserSession.lastQuota = quota;
      if (mounted) {
        setState(() {
          _lastQuota = quota;
          _quotaLoading = false;
        });
      }
      return;
    }
    // A transient network failure would otherwise leave the pill stuck on
    // whatever was seeded (or blank, on a first-ever visit) for the rest of
    // this page's lifetime. One retry covers that without polling forever.
    if (!_quotaRefreshRetried) {
      _quotaRefreshRetried = true;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) {
        unawaited(_refreshQuotaStatus());
      }
      return;
    }
    if (mounted) {
      setState(() => _quotaLoading = false);
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

  /// Uses the texture saved on the customer's profile when the scan could not
  /// measure one. Their own stated answer, not an inference.
  Future<void> _fillTextureFromProfile() async {
    final preferred = await UserSession.loadPreferredHairTexture();
    final normalized = UserSession.normalizeHairTextureOrNull(preferred);
    if (!mounted || normalized == null || normalized.isEmpty) return;

    setState(() => _hairTexture = normalized);
    await _loadRecommendations(preserveSelection: true);
  }

  /// Changing the detected hair type is not a filter tweak.
  ///
  /// Texture is the strongest signal in the ranking -- a match adds 0.55 and a
  /// mismatch subtracts 0.15 -- so overriding it rebuilds the whole list and
  /// changes which cuts the AI will render well. A customer who tapped a chip
  /// to see what it did had no way to know that, and no way back except
  /// remembering what the scan originally said.
  Future<bool> _confirmTextureOverride(String texture) async {
    final detected = widget.hairTexture.trim();
    final isReverting = detected.isNotEmpty &&
        UserSession.normalizeHairTextureLabel(detected) ==
            UserSession.normalizeHairTextureLabel(texture);
    if (isReverting) return true;

    final scanned = detected.isEmpty ? 'the scan result' : detected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Change your hair type?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'The scan read your hair as $scanned. Setting it to $texture '
          'rebuilds your recommendations and changes how an AI preview is '
          'generated.\n\nOnly change this if the scan got it wrong.',
          style: const TextStyle(color: Colors.white70, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep $scanned',
                style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            child: Text('Set to $texture'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _applyHairTextureOverride(String texture) async {
    if (_hairTexture == UserSession.normalizeHairTextureLabel(texture)) return;
    if (!await _confirmTextureOverride(texture)) return;
    if (!mounted) return;

    final normalized = UserSession.normalizeHairTextureLabel(texture);
    setState(() {
      _hairTexture = normalized;
      _textureFromProfile = false;
    });
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
        backgroundColor: AppBrand.panel,
        shape: RoundedRectangleBorder(
          borderRadius: AppBrand.radiusMd,
          side: const BorderSide(color: AppBrand.border),
        ),
        title: const Text('Leave scan?', style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w700)),
        content: const Text(
          'You can leave and return later via View results on Home. Your completed scan stays available.',
          style: TextStyle(color: AppBrand.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: AppBrand.accent),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppBrand.danger),
            child: const Text('Leave'),
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

  bool _needsMoreLength(Map<String, dynamic> style) =>
      styleNeedsMoreLength(style, _effectiveLengthLevel);

  /// Accepts the customer's word over the scan's, and remembers it.
  ///
  /// Mirrors _applyHairTextureOverride: written into UserSession so it
  /// survives leaving the page, rather than living only in this widget.
  void _acceptLongerHairClaim(Map<String, dynamic> style) {
    final needed = (style['min_length_level'] as num?)?.toInt() ??
        (style['minLengthLevel'] as num?)?.toInt() ??
        _effectiveLengthLevel;

    setState(() => _lengthOverride = needed);
    UserSession.lastScan = {
      ...?UserSession.lastScan,
      'hairLengthLevel': needed,
      'hairLengthSource': 'customer',
    };
    UserSession.commitCompletedScan();
  }

  /// The best style on this page the customer could actually have cut today.
  ///
  /// Picked from the rankings the server already returned -- every row carries
  /// min_length_level -- so this needs no extra call and no second idea of
  /// what suits them.
  Map<String, dynamic>? get _achievableAlternative {
    for (final row in [
      ..._topPicks,
      ..._categories['formal'] ?? const <Map<String, dynamic>>[],
      ..._categories['alternative'] ?? const <Map<String, dynamic>>[],
      ..._libraryPicks,
    ]) {
      if (!styleNeedsMoreLength(row, _effectiveLengthLevel)) return row;
    }

    return null;
  }

  Future<LengthChoice> _confirmLongerHairStyle(String styleName) =>
      confirmLongerHairStyle(
        context,
        styleName,
        canShowAlternatives: _achievableAlternative != null,
      );

  Future<void> _onGeneratePreviewPressed(Map<String, dynamic> style) async {
    final variantId = int.tryParse(_variantKey(style)) ?? 0;
    if (variantId <= 0) return;

    final styleName = style['style_name']?.toString() ??
        style['styleName']?.toString() ??
        'this style';

    final hasSavedPreview = _previewUrlsForVariant(variantId) != null;

    // Ask before the generation prompt, not after: a customer who backs out
    // here has spent nothing.
    var growOut = _needsMoreLength(style);
    if (growOut && !hasSavedPreview) {
      switch (await _confirmLongerHairStyle(styleName)) {
        case LengthChoice.cancel:
          return;
        case LengthChoice.showAlternatives:
          if (!mounted) return;
          final alternative = _achievableAlternative;
          if (alternative != null) {
            setState(() {
              _selected = alternative;
              _expandedVariantId = _variantKey(alternative);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${alternative['style_name'] ?? 'This style'} suits your '
                  'length today — generate it instead.',
                ),
              ),
            );
          }
          return;
        case LengthChoice.correctLength:
          // Their hair is long enough after all, so this is an ordinary
          // generation with no goal label.
          _acceptLongerHairClaim(style);
          growOut = false;
        case LengthChoice.growOutGoal:
          break;
      }
      if (!mounted) return;
    }
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
    setState(() => _previewIsGrowOutGoal = growOut);

    unawaited(_loadReplicatePreviewsForSelected(
      forceRegenerate: forceRegenerate,
    ));
  }

  /// Lets a customer who doesn't like the recommendations pick any library
  /// style that suits their scanned texture, then generate it on this scan
  /// through the same confirm-and-generate path as a recommended style.
  Future<void> _openLibraryPicker() async {
    String nameOf(Map<String, dynamic> row) =>
        (row['style_name'] ?? row['styleName'] ?? '').toString().trim().toLowerCase();
    final shown = <String>{
      for (final row in [
        ..._topPicks,
        ..._categories['formal']!,
        ..._categories['alternative']!,
        ..._libraryPicks,
      ])
        nameOf(row),
    }..remove('');

    final picked = await showLibraryStylePicker(
      context,
      hairTexture: _hairTexture,
      excludeStyleNames: shown,
    );
    if (picked == null || !mounted) return;

    final id = _variantKey(picked);
    setState(() {
      _libraryPicks.removeWhere((row) => _variantKey(row) == id);
      _libraryPicks.insert(0, picked);
      _expandedVariantId = id;
      _selected = picked;
      _previewError = null;
    });
    await _onGeneratePreviewPressed(picked);
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
    // Checked first: if left and right show the same pose, nothing else the
    // other checks report about this angle is worth acting on yet.
    if (diag['duplicateView'] == true) {
      return 'The left and right previews came back showing the same angle. '
          'Tap Regenerate preview to try again.';
    }
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
    final saveButton = _buildSaveLookButton();
    return Positioned(
      top: 10,
      left: 10,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
          // On the image rather than only beneath it, so a screenshot carries
          // the label with it.
          if (hasAiPreview && _previewIsGrowOutGoal) ...[
            const SizedBox(width: 6),
            const GrowOutGoalBadge(),
          ],
          if (saveButton != null) ...[
            const SizedBox(width: 6),
            saveButton,
          ],
        ],
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

  Future<void> _loadReplicatePreviewsForSelected({
    bool forceRegenerate = false,
    bool achievableToday = false,
  }) async {
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
        achievableToday: achievableToday,
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
        _previewGenerating = false;
        _previewError = null;
      });
      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = _selectedStyleName;
      UserSession.selectedPreviewImages = urls;
      UserSession.customerPreviewImages = urls;
      UserSession.commitCompletedScan();
      final quota = FaceScanService.quotaFromResponse(data);
      if (quota != null) {
        UserSession.lastQuota = quota;
        setState(() => _lastQuota = quota);
      }
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
      final quotaFromError = {
        'limit': e.limit,
        'used': e.used,
        'remaining': e.remaining,
        'unlimited': e.unlimited,
        'purchased': e.purchased,
      };
      UserSession.lastQuota = quotaFromError;
      setState(() {
        _previewGenerating = false;
        _previewError = null;
        _lastQuota = quotaFromError;
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

  /// "$used of $limit ..." wording that tells a free allotment apart from
  /// purchased top-up credits, instead of calling the whole `limit` "free"
  /// once AiCreditPurchasePage credits are mixed into it.
  String _previewsUsedLabel({
    required int used,
    required int limit,
    required int purchased,
    required String noun,
  }) {
    if (purchased <= 0) return '$used of $limit free $noun used';
    return '$used of $limit $noun used ($purchased purchased)';
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
    final purchased = (quota['purchased'] as num?)?.toInt() ?? 0;
    final label = _previewsUsedLabel(
      used: used,
      limit: limit,
      purchased: purchased,
      noun: 'styles',
    );
    return 'AI preview ready — swipe angles to compare. ($label)';
  }

  /// Kiosk walk-ins have no login, so there is no account to attach a
  /// purchase to (see ai_tryon_effective_style_limit — top-ups only apply to a
  /// signed-in userId). The purchase entry point is hidden there rather than
  /// shown and failing.
  bool get _canPurchaseCredits => !widget.kioskMode && UserSession.userId != null;

  Future<void> _openCreditPurchase() async {
    final quota = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        settings: const RouteSettings(name: AiCreditPurchasePage.routeName),
        builder: (_) => const AiCreditPurchasePage(),
      ),
    );
    if (quota != null) {
      UserSession.lastQuota = quota;
      if (mounted) {
        setState(() => _lastQuota = quota);
      }
    }
    // A late deep-link return (PaymentResultPage) pops the purchase page with
    // no result, so re-read the server either way.
    _quotaRefreshRetried = false;
    unawaited(_refreshQuotaStatus());
  }

  Future<void> _showQuotaExceededDialog(FaceScanQuotaExceededException e) async {
    if (!mounted) return;
    // e.hint is the server's own guidance for this response (e.g. "you can still
    // view or regenerate a style you already tried"). Previously this dialog
    // always showed a hardcoded sentence instead, which drifts if the server-side
    // wording ever changes.
    final hint = (e.hint?.trim().isNotEmpty ?? false)
        ? e.hint!.trim()
        : 'You can still view and book any style you already generated.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Preview limit reached',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.purchased > 0
                  ? "You've used ${e.used} of ${e.limit} previews (${e.purchased} purchased)."
                  : "You've used ${e.used} of ${e.limit} free previews.",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
          if (_canPurchaseCredits)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_openCreditPurchase());
              },
              child: Text(
                'Get ${AiCreditPurchasePage.bundleCredits} more — '
                '₱${AiCreditPurchasePage.bundleAmountPhp.toStringAsFixed(0)}',
              ),
            ),
        ],
      ),
    );
  }

  /// "Save this look" for the generated preview currently on screen.
  ///
  /// Saving is opt-in: a generated preview otherwise lives only in this scan
  /// session's cache and becomes unreachable after the next scan. Hidden in
  /// kiosk mode, where a walk-in has no account to save against, and hidden
  /// until a real AI preview exists (a catalog photo is not the customer's
  /// look).
  Widget? _buildSaveLookButton() {
    if (widget.kioskMode || UserSession.userId == null) return null;
    final variantId = _selectedVariantId;
    if (variantId == null || variantId <= 0) return null;
    final urls = _previewUrlsForVariant(variantId);
    final front = urls?['frontViewUrl']?.trim() ?? '';
    if (front.isEmpty) return null;

    final saved = _savedVariantIds.contains(variantId);
    return Tooltip(
      message: saved ? 'Saved to your looks' : 'Save this look',
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        shape: StadiumBorder(
          side: BorderSide(color: saved ? AppBrand.accent : Colors.white38),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _savingLook ? null : () => unawaited(_toggleSaveLook(variantId)),
          child: SizedBox(
            // Matches the badge's height while keeping a finger-sized target.
            width: 44,
            height: 28,
            child: Center(
              child: _savingLook
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border,
                      size: 17,
                      color: saved ? AppBrand.accent : Colors.white70,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSaveLook(int variantId) async {
    final urls = _previewUrlsForVariant(variantId);
    final front = urls?['frontViewUrl']?.trim() ?? '';
    if (front.isEmpty) return;

    setState(() => _savingLook = true);
    try {
      if (_savedVariantIds.contains(variantId)) {
        // The cached id goes stale as soon as the look is deleted from the
        // Saved tab while this page is still on the navigation stack, so fall
        // back to resolving it from the server. Without this, an unsave either
        // 404'd or -- when nothing was cached -- silently skipped the server
        // entirely and left the row in place while the UI claimed otherwise.
        final savedId = _savedLookIds[variantId] ??
            await SavedPreviewsService.savedIdFor(
              variantId: variantId,
              scanSessionId: UserSession.ensureScanSessionId(),
            );
        if (savedId != null) {
          await SavedPreviewsService.delete(savedId);
        }
        if (!mounted) return;
        setState(() {
          _savedVariantIds.remove(variantId);
          _savedLookIds.remove(variantId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from your saved looks.')),
        );
        return;
      }

      final savedId = await SavedPreviewsService.save(
        variantId: variantId,
        scanSessionId: UserSession.ensureScanSessionId(),
        frontViewUrl: front,
        sideViewUrl: urls?['sideViewUrl'],
        backViewUrl: urls?['backViewUrl'],
        styleName: _selectedStyleName,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
      );
      if (!mounted) return;
      setState(() {
        _savedVariantIds.add(variantId);
        if (savedId != null) _savedLookIds[variantId] = savedId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Find it under Saved → Your AI looks.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update your saved looks: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingLook = false);
    }
  }

  /// Compact "previews left" pill for the Top picks row: an icon, the number
  /// still available, a + to buy more, and a ? explaining what the number is.
  ///
  /// Shows what is *left* rather than what has been used, because remaining is
  /// the number a customer acts on. Free and purchased are deliberately summed
  /// into one figure -- the breakdown lives in the help sheet, since which
  /// bucket a preview comes from does not change what they can do next.
  /// Placeholder shown only while the very first quota fetch of this process
  /// is still in flight (no cached value to seed from) -- so the pill's slot
  /// is occupied instead of the row silently having no trailing widget.
  Widget _quotaPillSkeleton() {
    return Container(
      width: 54,
      height: 26,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38),
      ),
    );
  }

  Widget? _quotaPill() {
    final quota = _lastQuota;
    if (quota == null) {
      // Nothing cached yet and the first fetch (plus its retry) hasn't
      // settled -- a bare skeleton beats the pill silently never appearing.
      return _quotaLoading ? _quotaPillSkeleton() : null;
    }
    if (quota['unlimited'] == true) return null;
    final limit = (quota['limit'] as num?)?.toInt();
    final used = (quota['used'] as num?)?.toInt();
    if (limit == null || used == null || limit <= 0) return null;

    // Clamped: `used` can legitimately exceed `limit` (previews generated while
    // AI_TRYON_UNLIMITED was on, or before a limit was lowered), and a negative
    // "left" count would be nonsense.
    final remaining = (limit - used).clamp(0, limit);
    final isEmpty = remaining <= 0;
    final canBuy = _canPurchaseCredits;

    final accentColor = isEmpty ? Colors.orange.shade200 : Colors.white70;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: isEmpty ? const Color(0xFF3A1A10) : const Color(0xFF1A1A1A),
          shape: StadiumBorder(
            side: BorderSide(color: isEmpty ? Colors.orange.shade300 : Colors.white24),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canBuy ? () => unawaited(_openCreditPurchase()) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 7, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: accentColor),
                  const SizedBox(width: 5),
                  Text(
                    '$remaining',
                    style: TextStyle(
                      color: isEmpty ? Colors.orange.shade200 : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (canBuy) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.add_circle, size: 15, color: accentColor),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: _showQuotaHelp,
          icon: const Icon(Icons.help_outline, size: 16, color: Colors.white38),
          tooltip: 'What is this number?',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Future<void> _showQuotaHelp() async {
    final quota = _lastQuota;
    final limit = (quota?['limit'] as num?)?.toInt() ?? 0;
    final used = (quota?['used'] as num?)?.toInt() ?? 0;
    final purchased = (quota?['purchased'] as num?)?.toInt() ?? 0;
    final free = (limit - purchased).clamp(0, limit);
    final remaining = (limit - used).clamp(0, limit);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppBrand.panel,
        shape: RoundedRectangleBorder(
          borderRadius: AppBrand.radiusMd,
          side: const BorderSide(color: AppBrand.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: AppBrand.accent),
            SizedBox(width: 8),
            Text(
              'AI previews',
              style: TextStyle(color: AppBrand.text, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This number is how many AI hairstyle previews you have left. '
              'Generating a new style uses one.',
              style: const TextStyle(color: AppBrand.textMuted, height: 1.45).copyWith(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            _quotaHelpRow('Previews left', '$remaining'),
            _quotaHelpRow('Free allowance', '$free'),
            if (purchased > 0) _quotaHelpRow('Purchased', '$purchased'),
            _quotaHelpRow('Used so far', '$used'),
            const SizedBox(height: 12),
            const Text(
              'Reopening a style you already generated is free — it does not use another preview.',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: AppBrand.accent),
            child: const Text('Got it'),
          ),
          if (_canPurchaseCredits)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_openCreditPurchase());
              },
              child: Text(
                'Get ${AiCreditPurchasePage.bundleCredits} more — '
                '₱${AiCreditPurchasePage.bundleAmountPhp.toStringAsFixed(0)}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _quotaHelpRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
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
        onProfileTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
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
                // Never show a texture the scan did not measure; that is
                // how a shirt over the head produced "Hair: Wavy".
                if (_hairTexture.trim().isEmpty)
                  _chip('Hair: not measured')
                else if (_textureFromProfile)
                  _chip('Hair: $_hairTexture (from your profile)')
                else
                  _chip('Hair: $_hairTexture'),
                _chip('Length: ${widget.hairLengthLabel}'),
                // Colour chip removed: the detected value is sampled from a
                // geometric hair mask that also picks up background, so it was
                // frequently wrong. The try-on model reads colour straight from
                // the photo, so nothing downstream depends on showing it.
              ],
            ),
            const SizedBox(height: 8),
            if (_hairVisibility != 'ok') ...[
              const SizedBox(height: 2),
              _buildHairVisibilityNotice(),
              const SizedBox(height: 10),
            ] else ...[
              _buildHairTypeAdjustment(),
              if (_noHairDetected && _analysisProvider == 'ai-service') ...[
                const SizedBox(height: 10),
                _buildLowHairNotice(),
              ],
            ],
            const SizedBox(height: 8),
            const Text(
              'Pick a style below → Generate preview',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
              const SizedBox(height: 12),
            ScannerLayout.previewFrame(
              context: context,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _previewGenerating
                      // Indeterminate on purpose: the server generates all three
                      // angles in one blocking call and reports no partial
                      // progress, so a percentage here would be invented. The
                      // stage list plus an elapsed timer is what is actually
                      // true. See ScanProgressPanel.
                      ? const Center(
                          child: ScanProgressPanel.indeterminate(
                            title: 'Generating your AI preview',
                            stages: [
                              'Preparing your photos',
                              'Rendering front, left and right views',
                              'Finishing up',
                            ],
                            currentStep: 1,
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
            if (_previewIsGrowOutGoal &&
                !_previewGenerating &&
                previewUrl != null &&
                previewUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                growOutCaption(_selectedStyleName),
                style: const TextStyle(
                  color: GrowOutGoalBadge.color,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
              if (_achievableAlternative != null) ...[
                const SizedBox(height: 8),
                _achievableAlternativeCard(_achievableAlternative!),
              ],
            ],
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
              _sectionTitle('Top picks', trailing: _quotaPill()),
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
              if (_libraryPicks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _sectionTitle('From the library'),
                ..._libraryPicks.map(_styleTile),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_openLibraryPicker()),
                  icon: Icon(
                    Icons.grid_view_rounded,
                    color: widget.kioskMode ? AppBrand.gold : Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    'Library',
                    style: TextStyle(color: widget.kioskMode ? AppBrand.gold : Colors.white),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: widget.kioskMode ? AppBrand.goldLine : Colors.white24,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
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

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          if (trailing != null) ...[
            const Spacer(),
            trailing,
          ],
        ],
      ),
    );
  }

  /// Explains why no texture is shown, and offers the one action that helps.
  ///
  /// Bald and covered share a data state -- texture unknown -- but not a
  /// message. Telling someone with a shaved head to remove their cap is
  /// useless; telling someone in a hood that they have no hair is wrong. So the
  /// mechanism is shared and the wording is not. Neither blocks: a customer who
  /// cannot uncover their head keeps the feature, with results based on face
  /// shape.
  Widget _buildHairVisibilityNotice() {
    final obstructed = _hairVisibility == 'obstructed';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: obstructed ? AppBrand.warning : Colors.white24,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                obstructed ? Icons.visibility_off_outlined : Icons.info_outline,
                size: 18,
                color: obstructed ? AppBrand.warning : Colors.white70,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  obstructed
                      ? "We couldn't see your hair"
                      : 'Little or no visible hair',
                  style: TextStyle(
                    color: obstructed ? AppBrand.warning : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            obstructed
                ? 'A cap, hood or covering is hiding it, so we have not guessed '
                    'a hair type. These styles are matched to your face shape. '
                    'Uncover your hair and scan again for a closer match.'
                : 'There is nothing to measure yet, so these styles are matched '
                    'to your face shape. You can still preview any of them.',
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          // Asking beats guessing: the chips below already re-rank on tap.
          const Text(
            'Know your hair type? Pick it and we will match the styles to it.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
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
          if (obstructed) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const AiFaceScanPage(startFresh: true),
                    ),
                  );
                },
                style: AppBrand.primaryButton,
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: const Text(
                  'Scan again',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
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

  /// The catalog photo for a recommendation.
  ///
  /// The URL was already on every row -- variant_ranking.php selects it and the
  /// insight builders copy the whole row through -- and the tile simply never
  /// read it, so customers picked a haircut from its name alone. Bundled
  /// overlay art arrives as an `assets/` path; an admin-uploaded photo arrives
  /// as a URL, so both branches are needed.
  /// "What your barber can cut today", under a grow-out preview.
  ///
  /// One tap selects it, so the honest option is as easy to act on as the
  /// aspirational one.
  Widget _achievableAlternativeCard(Map<String, dynamic> item) {
    final name = item['style_name']?.toString() ??
        item['styleName']?.toString() ??
        'Another style';

    return InkWell(
      onTap: () {
        setState(() {
          _selected = item;
          _expandedVariantId = _variantKey(item);
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            _styleThumbnail(item),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your barber can cut this today',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _styleThumbnail(Map<String, dynamic> item) {
    return StyleViewThumbnail(style: item, size: 58);
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
                    _styleThumbnail(item),
                    const SizedBox(width: 10),
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
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white54,
                      size: 22,
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
                    // The side and back URLs were on every row and never
                    // drawn, so a customer judging a cut could only ever see
                    // the front -- the least informative angle for a fade.
                    if (StyleView.values
                        .any((v) => styleViewUrl(item, v).isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Reference photos',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StyleViewStrip(
                        style: item,
                        onViewTap: (view) => showStyleViewViewer(context, item, view),
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
