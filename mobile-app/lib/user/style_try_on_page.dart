import 'dart:async';

import 'package:flutter/material.dart';

import 'ai_credit_purchase_page.dart';
import 'app_brand.dart';
import 'api_config.dart';
import 'hair_compatibility.dart';
import 'services/face_scan_service.dart';
import 'services/style_booking_launcher.dart';
import 'user_session.dart';
import 'widgets/style_length_warning.dart';
import 'widgets/style_view_thumbnail.dart';

/// Trying one haircut on, for a customer who arrived from the library.
///
/// "Try on" used to hand off to the recommendations page, which does a great
/// deal: it ranks styles, groups them into categories, offers a library
/// picker. A customer who had already chosen a haircut landed in that list
/// with their choice merely pre-selected, nothing generated, and no sign of
/// what to do next -- it read as if the button had failed.
///
/// This page does one thing with one haircut: show it, generate it on the
/// customer's own scan, and offer to book it. Nothing is spent on arrival; the
/// generate button is an explicit act, and the texture and length warnings sit
/// in front of it.
class StyleTryOnPage extends StatefulWidget {
  final Map<String, dynamic> style;
  final Map<String, String> captures;
  final String faceShape;
  final String hairTexture;
  final int hairLengthLevel;

  const StyleTryOnPage({
    super.key,
    required this.style,
    required this.captures,
    this.faceShape = '',
    this.hairTexture = '',
    this.hairLengthLevel = 1,
  });

  @override
  State<StyleTryOnPage> createState() => _StyleTryOnPageState();
}

class _StyleTryOnPageState extends State<StyleTryOnPage> {
  Map<String, String>? _previews;
  Map<String, dynamic>? _quota;
  StyleView _shown = StyleView.front;
  bool _generating = false;
  bool _booking = false;
  String? _error;

  /// Set when the customer accepted the length warning, so a regenerate keeps
  /// rendering what is achievable rather than quietly reverting.
  bool _achievableToday = false;

  int get _variantId =>
      int.tryParse(widget.style['variantId']?.toString() ?? '') ??
      int.tryParse(widget.style['variantID']?.toString() ?? '') ??
      int.tryParse(widget.style['variant_id']?.toString() ?? '') ??
      0;

  String get _styleName =>
      widget.style['name']?.toString() ??
      widget.style['style_name']?.toString() ??
      widget.style['styleName']?.toString() ??
      'This haircut';

  @override
  void initState() {
    super.initState();

    // Save the session on arrival, not only after a generation. A customer who
    // scanned, looked at the haircut and went home to the dashboard had a
    // session the app could see -- the chips were right there -- and a View
    // button that insisted no scan existed.
    UserSession.tryOnStyle = Map<String, dynamic>.from(widget.style);
    if (UserSession.capturedFaceImages == null ||
        UserSession.capturedFaceImages!.isEmpty) {
      UserSession.capturedFaceImages = Map<String, String>.from(widget.captures);
    }
    UserSession.commitCompletedScan();

    _quota = UserSession.lastQuota;
    // A preview generated earlier in this session costs nothing to show again.
    final saved = UserSession.selectedVariantId == _variantId
        ? UserSession.selectedPreviewImages
        : null;
    if (saved != null && (saved['frontViewUrl'] ?? '').isNotEmpty) {
      _previews = Map<String, String>.from(saved);
    }
    unawaited(_refreshQuota());
  }

  Future<void> _refreshQuota() async {
    final quota = await FaceScanService.fetchQuotaStatus(
      userId: UserSession.userId,
      scanSessionId: UserSession.ensureScanSessionId(),
    );
    if (quota == null || !mounted) return;
    UserSession.lastQuota = quota;
    setState(() => _quota = quota);
  }

  String get _quotaLabel {
    final quota = _quota;
    if (quota == null) return '';
    if (quota['unlimited'] == true) return 'Unlimited previews';

    final used = (quota['used'] as num?)?.toInt() ?? 0;
    final limit = (quota['limit'] as num?)?.toInt() ?? 0;
    final purchased = (quota['purchased'] as num?)?.toInt() ?? 0;
    final remaining = (quota['remaining'] as num?)?.toInt() ?? (limit - used);

    // Says "free" only when it is free. Once purchased credits are mixed into
    // the limit, calling the whole allowance free is simply untrue.
    final of = purchased > 0
        ? '$used of $limit used ($purchased purchased)'
        : '$used of $limit free previews used';

    return '$remaining left — $of';
  }

