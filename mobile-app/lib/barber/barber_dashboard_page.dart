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

  int _currentTab = _tabDashboard;
  bool _loading = true;
  bool _showWelcomeBanner = true;
  String? _error;
  String? _expandedStatus;
  List<Map<String, dynamic>> _appointments = [];
  // Walk-ins were invisible here: a barber could see who had booked but not
  // who the kiosk had queued to them, nor what those guests picked.
  List<Map<String, dynamic>> _walkins = [];
  bool _showingWalkins = false;
  Timer? _welcomeTimer;

  @override
  void initState() {
    super.initState();
    _welcomeTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showWelcomeBanner = false);
    });
    _loadToday();
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
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
    await Future.wait([_loadAppointments(), _loadWalkins()]);
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
            if (_showWelcomeBanner) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppBrand.goldTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppBrand.goldLine),
                ),
                child: Text(
                  UserSession.fullName != null
                      ? 'Welcome, ${UserSession.fullName}'
                      : 'Welcome',
                  style: const TextStyle(
                    color: AppBrand.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
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

  List<Widget> _buildCategorizedSections(BuildContext context) {
    if (_appointments.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No appointments assigned yet.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ];
    }

    const upcomingStatuses = ['Scheduled', 'CheckedIn', 'InProgress'];
    const folderStatuses = ['Completed', 'Cancelled', 'NoShow'];

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final appt in _appointments) {
      final status = (appt['status']?.toString() ?? 'Unknown').trim();
      groups.putIfAbsent(status, () => []);
      groups[status]!.add(appt);
    }

    final widgets = <Widget>[];

    // Upcoming appointments are always visible (not tucked into folders).
    final upcoming = <Map<String, dynamic>>[];
    for (final status in upcomingStatuses) {
      upcoming.addAll(groups[status] ?? const []);
    }
    widgets.add(
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Text(
          'Upcoming appointments',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    if (upcoming.isEmpty) {
      widgets.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppBrand.border),
          ),
          child: const Text(
            'No scheduled appointments right now.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      );
    } else {
      widgets.addAll(upcoming.map((appt) => _appointmentTile(context, appt)));
      widgets.add(const SizedBox(height: 8));
    }

    // Completed / cancelled / no-show stay in collapsible folders.
    for (final status in folderStatuses) {
      final items = groups[status] ?? [];
      if (items.isEmpty) continue;
      final isExpanded = _expandedStatus == status;
      widgets.add(
        _statusHeader(
          status: status,
          count: items.length,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              _expandedStatus = isExpanded ? null : status;
            });
          },
        ),
      );
      if (isExpanded) {
        widgets.add(const SizedBox(height: 8));
        widgets.addAll(items.map((appt) => _appointmentTile(context, appt)));
      }
      widgets.add(const SizedBox(height: 14));
    }

    // Any unexpected status still appears as a folder so nothing is hidden.
    for (final status in groups.keys) {
      if (upcomingStatuses.contains(status) || folderStatuses.contains(status)) {
        continue;
      }
      final items = groups[status] ?? [];
      if (items.isEmpty) continue;
      final isExpanded = _expandedStatus == status;
      widgets.add(
        _statusHeader(
          status: status,
          count: items.length,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              _expandedStatus = isExpanded ? null : status;
            });
          },
        ),
      );
      if (isExpanded) {
        widgets.add(const SizedBox(height: 8));
        widgets.addAll(items.map((appt) => _appointmentTile(context, appt)));
      }
      widgets.add(const SizedBox(height: 14));
    }

    return widgets;
  }

  Widget _statusHeader({
    required String status,
    required int count,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppBrand.border),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.folder_open : Icons.folder,
              color: Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppBrand.border),
              ),
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white60,
            ),
          ],
        ),
      ),
    );
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
