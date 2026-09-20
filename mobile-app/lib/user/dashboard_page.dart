import 'dart:async';

import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'saved_haircuts_page.dart';
import 'haircuts_list_page.dart';
import 'widgets/ai_chatbot_fab.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'widgets/shimmer_skeleton.dart';
import 'customer_api.dart';
import 'recommendation_match_display.dart';
import 'ai_face_scan_page.dart';
import 'appointments_page.dart';
import 'customer_navigation.dart';
import 'face_scan_results_page.dart';
import 'hair_texture_onboarding.dart';
import 'user_session.dart';
import '../main.dart';
import 'services/booking_draft_service.dart';
import 'services/booking_slots_service.dart';
import 'barber_selection_page.dart';
import 'group_size_page.dart';
import 'time_format_utils.dart';
import 'booking_guard.dart';
import 'suggested_appointment_page.dart';
import 'app_brand.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver, RouteAware {
  static const _fontFamily = 'CenturyGothic';

  /// Shop hours run morning to evening, so the greeting is worth getting right
  /// — it is the first line a returning customer reads.
  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  int _selectedIndex = 0; // Home tab

  bool _showWelcome = true;
  Timer? _welcomeTimer;

  bool _needsHairTextureOnboarding = false;
  bool _isRouteSubscribed = false;

  Map<String, dynamic>? _nextUpcomingAppointment;
  Map<String, dynamic>? _slotSuggestion;
  List<Map<String, dynamic>> _slotAlternatives = const [];
  Map<String, dynamic>? _quickBookProfile;
  BookingDraft? _bookingDraft;
  bool _hasActiveAppointment = false;
  Map<String, dynamic>? _favoriteBarber;
  Map<String, dynamic>? _recentHaircut;
  Map<String, dynamic>? _trendingHaircut;
  bool _loadingPersonalInsights = false;
  /// First successful "For you" resolve — avoid skeleton flash on soft refresh.
  bool _personalInsightsResolved = false;
  /// Ignores stale responses when home refresh is triggered again quickly.
  int _homeLoadToken = 0;
  DateTime? _suggestionFetchedAt;
  static const Duration _suggestionTtl = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _welcomeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showWelcome = false;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
    _welcomeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isRouteSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
      _isRouteSubscribed = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadHomeInsights();
    }
  }

  @override
  void didPopNext() {
    _loadHomeInsights();
  }

  Future<void> _bootstrap() async {
    // Shell (Library / Scan / section layout) paints immediately.
    // Hair-texture check and dashboard data load run concurrently — do not
    // wait for profile.php before starting appointment/insights fetches.
    unawaited(_loadHomeInsights());
    await _resolveHairTexture();
  }

  Future<void> _openAppointments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppointmentsPage()),
    );
    if (mounted) {
      unawaited(_loadHomeInsights());
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCustomerAppointments(int userId) async {
    try {
      final data = await CustomerApi.postDecoded('booking.php', {
        'action': 'listByCustomer',
        'userID': userId,
      });
      return (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _firstUpcomingFromAppointments(
    List<Map<String, dynamic>> items,
  ) {
    for (final appt in items) {
      final status = appt['status']?.toString() ?? '';
      if (status == 'Completed' ||
          status == 'Cancelled' ||
          status == 'NoShow') {
        continue;
      }
      final services = (appt['services'] as List<dynamic>? ?? []);
      final firstService = services.isNotEmpty
          ? Map<String, dynamic>.from(services.first as Map)
          : <String, dynamic>{};
      final isGroup = appt['isGroup'] == true;
      final displayTitle = isGroup
          ? (appt['displayTitle']?.toString() ??
              firstService['hairstyleName']?.toString() ??
              'Group booking')
          : (firstService['hairstyleName']?.toString() ??
              firstService['serviceName']?.toString() ??
              'Haircut');
      final timeRangeRaw = appt['timeRange']?.toString() ?? '';
      final timeRange = timeRangeRaw.isNotEmpty
          ? formatTimeRangeTo12h(timeRangeRaw)
          : formatTo12Hour(appt['startTime']?.toString() ?? '');
      return {
        'appointmentId': appt['appointmentID'],
        'service': displayTitle,
        'barber': appt['barberName']?.toString() ?? 'Barber',
        'date': appt['appointmentDate']?.toString() ?? '',
        'time': timeRange,
        'status': status,
      };
    }
    return null;
  }

  bool _hasActiveFromAppointments(List<Map<String, dynamic>> items) {
    for (final appt in items) {
      if (BookingGuard.isActiveStatus(appt['status']?.toString() ?? '')) {
        return true;
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> _fetchQuickBookProfile(int userId) async {
    try {
      final profileData = await CustomerApi.postDecoded('booking.php', {
        'action': 'getQuickBookProfile',
        'userID': userId,
      });
      return profileData['profile'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<
      ({
        Map<String, dynamic>? favoriteBarber,
        Map<String, dynamic>? recentHaircut,
        Map<String, dynamic>? trendingHaircut,
      })> _fetchPersonalInsights(int userId) async {
    late final Map<String, dynamic> insights;
    try {
      insights = await CustomerApi.postDecoded('booking.php', {
        'action': 'getCustomerHomeInsights',
        'userID': userId,
      });
    } catch (_) {
      return (
        favoriteBarber: null,
        recentHaircut: null,
        trendingHaircut: null,
      );
    }
    return (
      favoriteBarber: insights['favoriteBarber'] is Map
          ? Map<String, dynamic>.from(insights['favoriteBarber'] as Map)
          : null,
      recentHaircut: insights['recentHaircut'] is Map
          ? Map<String, dynamic>.from(insights['recentHaircut'] as Map)
          : null,
      trendingHaircut: insights['trendingHaircut'] is Map
          ? Map<String, dynamic>.from(insights['trendingHaircut'] as Map)
          : null,
    );
  }

  Future<void> _applyPersonalInsights(
    int token,
    Future<
            ({
              Map<String, dynamic>? favoriteBarber,
              Map<String, dynamic>? recentHaircut,
              Map<String, dynamic>? trendingHaircut,
            })>
        personalFuture,
  ) async {
    try {
      final personal = await personalFuture;
      if (!mounted || token != _homeLoadToken) return;
      setState(() {
        _favoriteBarber = personal.favoriteBarber;
        _recentHaircut = personal.recentHaircut;
        _trendingHaircut = personal.trendingHaircut;
        _loadingPersonalInsights = false;
        _personalInsightsResolved = true;
      });
    } catch (_) {
      if (!mounted || token != _homeLoadToken) return;
      setState(() {
        _loadingPersonalInsights = false;
        _personalInsightsResolved = true;
      });
    }
  }

  bool get _suggestionStillFresh {
    final fetchedAt = _suggestionFetchedAt;
    if (_slotSuggestion == null || fetchedAt == null) return false;
    return DateTime.now().difference(fetchedAt) < _suggestionTtl;
  }

  Future<void> _loadSuggestionInBackground(int userId, int token) async {
    if (_suggestionStillFresh) {
      return;
    }

    Map<String, dynamic>? suggestion;
    List<Map<String, dynamic>> alternatives = const [];
    try {
      final slotResult = await BookingSlotsService.fetchBestSuggestion(
        timeout: BookingSlotsService.dashboardTimeout,
      );
      if (slotResult.isSuccess) {
        suggestion = slotResult.suggestion;
        alternatives = slotResult.alternatives;
      }
    } catch (_) {}

    if (!mounted || token != _homeLoadToken) return;
    if (_hasActiveAppointment) {
      setState(() {
        _slotSuggestion = null;
        _slotAlternatives = const [];
        _quickBookProfile = null;
      });
      return;
    }

    if (suggestion == null) return;
    final slotDate = suggestion['slotDate']?.toString() ?? '';
    final slotTime = suggestion['slotTime']?.toString() ?? '';
    if (slotDate.isEmpty ||
        slotTime.isEmpty ||
        isPastOrInvalidSuggestion(date: slotDate, time: slotTime)) {
      return;
    }
    setState(() {
      _slotSuggestion = suggestion;
      _slotAlternatives = alternatives;
      _suggestionFetchedAt = DateTime.now();
    });
  }

  Future<void> _loadHomeInsights() async {
    final userId = UserSession.userId;
    if (userId == null || userId <= 0) {
      if (!mounted) return;
      setState(() {
        _nextUpcomingAppointment = null;
        _slotSuggestion = null;
        _slotAlternatives = const [];
        _quickBookProfile = null;
        _bookingDraft = null;
        _hasActiveAppointment = false;
        _favoriteBarber = null;
        _recentHaircut = null;
        _trendingHaircut = null;
        _loadingPersonalInsights = false;
        _personalInsightsResolved = true;
        _suggestionFetchedAt = null;
      });
      return;
    }

    final token = ++_homeLoadToken;
    final showPersonalSkeleton = !_personalInsightsResolved;
    if (mounted && showPersonalSkeleton) {
      setState(() => _loadingPersonalInsights = true);
    }

    // Fire independent home requests together.
    final personalFuture = _fetchPersonalInsights(userId);
    final appointmentsFuture = _fetchCustomerAppointments(userId);
    final quickBookFuture = _fetchQuickBookProfile(userId);
    unawaited(_applyPersonalInsights(token, personalFuture));

    Map<String, dynamic>? upcoming;
    var hasActive = false;
    Map<String, dynamic>? quickProfile;

    try {
      final results = await Future.wait<Object?>([
        appointmentsFuture,
        quickBookFuture,
      ]);
      if (!mounted || token != _homeLoadToken) return;

      final items = results[0] as List<Map<String, dynamic>>;
      quickProfile = results[1] as Map<String, dynamic>?;
      hasActive = _hasActiveFromAppointments(items);
      upcoming = _firstUpcomingFromAppointments(items);
    } catch (_) {
      // Appointment / quick-book failed independently.
    }

    BookingDraft? draft;
    if (!hasActive) {
      try {
        draft = await BookingDraftService.load();
        if (draft == null &&
            UserSession.selectedVariantId != null &&
            UserSession.selectedVariantId! > 0) {
          draft = BookingDraft(
            variantId: UserSession.selectedVariantId!,
            styleName: UserSession.selectedStyleName,
            serviceId: UserSession.selectedServiceId,
            estimatedMinutes: UserSession.selectedEstimatedMinutes,
            step: 'barber',
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (_) {}
    }

    if (!mounted || token != _homeLoadToken) return;
    setState(() {
      _nextUpcomingAppointment = upcoming;
      _hasActiveAppointment = hasActive;
      _bookingDraft = draft;
      if (hasActive) {
        _slotSuggestion = null;
        _slotAlternatives = const [];
        _quickBookProfile = null;
        _suggestionFetchedAt = null;
      } else {
        _quickBookProfile = quickProfile;
      }
    });

    // Optional next-slot teaser: short timeout, no skeleton, in-memory TTL.
    if (!hasActive) {
      unawaited(_loadSuggestionInBackground(userId, token));
    }
  }

  Future<void> _resolveHairTexture() async {
    var texture = await UserSession.loadPreferredHairTexture();
    final userId = UserSession.userId;
    if (userId != null && userId > 0) {
      try {
        final data = await CustomerApi.postDecoded('profile.php', {
          'action': 'get',
          'userID': userId,
        });
        final profile = data['profile'] as Map<String, dynamic>?;
        final fromDb = profile?['hairTexture']?.toString().trim() ?? '';
        if (fromDb.isNotEmpty) {
          texture = fromDb;
          await UserSession.savePreferredHairTexture(fromDb);
        }
      } catch (_) {
        // Keep local preference when profile fetch fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _needsHairTextureOnboarding = texture == null || texture.isEmpty;
    });
  }

  bool get _hasActiveScanSession {
    final captures = UserSession.capturedFaceImages;
    return captures != null && captures.isNotEmpty;
  }

  void _openFaceScan({bool startFresh = false}) {
    if (startFresh) {
      UserSession.beginNewScanWorkingState();
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => AiFaceScanPage(startFresh: startFresh),
          ),
        )
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openLastScanResults() {
    if (!UserSession.restoreCompletedScan()) {
      final liveCaptures = UserSession.capturedFaceImages;
      final liveScan = UserSession.lastScan;
      if (liveCaptures == null || liveCaptures.isEmpty || liveScan == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No completed scan to view yet. Start a new scan first.'),
          ),
        );
        return;
      }
      UserSession.commitCompletedScan();
    }

    final captures = UserSession.capturedFaceImages;
    final scan = UserSession.lastScan ?? {};
    if (captures == null || captures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scan photos are unavailable. Please run a new scan.'),
        ),
      );
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => FaceScanResultsPage(
              captures: Map<String, String>.from(captures),
              faceShape: scan['faceShape']?.toString() ?? 'oval',
              hairTexture: UserSession.normalizeHairTextureLabel(
                scan['hairTexture']?.toString() ??
                    UserSession.preferredHairTexture,
              ),
              hairLengthLevel: int.tryParse('${scan['hairLengthLevel']}') ?? 1,
              hairLengthLabel: scan['hairLength']?.toString() ?? 'short',
              analysisProvider: scan['analysisProvider']?.toString(),
              hairTextureScore: (scan['hairTextureScore'] as num?)?.toDouble(),
              noHairDetected: scan['noHairDetected'] == true,
              hairColorLabel: scan['hairColor']?.toString(),
            ),
          ),
        )
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  bool get _canQuickBook {
    if (_hasActiveAppointment) return false;
    final profile = _quickBookProfile;
    if (profile == null || profile['eligible'] != true) return false;
    final variantId = int.tryParse('${profile['variantId'] ?? ''}') ?? 0;
    return variantId > 0 && _slotSuggestion != null;
  }

  Future<void> _handleQuickBook() async {
    if (!_canQuickBook) {
      if (_hasActiveAppointment) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active appointment.')),
        );
        await _openAppointments();
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    final profile = _quickBookProfile!;
    final suggestion = Map<String, dynamic>.from(_slotSuggestion!);
    final variantId = int.tryParse('${profile['variantId'] ?? ''}') ?? 0;
    if (variantId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved hairstyle found. Try a face scan first.')),
      );
      return;
    }

    final hasActive = await BookingGuard.hasActiveAppointment(userId: UserSession.userId);
    if (!mounted) return;
    if (hasActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      await _openAppointments();
      return;
    }

    UserSession.selectedVariantId = variantId;
    UserSession.selectedStyleName = profile['styleName']?.toString() ?? 'Haircut';
    final serviceId = int.tryParse('${profile['serviceId'] ?? ''}');
    if (serviceId != null && serviceId > 0) {
      UserSession.selectedServiceId = serviceId;
    }
    UserSession.selectedPreviewImages = null;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuggestedAppointmentPage(
          suggestion: suggestion,
          alternatives: _slotAlternatives,
          skipPreviews: true,
        ),
      ),
    );
    if (mounted) {
      await _loadHomeInsights();
    }
  }

  String _formatShortDate(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) {
      return isoDate;
    }
    final month = int.tryParse(parts[1]) ?? 0;
    final day = int.tryParse(parts[2]) ?? 0;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (month < 1 || month > 12 || day < 1) {
      return isoDate;
    }
    return '${months[month - 1]} $day';
  }

  bool _isSlotToday(String? slotDate) {
    if (slotDate == null || slotDate.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return slotDate == today || normalizeSqlDate(slotDate) == today;
  }

  String _slotTeaserLine(Map<String, dynamic> suggestion) {
    final slotDate = suggestion['slotDate']?.toString() ?? '';
    final slotTime = formatTo12Hour(suggestion['slotTime']?.toString() ?? '');
    final barberName = suggestion['barberName']?.toString() ?? 'a barber';
    if (_isSlotToday(slotDate)) {
      return 'Next slot today · $slotTime with $barberName';
    }
    return 'Next opening · ${_formatShortDate(slotDate)} · $slotTime';
  }

  Future<void> _continueBooking() async {
    final draft = _bookingDraft;
    if (draft == null || !draft.isValid) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    BookingDraftService.applyToSession(draft);

    if (draft.step == 'calendar' &&
        draft.barberId != null &&
        draft.barberId! > 0) {
      final barberName = draft.barberName ?? 'Barber';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupSizePage(
            barberId: draft.barberId!,
            barberName: barberName,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
    );
  }

  Widget _buildUpcomingStrip() {
    final appt = _nextUpcomingAppointment;
    if (appt == null) {
      return const SizedBox.shrink();
    }

    final service = appt['service']?.toString() ?? 'Appointment';
    final barber = appt['barber']?.toString() ?? '';
    final date = appt['date']?.toString() ?? '';
    final time = appt['time']?.toString() ?? '';
    final when = [
      if (date.isNotEmpty) _formatShortDate(date),
      if (time.isNotEmpty) time,
    ].join(' · ');

    return GestureDetector(
      onTap: _openAppointments,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF141A24), Color(0xFF11131A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppBrand.accentLine, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available, color: AppBrand.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upcoming appointment',
                    style: TextStyle(
                      color: AppBrand.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (barber.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'with $barber',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                  if (when.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      when,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueBookingCard() {
    if (_hasActiveAppointment) {
      return const SizedBox.shrink();
    }
    final draft = _bookingDraft;
    if (draft == null || !draft.isValid) {
      return const SizedBox.shrink();
    }

    final styleName = draft.styleName?.trim();
    final title = styleName != null && styleName.isNotEmpty
        ? 'Continue booking · $styleName'
        : 'Continue booking';
    final subtitle = draft.step == 'calendar'
        ? 'Pick date & time with ${draft.barberName ?? 'your barber'}'
        : 'Choose a barber and time slot';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.borderStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _continueBooking,
            child: const Text(
              'Continue',
              style: TextStyle(color: AppBrand.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickBookCard() {
    if (!_canQuickBook) {
      return const SizedBox.shrink();
    }

    final styleName = _quickBookProfile?['styleName']?.toString() ?? 'your usual style';
    final suggestion = _slotSuggestion!;
    final line = _slotTeaserLine(suggestion);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11131A), Color(0xFF161E2B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.accentLine),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _handleQuickBook,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.flash_on, color: AppBrand.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Book your next slot',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$styleName · $line',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityTeaser() {
    // Hide entirely when the customer already has something booked.
    if (_hasActiveAppointment || _nextUpcomingAppointment != null) {
      return const SizedBox.shrink();
    }

    // When quick-book is available, the gold "Book your next slot" card already
    // shows the same suggestion and action — skip this duplicate teaser.
    if (_canQuickBook) {
      return const SizedBox.shrink();
    }

    // Optional teaser: never show a loading skeleton — suggestBestSlot can be slow
    // (slot seeding). Appear only when a suggestion is already available.
    final suggestion = _slotSuggestion;
    if (suggestion == null) {
      return const SizedBox.shrink();
    }

    // Informational only: next open slot when the user can't one-tap quick book yet.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.white70, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Barber availability',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _slotTeaserLine(suggestion),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return SizedBox(
      width: double.infinity,
      child: _QuickActionTile(
        icon: Icons.folder_open_outlined,
        label: 'Library',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HaircutsListPage()),
          );
        },
      ),
    );
  }

  Widget _buildScanSessionCard() {
    final scan = UserSession.completedScanSummary ?? UserSession.lastScan;
    final hasScanSummary = scan != null &&
        ((scan['hairTexture']?.toString().trim().isNotEmpty ?? false) ||
            (scan['faceShape']?.toString().trim().isNotEmpty ?? false));
    final hasScan = UserSession.hasCompletedScanResults ||
        UserSession.hasRecentRecommendations ||
        _hasActiveScanSession ||
        hasScanSummary;

    if (!hasScan) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppBrand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppBrand.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Session',
              style: TextStyle(
                fontFamily: _fontFamily,
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No scan results yet.',
              style: TextStyle(
                fontFamily: _fontFamily,
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try our AI Face Scan for personalized recommendations!',
              style: TextStyle(
                fontFamily: _fontFamily,
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _openFaceScan(startFresh: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppBrand.borderStrong),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: const Text(
                  'Start Scanning',
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final face = scan?['faceShape']?.toString() ?? '—';
    final texture = scan?['hairTexture']?.toString() ??
        UserSession.preferredHairTexture ??
        '—';
    final length = scan?['hairLength']?.toString() ?? '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Scan Session',
            style: TextStyle(
              fontFamily: _fontFamily,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ScanChip(label: 'Face: $face'),
              _ScanChip(label: 'Hair: $texture'),
              if (length != '—') _ScanChip(label: 'Length: $length'),
            ],
          ),
          ..._buildTopPicksPreview(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _openLastScanResults,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppBrand.borderStrong),
                  ),
                  child: const Text(
                    'View results',
                    style: TextStyle(fontFamily: _fontFamily),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _openFaceScan(startFresh: true),
                  style: AppBrand.primaryButton.copyWith(
                    minimumSize:
                        const WidgetStatePropertyAll(Size.fromHeight(44)),
                  ),
                  child: const Text(
                    'New scan',
                    style: TextStyle(
                      fontFamily: _fontFamily,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Top 3 ranked styles from the last scan, shown inline so the customer does
  /// not have to open the results page to remember what was recommended.
  ///
  /// Reads [UserSession.lastRecommendations], which the results page already
  /// persists into the session snapshot, so this needs no network call. Returns
  /// an empty list (rendering nothing) when a scan exists but its ranking does
  /// not -- a restored snapshot, or a scan whose rerank never completed.
  List<Widget> _buildTopPicksPreview() {
    final picks = UserSession.lastRecommendations.take(3).toList();
    if (picks.isEmpty) return const [];

    return [
      const SizedBox(height: 14),
      const Text(
        'Top picks for you',
        style: TextStyle(
          fontFamily: _fontFamily,
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      const SizedBox(height: 8),
      for (final pick in picks) _buildTopPickRow(pick),
    ];
  }

  Widget _buildTopPickRow(Map<String, dynamic> pick) {
    // Same accessors the results page uses, so the two stay in agreement if the
    // recommendation payload shape changes.
    final name = pick['style_name']?.toString() ??
        pick['styleName']?.toString() ??
        'Style';
    final subtitle = (pick['fit_reason']?.toString().trim().isNotEmpty ?? false)
        ? pick['fit_reason'].toString().trim()
        : pick['description']?.toString().trim() ?? '';
    final rankLabel = RecommendationMatchDisplay.rankLabel(pick);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _openLastScanResults,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: _fontFamily,
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (rankLabel != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              rankLabel,
                              style: const TextStyle(
                                fontFamily: _fontFamily,
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _fontFamily,
                            color: Colors.white54,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bookWithFavoriteBarber() async {
    final barber = _favoriteBarber;
    if (barber == null) return;
    final barberId = int.tryParse('${barber['barberId']}') ?? 0;
    final barberName = barber['fullName']?.toString() ?? 'Barber';
    if (barberId <= 0) return;

    if (_hasActiveAppointment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      await _openAppointments();
      return;
    }

    await BookingDraftService.saveFromSession(
      step: 'calendar',
      barberId: barberId,
      barberName: barberName,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupSizePage(
          barberId: barberId,
          barberName: barberName,
        ),
      ),
    );
  }

  Future<void> _bookAgainRecentHaircut() async {
    final recent = _recentHaircut;
    if (recent == null) return;

    if (_hasActiveAppointment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      await _openAppointments();
      return;
    }

    final variantId = int.tryParse('${recent['variantId']}') ?? 0;
    final serviceId = int.tryParse('${recent['serviceId']}') ?? 0;
    final styleName = recent['styleName']?.toString() ?? 'Haircut';
    if (variantId > 0) {
      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = styleName;
    }
    if (serviceId > 0) {
      UserSession.selectedServiceId = serviceId;
    }

    final barberId = int.tryParse('${recent['barberId']}') ?? 0;
    final barberName = recent['barberName']?.toString() ?? 'Barber';
    if (barberId > 0) {
      await BookingDraftService.saveFromSession(
        step: 'calendar',
        barberId: barberId,
        barberName: barberName,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupSizePage(
            barberId: barberId,
            barberName: barberName,
          ),
        ),
      );
      return;
    }

    await BookingDraftService.saveFromSession(step: 'barber');
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
    );
  }

  Future<void> _bookTrendingHaircut() async {
    final trend = _trendingHaircut;
    if (trend == null) return;

    if (_hasActiveAppointment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      await _openAppointments();
      return;
    }

    final variantId = int.tryParse('${trend['variantId']}') ?? 0;
    final serviceId = int.tryParse('${trend['serviceId']}') ?? 0;
    final styleName = trend['styleName']?.toString() ?? 'Haircut';
    if (variantId > 0) {
      UserSession.selectedVariantId = variantId;
      UserSession.selectedStyleName = styleName;
    }
    if (serviceId > 0) {
      UserSession.selectedServiceId = serviceId;
    }

    await BookingDraftService.saveFromSession(step: 'barber');
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
    );
  }

  Widget _buildPersonalizedSection() {
    final showSkeleton = _loadingPersonalInsights && !_personalInsightsResolved;

    if (showSkeleton) {
      return const AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For you',
              style: TextStyle(
                fontFamily: _fontFamily,
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 10),
            _InsightCardSkeleton(),
            SizedBox(height: 10),
            _InsightCardSkeleton(),
            SizedBox(height: 10),
            _InsightCardSkeleton(),
          ],
        ),
      );
    }

    final cards = <Widget>[];

    if (_favoriteBarber != null) {
      final barber = _favoriteBarber!;
      final rating = barber['avgRating'];
      final ratingText = rating is num
          ? rating.toStringAsFixed(1)
          : (double.tryParse('$rating')?.toStringAsFixed(1) ?? '—');
      final source = barber['source']?.toString() == 'customer_ratings'
          ? 'From your ratings'
          : 'Most booked by you';
      cards.add(
        _InsightCard(
          eyebrow: 'Favorite barber',
          title: barber['fullName']?.toString() ?? 'Barber',
          subtitle: '$source · $ratingText★',
          icon: Icons.star_rounded,
          accent: AppBrand.accent,
          onAction: _bookWithFavoriteBarber,
        ),
      );
    }

    if (_recentHaircut != null) {
      final recent = _recentHaircut!;
      final date = recent['appointmentDate']?.toString() ?? '';
      final barberName = recent['barberName']?.toString() ?? 'Barber';
      cards.add(
        _InsightCard(
          eyebrow: 'Recent haircut',
          title: recent['styleName']?.toString() ?? 'Haircut',
          subtitle: date.isNotEmpty ? 'With $barberName · $date' : 'With $barberName',
          icon: Icons.content_cut,
          accent: Colors.white70,
          onAction: _bookAgainRecentHaircut,
        ),
      );
    }

    if (_trendingHaircut != null) {
      final trend = _trendingHaircut!;
      final count = int.tryParse('${trend['bookingCount']}') ?? 0;
      cards.add(
        _InsightCard(
          eyebrow: 'Trending haircut',
          title: trend['styleName']?.toString() ?? 'Haircut',
          subtitle: count > 0
              ? 'Booked $count times in the last 90 days'
              : 'Popular with customers right now',
          icon: Icons.local_fire_department_outlined,
          accent: AppBrand.warning,
          onAction: _bookTrendingHaircut,
        ),
      );
    }

    if (cards.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppBrand.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppBrand.border),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'After a few bookings and ratings, your favorite barber, recent cut, and trending styles will show up here.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'For you',
          style: TextStyle(
            fontFamily: _fontFamily,
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...cards.map(
          (card) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: card,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppTopBar(
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppBrand.s2),

            // Greeting masthead — the dashboard's one brand moment.
            if (_showWelcome) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const BrandMark(size: 52),
                  const SizedBox(width: AppBrand.s4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _greeting(),
                          style: const TextStyle(
                            fontFamily: _fontFamily,
                            color: AppBrand.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          UserSession.fullName ?? 'Welcome',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _fontFamily,
                            color: AppBrand.chalk,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.2,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppBrand.s6),
            ],

            _buildUpcomingStrip(),
            _buildContinueBookingCard(),
            _buildQuickBookCard(),
            _buildAvailabilityTeaser(),
            _buildQuickActions(),
            const SizedBox(height: 14),
            _buildScanSessionCard(),
            const SizedBox(height: 14),
            _buildPersonalizedSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
          if (_needsHairTextureOnboarding)
            HairTextureOnboarding(
              onCompleted: () async {
                setState(() {
                  _needsHairTextureOnboarding = false;
                });
                await _loadHomeInsights();
              },
            ),
        ],
      ),
      floatingActionButton: const AiChatbotFab(
        heroTag: 'dashboard_ai_chat_fab',
        bottomPadding: 0,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            // already on Home
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

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppBrand.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppBrand.borderStrong),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: _DashboardPageState._fontFamily,
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onAction;

  const _InsightCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontFamily: _DashboardPageState._fontFamily,
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: _DashboardPageState._fontFamily,
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: _DashboardPageState._fontFamily,
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppBrand.borderStrong),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white70,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanChip extends StatelessWidget {
  final String label;

  const _ScanChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppBrand.borderStrong),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: _DashboardPageState._fontFamily,
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InsightCardSkeleton extends StatelessWidget {
  const _InsightCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.border),
      ),
      child: const Row(
        children: [
          AppShimmerBox(width: 40, height: 40, borderRadius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmerBox(width: 88, height: 10, borderRadius: 4),
                SizedBox(height: 8),
                AppShimmerBox(width: 140, height: 14, borderRadius: 4),
                SizedBox(height: 8),
                AppShimmerBox(width: 180, height: 11, borderRadius: 4),
              ],
            ),
          ),
          SizedBox(width: 8),
          AppShimmerBox(width: 40, height: 40, borderRadius: 10),
        ],
      ),
    );
  }
}
