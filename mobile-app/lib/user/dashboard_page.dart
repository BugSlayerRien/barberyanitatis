import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'profile_page.dart';
import 'saved_haircuts_page.dart';
import 'haircuts_list_page.dart';
import 'widgets/ai_chatbot_fab.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'api_config.dart';
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

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver, RouteAware {
  int _selectedIndex = 0; // Home tab

  bool _showWelcome = true;
  Timer? _welcomeTimer;

  bool _needsHairTextureOnboarding = false;
  String? _userHairTexture;
  bool _isRouteSubscribed = false;

  Map<String, dynamic>? _nextUpcomingAppointment;
  Map<String, dynamic>? _slotSuggestion;
  Map<String, dynamic>? _quickBookProfile;
  BookingDraft? _bookingDraft;
  bool _loadingHomeInsights = false;
  bool _hasActiveAppointment = false;
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
    await _resolveHairTexture();
    if (mounted && !_needsHairTextureOnboarding) {
      await _loadHomeInsights();
    }
  }

  Future<void> _openAppointments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppointmentsPage()),
    );
    if (mounted) {
      await _loadHomeInsights();
    }
  }

  Future<void> _loadHomeInsights() async {
    final userId = UserSession.userId;
    if (userId == null || userId <= 0) {
      if (!mounted) return;
      setState(() {
        _nextUpcomingAppointment = null;
        _slotSuggestion = null;
        _quickBookProfile = null;
        _bookingDraft = null;
        _hasActiveAppointment = false;
        _loadingHomeInsights = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _loadingHomeInsights = true);
    }

    Map<String, dynamic>? upcoming;
    Map<String, dynamic>? suggestion;
    Map<String, dynamic>? quickProfile;
    BookingDraft? draft;
    var hasActive = false;

    try {
      hasActive = await BookingGuard.hasActiveAppointment(userId: userId);
    } catch (_) {}

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

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listByCustomer',
          'userID': userId,
        }),
      );
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['appointments'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
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
          upcoming = {
            'appointmentId': appt['appointmentID'],
            'service': displayTitle,
            'barber': appt['barberName']?.toString() ?? 'Barber',
            'date': appt['appointmentDate']?.toString() ?? '',
            'time': timeRange,
            'status': status,
          };
          break;
        }
      }
    } catch (_) {}

    try {
      final profileResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getQuickBookProfile',
          'userID': userId,
        }),
      );
      if (profileResponse.statusCode == 200 && profileResponse.body.isNotEmpty) {
        final profileData = jsonDecode(profileResponse.body) as Map<String, dynamic>;
        quickProfile = profileData['profile'] as Map<String, dynamic>?;
      }
    } catch (_) {}

    final slotResult = await BookingSlotsService.fetchBestSuggestion();
    if (slotResult.isSuccess) {
      suggestion = slotResult.suggestion;
    }

    if (!mounted) return;
    setState(() {
      _nextUpcomingAppointment = upcoming;
      _slotSuggestion = suggestion;
      _quickBookProfile = quickProfile;
      _bookingDraft = draft;
      _hasActiveAppointment = hasActive;
      _loadingHomeInsights = false;
    });
  }

  Future<void> _resolveHairTexture() async {
    var texture = await UserSession.loadPreferredHairTexture();
    final userId = UserSession.userId;
    if (userId != null && userId > 0) {
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/profile.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'get', 'userID': userId}),
        );
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final profile = data['profile'] as Map<String, dynamic>?;
          final fromDb = profile?['hairTexture']?.toString().trim() ?? '';
          if (fromDb.isNotEmpty) {
            texture = fromDb;
            await UserSession.savePreferredHairTexture(fromDb);
          }
        }
      } catch (_) {
        // Keep local preference when profile fetch fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _userHairTexture = texture;
      _needsHairTextureOnboarding = texture == null || texture.isEmpty;
    });
  }

  bool get _hasActiveScanSession {
    final captures = UserSession.capturedFaceImages;
    return captures != null && captures.isNotEmpty;
  }

  void _openFaceScan() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
    );
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
    return slotDate == today;
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

  void _openLastScanResults() {
    final captures = UserSession.capturedFaceImages;
    if (captures == null || captures.isEmpty) {
      _openFaceScan();
      return;
    }
    final scan = UserSession.lastScan ?? {};
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaceScanResultsPage(
          captures: Map<String, String>.from(captures),
          faceShape: scan['faceShape']?.toString() ?? 'oval',
          hairTexture: scan['hairTexture']?.toString() ??
              _userHairTexture ??
              UserSession.preferredHairTexture ??
              'Straight',
          hairLengthLevel: int.tryParse('${scan['hairLengthLevel']}') ?? 1,
          hairLengthLabel: scan['hairLength']?.toString() ?? 'short',
          analysisProvider: scan['analysisProvider']?.toString(),
          hairTextureScore: (scan['hairTextureScore'] as num?)?.toDouble(),
          noHairDetected: scan['noHairDetected'] == true,
          hairColorLabel: scan['hairColor']?.toString(),
        ),
      ),
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
            colors: [Color(0xFF2A2418), Color(0xFF1A1A1A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFA99941), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available, color: Color(0xFFA99941), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upcoming appointment',
                    style: TextStyle(
                      color: Color(0xFFA99941),
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
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
          colors: [Color(0xFF1E1A10), Color(0xFF2A2412)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA99941)),
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
                const Icon(Icons.flash_on, color: Color(0xFFA99941), size: 28),
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
    if (_loadingHomeInsights && _slotSuggestion == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
            SizedBox(width: 12),
            Text(
              'Checking barber availability…',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final suggestion = _slotSuggestion;
    if (suggestion == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _canQuickBook ? _handleQuickBook : null,
        child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.white70, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _canQuickBook ? 'Tap to quick book' : 'Barber availability',
                  style: const TextStyle(
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
          if (_canQuickBook)
            const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.face_retouching_natural,
            label: 'Face scan',
            onTap: _openFaceScan,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.calendar_month_outlined,
            label: 'Book',
            onTap: _canQuickBook ? _handleQuickBook : _openAppointments,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.folder_open_outlined,
            label: 'Library',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HaircutsListPage()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScanStatusCard() {
    final scan = UserSession.lastScan;
    final hasScan = UserSession.hasRecentRecommendations || _hasActiveScanSession;

    if (!hasScan) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get personalized picks',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Run a 3-angle face scan for AI recommendations and try-on previews.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _openFaceScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Start face scan', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    }

    final face = scan?['faceShape']?.toString() ?? '—';
    final texture = scan?['hairTexture']?.toString() ?? _userHairTexture ?? '—';
    final length = scan?['hairLength']?.toString() ?? '—';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your last scan',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ScanChip(label: 'Face: $face'),
              _ScanChip(label: 'Hair: $texture'),
              if (length != '—') _ScanChip(label: 'Length: $length'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _openLastScanResults,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: const Text('View results'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _openFaceScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('New scan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
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
            const SizedBox(height: 12),
            
            // Welcome Card
            if (_showWelcome) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  UserSession.fullName != null ? 'Welcome ${UserSession.fullName}' : 'Welcome',
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            _buildUpcomingStrip(),
            _buildContinueBookingCard(),
            _buildQuickBookCard(),
            _buildAvailabilityTeaser(),
            _buildQuickActions(),
            const SizedBox(height: 14),
            _buildScanStatusCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
          if (_needsHairTextureOnboarding)
            HairTextureOnboarding(
              onCompleted: () async {
                setState(() {
                  _needsHairTextureOnboarding = false;
                  _userHairTexture = UserSession.preferredHairTexture;
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
      color: const Color(0xFF151515),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;

  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
      ],
    );
  }
}
