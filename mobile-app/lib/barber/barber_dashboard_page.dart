import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/app_brand.dart';
import '../user/api_config.dart';
import '../user/time_format_utils.dart';
import '../user/widgets/app_top_bar.dart';
import '../user/widgets/menu_sheet.dart';
import '../user/user_session.dart';
import '../user/widgets/pill_tabs.dart';
import 'barber_appointment_detail_page.dart';
import 'barber_profile_page.dart';
import 'barber_calendar_page.dart';

class BarberDashboardPage extends StatefulWidget {
  const BarberDashboardPage({super.key});

  @override
  State<BarberDashboardPage> createState() => _BarberDashboardPageState();
}

class _BarberDashboardPageState extends State<BarberDashboardPage> {
  static const int _tabDashboard = 0;
  static const int _tabCalendar = 1;
  static const int _tabProfile = 2;
  static const int _tabMenu = 3;

  // Same three states the customer's Bookings page uses, through the same
  // control -- the two screens had drifted into different shapes for one job.
  static const List<String> _appointmentTabs = ['Upcoming', 'Completed', 'Cancelled'];

  int _currentTab = _tabDashboard;
  int _appointmentTab = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appointments = [];
  // Walk-ins were invisible here: a barber could see who had booked but not
  // who the kiosk had queued to them, nor what those guests picked.
  List<Map<String, dynamic>> _walkins = [];
  bool _showingWalkins = false;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadAppointments() async {
    final barberId = UserSession.userId;
    if (barberId == null || barberId <= 0) {
      setState(() {
        _loading = false;
        _error = 'Invalid barber session. Please log in again.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listByBarber',
          'barberID': barberId,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load barber appointments.';
          _loading = false;
        });
        return;
      }

      final items = (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _appointments = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load barber appointments: $e';
        _loading = false;
      });
    }
  }

  /// Both lists come from different endpoints but are one day's work, so they
  /// are loaded together and the toggle never waits on a second request.
  Future<void> _loadToday() async {
    await Future.wait([_loadAppointments(), _loadWalkins(), _loadBarberName()]);
  }

  /// Reads the barber's name from `barbers`, where it actually lives.
  ///
  /// Sign-in resolves the display name from Supabase user metadata, which
  /// barber accounts do not carry -- so it fell through to the email and the
  /// dashboard greeted them with "barber@tatis.local". The name is in the
  /// barbers table and this screen already talks to that endpoint.
  Future<void> _loadBarberName() async {
    final barberId = UserSession.userId;
    final email = UserSession.email ?? '';
    if ((barberId == null || barberId <= 0) && email.isEmpty) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'detail',
          'barberID': barberId ?? 0,
          'email': email,
        }),
      );
      if (!mounted || response.statusCode != 200) return;

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      final name = (data['barber'] as Map?)?['full_name']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        setState(() => UserSession.fullName = name);
      }
    } catch (_) {
      // The greeting falls back to a plain "Welcome"; not worth an error.
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 18) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }

  Future<void> _loadWalkins() async {
    final barberId = UserSession.userId;
    if (barberId == null || barberId <= 0) return;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listWalkinsByBarber',
          'barberID': barberId,
          'email': UserSession.email ?? '',
        }),
      );
      if (!mounted || response.statusCode != 200) return;

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      setState(() {
        _walkins = (data['walkins'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } catch (_) {
      // The appointments list is the critical half; a walk-in fetch that fails
      // should leave the barber's day on screen rather than blanking it.
    }
  }

  Widget _buildWorkToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: false,
            label: Text('Appointments (${_appointments.length})'),
          ),
          ButtonSegment(
            value: true,
            label: Text('Walk-ins (${_walkins.length})'),
          ),
        ],
        selected: {_showingWalkins},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() => _showingWalkins = selection.first);
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? AppBrand.gold : AppBrand.surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? Colors.black : AppBrand.textMuted),
          side: const WidgetStatePropertyAll(BorderSide(color: AppBrand.border)),
        ),
      ),
    );
  }

  List<Widget> _buildWalkinSection(BuildContext context) {
    if (_walkins.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              'No walk-ins queued to you today.',
              style: TextStyle(color: AppBrand.textMuted),
            ),
          ),
        ),
      ];
    }

    return _walkins.map(_walkinCard).toList();
  }

  Widget _walkinCard(Map<String, dynamic> walkin) {
    final status = walkin['status']?.toString() ?? '';
    final style = walkin['style']?.toString() ?? '';
    final notes = walkin['notes']?.toString() ?? '';
    final entryPath = walkin['entryPath']?.toString() ?? '';
    final claimCode = walkin['claimCode']?.toString() ?? '';
    final paymentMode = walkin['paymentMode']?.toString() ?? 'counter';
    final price = (walkin['price'] as num?)?.toDouble() ?? 0;
    final people = (walkin['peopleCount'] as num?)?.toInt() ?? 1;
    final waitMinutes = (walkin['waitMinutes'] as num?)?.toInt() ?? 0;
    final paused = walkin['paused'] == true;
    final previews = (walkin['previews'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((preview) => (preview['front']?.toString() ?? '').isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                walkin['queueNumber']?.toString() ?? '',
                style: const TextStyle(
                  color: AppBrand.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  walkin['guestName']?.toString() ?? 'Guest',
                  style: const TextStyle(
                    color: AppBrand.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _walkinStatusChip(paused ? 'Paused' : status),
            ],
          ),
          const SizedBox(height: 8),
          // What the guest picked at the kiosk. Calling "Mark, for the fade"
          // is how the right Mark stands up when three share the name.
          Text(
            [
              walkin['service']?.toString() ?? '',
              if (style.isNotEmpty) style,
              if (people > 1) '$people people',
            ].where((part) => part.isNotEmpty).join(' · '),
            style: const TextStyle(color: AppBrand.text, fontSize: 14, height: 1.4),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Asked for: $notes',
              style: const TextStyle(color: AppBrand.gold, fontSize: 13, height: 1.4),
            ),
          ],
          if (previews.isNotEmpty) ...[
            const SizedBox(height: 12),
            // What the guest was actually shown. A description of a fade is
            // open to interpretation; the picture they agreed to is not.
            const Text(
              'AI preview the guest generated',
              style: TextStyle(color: AppBrand.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: previews.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _previewThumb(context, previews[index]),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              if (claimCode.isNotEmpty) _walkinMeta('Code', claimCode),
              _walkinMeta('Pay', paymentMode == 'gcash' ? 'Paid by GCash' : 'At the counter'),
              if (price > 0) _walkinMeta('Price', '₱${price.toStringAsFixed(2)}'),
              if (status != 'InProgress' && waitMinutes > 0) _walkinMeta('Waited', '$waitMinutes min'),
              if (entryPath.isNotEmpty) _walkinMeta('Came via', entryPath),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewThumb(BuildContext context, Map<String, dynamic> preview) {
    final front = ApiConfig.resolveImageUrl(preview['front']?.toString() ?? '');
    final styleName = preview['styleName']?.toString() ?? '';

    return GestureDetector(
      onTap: () => _openPreview(context, preview),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              front,
              width: 96,
              height: styleName.isEmpty ? 120 : 96,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 96,
                height: styleName.isEmpty ? 120 : 96,
                color: AppBrand.panel,
                child: const Icon(Icons.image_not_supported_outlined, color: AppBrand.textMuted),
              ),
            ),
          ),
          if (styleName.isNotEmpty) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: 96,
              child: Text(
                styleName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppBrand.textMuted, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Front, left and right at a size the barber can actually work from.
  void _openPreview(BuildContext context, Map<String, dynamic> preview) {
    final views = <String, String>{
      'Front': preview['front']?.toString() ?? '',
      'Left': preview['left']?.toString() ?? '',
      'Right': preview['right']?.toString() ?? '',
    }..removeWhere((_, url) => url.isEmpty);
    if (views.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AppBrand.surface,
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview['styleName']?.toString().isNotEmpty == true
                    ? preview['styleName'].toString()
                    : 'AI preview',
                style: const TextStyle(
                  color: AppBrand.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: views.entries
                        .map((entry) => Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      ApiConfig.resolveImageUrl(entry.value),
                                      width: 220,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 220,
                                        height: 260,
                                        color: AppBrand.panel,
                                        child: const Icon(
                                          Icons.image_not_supported_outlined,
                                          color: AppBrand.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.key,
                                    style: const TextStyle(color: AppBrand.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _walkinMeta(String label, String value) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(color: AppBrand.textMuted, fontSize: 12),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppBrand.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _walkinStatusChip(String status) {
    final readable = status.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppBrand.goldTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppBrand.goldLine),
      ),
      child: Text(
        readable,
        style: const TextStyle(color: AppBrand.gold, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppTopBar(
        onProfileTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BarberProfilePage()),
          );
        },
      ),
      body: RefreshIndicator(
        color: AppBrand.gold,
        backgroundColor: AppBrand.surface,
        onRefresh: _loadToday,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            // Same greeting block as the customer dashboard: brand mark, the
            // time of day, then the name. It no longer vanishes on a timer --
            // a greeting that disappears while you are reading it is worse
            // than one that stays.
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
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              _buildWorkToggle(),
              if (_showingWalkins)
                ..._buildWalkinSection(context)
              else
                ..._buildCategorizedSections(context),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppBrand.surface,
        selectedItemColor: AppBrand.gold,
        unselectedItemColor: AppBrand.textMuted,
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentTab.clamp(0, 3),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        onTap: (index) async {
          if (index == _tabDashboard) {
            setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabCalendar) {
            setState(() => _currentTab = _tabCalendar);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BarberCalendarPage()),
            );
            if (mounted) setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabProfile) {
            setState(() => _currentTab = _tabProfile);
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BarberProfilePage()),
            );
            if (mounted) setState(() => _currentTab = _tabDashboard);
            return;
          }
          if (index == _tabMenu) {
            setState(() => _currentTab = _tabMenu);
            await showAppMenuSheet(context);
            if (mounted) setState(() => _currentTab = _tabDashboard);
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.event_available),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'Menu',
          ),
        ],
      ),
    ),
    );
  }

  /// Appointments under the same three tabs the customer's Bookings page uses.
  ///
  /// This screen used to show "Upcoming" as a heading with Completed,
  /// Cancelled and NoShow tucked into collapsible folders -- a different shape
  /// for the same job, which made one product look like two. Cancelled and
  /// NoShow share a tab because to a barber they are the same outcome: the
  /// chair stayed empty.
  List<Widget> _buildCategorizedSections(BuildContext context) {
    const upcomingStatuses = ['Scheduled', 'CheckedIn', 'InProgress', 'PendingPayment'];
    const completedStatuses = ['Completed'];
    const cancelledStatuses = ['Cancelled', 'NoShow'];

    final wanted = switch (_appointmentTab) {
      1 => completedStatuses,
      2 => cancelledStatuses,
      _ => upcomingStatuses,
    };

    final rows = _appointments.where((appt) {
      final status = (appt['status']?.toString() ?? '').trim();
      if (wanted.contains(status)) return true;
      // An unrecognised status is still somebody's booking, so it shows under
      // Upcoming rather than disappearing between the tabs.
      return _appointmentTab == 0 &&
          !completedStatuses.contains(status) &&
          !cancelledStatuses.contains(status);
    }).toList();

    final widgets = <Widget>[
      PillTabs(
        labels: _appointmentTabs,
        selectedIndex: _appointmentTab,
        onSelected: (index) => setState(() => _appointmentTab = index),
      ),
      const SizedBox(height: 18),
    ];

    if (rows.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              switch (_appointmentTab) {
                1 => 'No completed appointments yet.',
                2 => 'Nothing cancelled. Good day.',
                _ => 'No appointments assigned yet.',
              },
              style: const TextStyle(color: AppBrand.textMuted),
            ),
          ),
        ),
      );

      return widgets;
    }

    widgets.addAll(rows.map((appt) => _appointmentTile(context, appt)));

    return widgets;
  }

  Widget _appointmentTile(BuildContext context, Map<String, dynamic> appt) {
    final isGroup = appt['isGroup'] == true;
    final customerName = isGroup
        ? (appt['displayTitle']?.toString() ?? appt['customerName']?.toString() ?? 'Group booking')
        : (appt['customerName']?.toString() ?? 'Customer');
    final date = appt['appointmentDate']?.toString() ?? '';
    final timeRange = appt['timeRange']?.toString() ?? '';
    final startTime = formatTo12Hour(appt['startTime']?.toString() ?? '');
    final scheduleLabel = timeRange.isNotEmpty ? timeRange : startTime;
    final status = appt['status']?.toString() ?? 'Unknown';
    final peopleCount = (appt['peopleCount'] as num?)?.toInt() ?? 1;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BarberAppointmentDetailPage(appointment: appt),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppBrand.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customerName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      if (isGroup)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppBrand.goldTint,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppBrand.goldLine),
                          ),
                          child: Text(
                            'Group · $peopleCount',
                            style: const TextStyle(color: AppBrand.gold, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$date  $scheduleLabel',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: $status',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}