  bool get _canPurchaseCredits => UserSession.userId != null;

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
    // A late deep-link return pops this page without a result, so re-read the
    // server either way rather than trusting the pop.
    await _refreshQuota();
  }

  Future<void> _onGeneratePressed({bool regenerate = false}) async {
    if (_generating) return;

    if (_variantId <= 0) {
      setState(() => _error = 'This haircut cannot be previewed yet.');
      return;
    }

    // The customer's own texture governs. Asked before anything is spent.
    final proceed = await HairCompatibility.confirmBookingIfNeeded(
      context,
      HairCompatibility.evaluateStyleMap(widget.style),
    );
    if (!mounted || !proceed) return;

    // Whether the cut needs more hair is a fact about the scan, not about
    // which button was pressed. Deciding it inside the "first generation"
    // branch meant Generate again quietly reverted to the full-length prompt
    // -- the very thing that drew a long-backed mullet on short hair.
    final needsLength =
        styleNeedsMoreLength(widget.style, widget.hairLengthLevel);

    // The dialog is consent, asked once. The flag above is what actually
    // decides what gets rendered.
    if (needsLength && !_achievableToday) {
      final ok = await confirmLongerHairStyle(context, _styleName);
      if (!mounted || !ok) return;
    }
    final achievable = needsLength;

    setState(() {
      _generating = true;
      _error = null;
      _achievableToday = achievable;
    });

    try {
      final scanSessionId = UserSession.ensureScanSessionId();
      // The generator edits the customer's own photographs, so they have to be
      // on the server before it runs.
      await FaceScanService.ensureCapturesOnServer(
        scanSessionId: scanSessionId,
        userId: UserSession.userId,
        captures: widget.captures,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
      );

      final data = await FaceScanService.generateStylePreviews(
        scanSessionId: scanSessionId,
        variantId: _variantId,
        styleName: _styleName,
        styleCode: widget.style['style_code']?.toString() ??
            widget.style['styleCode']?.toString(),
        userId: UserSession.userId,
        faceShape: widget.faceShape,
        hairTexture: widget.hairTexture,
        hairLengthLevel: widget.hairLengthLevel,
        forceRegenerate: regenerate,
        achievableToday: achievable,
      );
      if (!mounted) return;

      final urls = FaceScanService.previewUrlsFromResponse(data);
      final cached = data['cached'] == true;
      final quota = FaceScanService.quotaFromResponse(data);

      UserSession.selectedVariantId = _variantId;
      UserSession.selectedStyleName = _styleName;
      UserSession.selectedPreviewImages = urls;
      UserSession.customerPreviewImages = urls;
      UserSession.commitCompletedScan();
      if (quota != null) UserSession.lastQuota = quota;

      setState(() {
        _previews = urls;
        _shown = StyleView.front;
        _generating = false;
        if (quota != null) _quota = quota;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cached
              ? 'Loaded your saved preview — no generation used.'
              : 'Preview ready.'),
        ),
      );
    } on FaceScanQuotaExceededException catch (e) {
      if (!mounted) return;
      final quota = {
        'limit': e.limit,
        'used': e.used,
        'remaining': e.remaining,
        'unlimited': e.unlimited,
        'purchased': e.purchased,
      };
      UserSession.lastQuota = quota;
      setState(() {
        _generating = false;
        _quota = quota;
      });
      await _showQuotaExceededDialog(e);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _showQuotaExceededDialog(FaceScanQuotaExceededException e) async {
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
            Text(hint, style: const TextStyle(color: Colors.white70, height: 1.4)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it', style: TextStyle(color: Colors.white70)),
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

  Future<void> _onBookPressed() async {
    if (_booking) return;
    setState(() => _booking = true);
    try {
      // Book with the generated preview when there is one, so the barber sees
      // the picture the customer actually agreed to.
      await launchBookingForStyle(context, widget.style, previewImages: _previews);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previews = _previews;
    final hasPreview = previews != null;

    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppBar(
        backgroundColor: AppBrand.panel,
        foregroundColor: Colors.white,
        title: Text(_styleName, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (hasPreview) _buildPreviewPanel(previews) else _buildIntroPanel(),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x1FD93B30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppBrand.poleRedText.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppBrand.poleRedText, fontSize: 12.5, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildActions(hasPreview),
            const SizedBox(height: 16),
            _buildDetails(),
          ],
        ),
      ),
    );
  }

  /// Before any generation: the reference photos and what will happen.
  Widget _buildIntroPanel() {
    final hasReferencePhotos =
        StyleView.values.any((v) => styleViewUrl(widget.style, v).isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReferencePhotos) ...[
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
              style: widget.style,
              height: 108,
              onViewTap: (view) => showStyleViewViewer(context, widget.style, view),
            ),
          ] else
            Row(
              children: [
                const Icon(Icons.content_cut, color: AppBrand.textMuted, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No photos of this cut yet — the AI preview is the best look '
                    'you can get at it.',
                    style: const TextStyle(
                      color: AppBrand.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          const Text(
            'We generate this cut on your own scan photos — front, side and '
            'back — so you can see it on you before you book.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }

  /// After generation: the three generated views, one at a time.
  Widget _buildPreviewPanel(Map<String, String> previews) {
    const keyFor = {
      StyleView.front: 'frontViewUrl',
      StyleView.side: 'sideViewUrl',
      StyleView.back: 'backViewUrl',
    };
    final available = StyleView.values
        .where((v) => (previews[keyFor[v]] ?? '').trim().isNotEmpty)
        .toList();
    final shown = available.contains(_shown)
        ? _shown
        : (available.isNotEmpty ? available.first : StyleView.front);
    final url = previews[keyFor[shown]] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              color: const Color(0xFF121212),
              child: url.isEmpty
                  ? const Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: Colors.white24, size: 40),
                    )
                  : Image.network(
                      ApiConfig.resolveImageUrl(url),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.white24, size: 40),
                      ),
                    ),
            ),
          ),
        ),
        if (available.length > 1) ...[
          const SizedBox(height: 10),
          SegmentedButton<StyleView>(
            segments: [
              for (final view in available)
                ButtonSegment(value: view, label: Text(view.label)),
            ],
            selected: {shown},
            showSelectedIcon: false,
            onSelectionChanged: (set) => setState(() => _shown = set.first),
          ),
        ],
        if (_achievableToday) ...[
          const SizedBox(height: 10),
          Text(
            'Adapted to your current length — this is the closest version your '
            'barber could cut today.',
            style: TextStyle(
              color: AppBrand.textMuted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(bool hasPreview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_quotaLabel.isNotEmpty) ...[
          Text(
            _quotaLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppBrand.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: _generating
              ? null
              : () => unawaited(_onGeneratePressed(regenerate: hasPreview)),
          icon: _generating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(hasPreview ? Icons.refresh_rounded : Icons.auto_awesome),
          label: Text(
            _generating
                ? 'Generating…'
                : (hasPreview ? 'Generate again' : 'Generate preview'),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _booking ? null : () => unawaited(_onBookPressed()),
          icon: const Icon(Icons.event_available_outlined, size: 18),
          label: Text(_booking ? 'Finding a slot…' : 'Book this haircut'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails() {
    final description = widget.style['description']?.toString().trim() ?? '';
    final instructions = (widget.style['barber_instructions'] ??
            widget.style['barberInstructions'] ??
            widget.style['details'] ??
            '')
        .toString()
        .trim();
    final minutes = widget.style['estimatedMinutes']?.toString() ??
        widget.style['estimated_minutes']?.toString() ??
        '';

    final rows = <Widget>[];
    void add(String label, String value) {
      if (value.isEmpty) return;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
          ),
        ],
      ));
    }

    add('About this cut', description);
    add("What your barber does", instructions);
    add('Typical chair time', minutes.isEmpty ? '' : '$minutes minutes');

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}
