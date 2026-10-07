import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:http/http.dart' as http;
import 'completed_appointment_detail.dart';
import 'profile_page.dart';
import 'customer_navigation.dart';
import 'dashboard_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'widgets/shimmer_skeleton.dart';
import 'api_config.dart';
import 'customer_api.dart';
import 'time_format_utils.dart';
import 'ph_phone.dart';
import 'user_session.dart';
import 'widgets/pill_tabs.dart';
import 'suggested_appointment_page.dart';
import 'barber_selection_page.dart';
import 'services/booking_slots_service.dart';
import 'payment_page.dart';
import 'calendar_page.dart';
import '../shared/pagination_controls.dart';
import '../main.dart';

/// True when an appointment's slot has already ended, so it no longer belongs
/// in the Upcoming tab regardless of the status the server still reports.
///
/// [date] is `YYYY-MM-DD` and [endTime] is `HH:MM[:SS]`, both in shop-local
/// terms. A missing or unparseable [endTime] falls back to the end of that
/// day, so a row with a blank end_time is only treated as past once the whole
/// day has gone by -- never mid-day, which would hide a valid appointment.
/// Unparseable or empty [date] returns false: keep showing it rather than
/// silently filing a booking away.
bool appointmentSlotHasPassed({
  String? date,
  String? endTime,
  DateTime? now,
}) {
  final rawDate = date?.trim() ?? '';
  if (rawDate.isEmpty) return false;

  final day = DateTime.tryParse(rawDate);
  if (day == null) return false;

  var slotEnd = DateTime(day.year, day.month, day.day, 23, 59, 59);
  final rawTime = endTime?.trim() ?? '';
  if (rawTime.isNotEmpty) {
    final parts = rawTime.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) : 0;
    // '00:00:00' is the codebase's "unset" end_time (see appointment_expiry.php),
    // not midnight, so it must not collapse the slot to the start of the day.
    if (hour != null && !(hour == 0 && (minute ?? 0) == 0)) {
      slotEnd = DateTime(day.year, day.month, day.day, hour, minute ?? 0);
    }
  }

  return slotEnd.isBefore(now ?? DateTime.now());
}

class AppointmentsPage extends StatefulWidget {
  final int? highlightAppointmentId;
  final String? forcedPaymentState;
  final String? forcedReceiptRef;

  const AppointmentsPage({
    super.key,
    this.highlightAppointmentId,
    this.forcedPaymentState,
    this.forcedReceiptRef,
  });

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage>
    with WidgetsBindingObserver, RouteAware {
  int _selectedTab = 0;
  int _upcomingPage = 1;
  int _completedPage = 1;
  int _cancelledPage = 1;
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _completedAppointments = [];
  // Cancelled and no-show were filed under "Completed", which read as if the
  // customer had actually received the service. They get their own tab.
  List<Map<String, dynamic>> _cancelledAppointments = [];
  bool _loading = true;
  String? _error;
  final Set<int> _processingAppointmentIds = <int>{};
  bool _isRouteSubscribed = false;
  DateTime? _lastLoadedAt;
  bool _loadInFlight = false;

  static const int _itemsPerPage = 4;
  /// How long a loaded list is trusted before a revisit refetches it.
  static const Duration _staleAfter = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppointments();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isRouteSubscribed) {
      routeObserver.unsubscribe(this);
      _isRouteSubscribed = false;
    }
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
      _loadAppointments();
    }
  }

  @override
  void didPopNext() {
    _loadAppointments();
  }

  /// [force] skips the staleness check -- used after an action that changed
  /// the data (cancel, reschedule, pull-to-refresh).
  Future<void> _loadAppointments({bool force = false}) async {
    if (UserSession.userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    // Returning from any pushed page and every app resume used to refetch the
    // whole list, so simply opening an appointment and coming back showed a
    // full-screen spinner on a list that had not changed.
    final loadedAt = _lastLoadedAt;
    final isFresh = loadedAt != null &&
        DateTime.now().difference(loadedAt) < _staleAfter &&
        _error == null;
    if (!force && isFresh) return;
    if (_loadInFlight) return;
    _loadInFlight = true;

    if (!mounted) {
      _loadInFlight = false;
      return;
    }
    // Only block the page when there is nothing to show yet; a refresh over
    // existing rows happens quietly underneath.
    final hasRows = _upcomingAppointments.isNotEmpty ||
        _completedAppointments.isNotEmpty ||
        _cancelledAppointments.isNotEmpty;
    setState(() {
      _loading = !hasRows;
      _error = null;
    });

    try {
      final data = await CustomerApi.postDecoded('booking.php', {
        'action': 'listByCustomer',
        'userID': UserSession.userId,
      });

      final items = (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final upcoming = <Map<String, dynamic>>[];
      final completed = <Map<String, dynamic>>[];
      final cancelled = <Map<String, dynamic>>[];

      for (final appt in items) {
        final services = (appt['services'] as List<dynamic>? ?? []);
        final firstService =
            services.isNotEmpty ? services.first as Map : <String, dynamic>{};
        final status = appt['status']?.toString() ?? '';

        final appointmentId = appt['appointmentID'];
        final isPaymentOverride = widget.highlightAppointmentId != null &&
            '$appointmentId' == '${widget.highlightAppointmentId}';
        final forcedState = widget.forcedPaymentState;
        final forcedReceipt = widget.forcedReceiptRef;

        final isGroup = appt['isGroup'] == true;
        final displayTitle = isGroup
            ? (appt['displayTitle']?.toString() ?? firstService['hairstyleName']?.toString() ?? 'Group booking')
            : (firstService['hairstyleName']?.toString() ??
                firstService['serviceName']?.toString() ??
                'Haircut');
        final timeRangeRaw = appt['timeRange']?.toString() ?? '';
        final timeRange = timeRangeRaw.isNotEmpty
            ? formatTimeRangeTo12h(timeRangeRaw)
            : '';
        final peopleCount = (appt['peopleCount'] as num?)?.toInt() ??
            (isGroup ? (appt['groupMembers'] as List?)?.length ?? 1 : 1);
        final perPersonMinutes =
            (firstService['durationMinutes'] as num?)?.toInt() ?? 60;
        final totalDurationMinutes = (appt['totalDurationMinutes'] as num?)?.toInt() ??
            (perPersonMinutes * peopleCount);
        final totalPrice = isGroup
            ? (appt['totalPrice']?.toString() ?? firstService['price']?.toString() ?? '0')
            : (firstService['price']?.toString() ?? '0');

        final mapped = {
          'appointmentId': appointmentId,
          'isGroup': isGroup,
          'bookingGroupID': appt['bookingGroupID'],
          'displayTitle': displayTitle,
          'groupMembers': appt['groupMembers'] ?? [],
          'groupMemberNames': appt['groupMemberNames'] ?? [],
          'peopleCount': peopleCount,
          'totalDurationMinutes': totalDurationMinutes,
          'timeRange': timeRange,
          'holdExpiresAt': appt['holdExpiresAt']?.toString(),
          'intentCreatedAt': appt['intentCreatedAt']?.toString(),
          'barberID': appt['barberID'],
          'frontViewUrl': appt['frontViewUrl'],
          'sideViewUrl': appt['sideViewUrl'],
          'backViewUrl': appt['backViewUrl'],
          'customerFrontUrl': appt['frontViewUrl'],
          'customerLeftUrl': appt['sideViewUrl'],
          'customerRightUrl': appt['backViewUrl'],
          'status': isPaymentOverride && forcedState == 'Paid'
              ? 'Scheduled'
              : status,
          'cancelReason': appt['cancelReason']?.toString(),
          'paymentState': isPaymentOverride && forcedState != null
              ? forcedState
              : appt['paymentState']?.toString() ??
                  (status == 'PendingPayment' ? 'Unpaid' : 'Unpaid'),
          'paymentStatus': isPaymentOverride && forcedState != null
              ? forcedState
              : appt['paymentStatus']?.toString(),
          'receiptRef': isPaymentOverride && forcedReceipt != null
              ? forcedReceipt
              : appt['receiptRef']?.toString(),
          'intentID': appt['intentID'],
          'intentStatus': isPaymentOverride && forcedState != null
              ? forcedState
              : appt['intentStatus']?.toString(),
          'intentExpiresAt': isPaymentOverride && forcedState == 'Paid'
              ? null
              : appt['intentExpiresAt']?.toString(),
          'canRetryPayment': isPaymentOverride && forcedState == 'Paid'
              ? false
              : appt['canRetryPayment'] == true,
          'canReschedule': isPaymentOverride && forcedState == 'Paid'
              ? true
              : appt['canReschedule'] == true,
          'rescheduleCount': appt['rescheduleCount'] ?? 0,
          'reschedulesRemaining': appt['reschedulesRemaining'] ?? 0,
          'rescheduleBlockedReason': appt['rescheduleBlockedReason']?.toString(),
          'intentFailureReason': appt['intentFailureReason']?.toString(),
          'service': displayTitle,
          'serviceID': firstService['serviceID'],
          'variantID': firstService['variantID'],
          'barber': 'with ${appt['barberName'] ?? ''}',
          'date': appt['appointmentDate']?.toString() ?? '',
          'time': timeRange.isNotEmpty
              ? timeRange
              : formatTo12Hour(appt['startTime']?.toString() ?? ''),
          'endTime': appt['endTime']?.toString() ?? '',
          'duration': isGroup
              ? '$totalDurationMinutes min ($peopleCount × $perPersonMinutes min)'
              : (firstService['durationMinutes'] != null
                  ? '${firstService['durationMinutes']} min'
                  : '—'),
          'price': '₱$totalPrice',
          'rating': status == 'Completed' ? '★★★★★' : null,
        };

        if (status == 'Completed') {
          completed.add(mapped);
        } else if (status == 'Cancelled' || status == 'NoShow') {
          cancelled.add(mapped);
        } else if (appointmentSlotHasPassed(
          date: mapped['date']?.toString(),
          endTime: mapped['endTime']?.toString(),
        )) {
          // The server sweep (expire_unpaid_past_appointments) is what actually
          // resolves these, but it is throttled and runs on request traffic, so
          // a stale row can still arrive here. Keep it out of Upcoming rather
          // than showing a date that has already gone by.
          completed.add(mapped);
        } else {
          upcoming.add(mapped);
        }
      }

      _lastLoadedAt = DateTime.now();
      if (!mounted) return;
      setState(() {
        _upcomingAppointments = upcoming;
        _completedAppointments = completed;
        _cancelledAppointments = cancelled;
        _upcomingPage = 1;
        _completedPage = 1;
        _cancelledPage = 1;
        _loading = false;
      });
    } on CustomerApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load appointments: $e';
        _loading = false;
      });
    } finally {
      _loadInFlight = false;
    }
  }

  /// The history tab holds Completed, Cancelled and NoShow appointments, so the
  /// badge has to reflect the real status. It used to be hardcoded to
  /// "Completed", which showed cancelled appointments as completed.
  String _historyStatusLabel(String status) {
    switch (status) {
      case 'Cancelled':
        return 'Cancelled';
      case 'NoShow':
        return 'No Show';
      default:
        return 'Completed';
    }
  }

  Color _historyStatusColor(String status) {
    switch (status) {
      case 'Cancelled':
        return const Color(0xFFE57373);
      case 'NoShow':
        return const Color(0xFFE67E22);
      default:
        return const Color(0xFF999999);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allAppointments =
        _selectedTab == 0
            ? _upcomingAppointments
            : _selectedTab == 1
                ? _completedAppointments
                : _cancelledAppointments;
    final currentPage = _selectedTab == 0
        ? _upcomingPage
        : _selectedTab == 1
            ? _completedPage
            : _cancelledPage;
    final totalPages = _totalPages(allAppointments.length);
    final safePage = currentPage.clamp(1, totalPages);
    final appointments = _paginateAppointments(allAppointments, safePage);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => navigateBackToCustomerHome(context),
        onProfileTap: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: RefreshIndicator(
        onRefresh: _loadAppointments,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PillTabs(
                labels: const ['Upcoming', 'Completed', 'Cancelled'],
                selectedIndex: _selectedTab,
                onSelected: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: 24),
              if (_loading)
                _buildAppointmentsSkeleton()
              else if (_error != null)
                Center(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.white70)))
              else if (appointments.isEmpty)
                Center(
                  child: Text(
                    _selectedTab == 0
                        ? 'No upcoming appointments.'
                        : _selectedTab == 1
                            ? 'No completed appointments.'
                            : 'No cancelled appointments.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              else
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    key: ValueKey<int>(_selectedTab),
                    children: appointments.map((appointment) {
                      final isUpcoming = _selectedTab == 0;
                      final statusText =
                          (appointment['status']?.toString() ?? 'Scheduled')
                              .trim();
                      final paymentState =
                          appointment['paymentState']?.toString() ??
                              (statusText == 'PendingPayment' ? 'Unpaid' : 'Unpaid');
                      final isPendingPayment =
                          statusText == 'PendingPayment' && paymentState != 'Paid';
                      final paymentChip = _buildPaymentChip(paymentState);
                      final appointmentId =
                          int.tryParse('${appointment['appointmentId'] ?? ''}') ??
                              0;
                      final isProcessing = appointmentId > 0 &&
                          _processingAppointmentIds.contains(appointmentId);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (appointment['isGroup'] == true)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.groups_rounded,
                                      color: AppBrand.accent,
                                      size: 28,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appointment['isGroup'] == true
                                            ? (appointment['displayTitle'] as String? ??
                                                appointment['service'] as String)
                                            : appointment['service'] as String,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        appointment['barber'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                      const SizedBox(height: 6),
                                      paymentChip,
                                      if (!isUpcoming &&
                                          statusText == 'Cancelled' &&
                                          (appointment['cancelReason']
                                                  as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                              true) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Reason: ${appointment['cancelReason']}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFE57373),
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isUpcoming
                                        ? (isPendingPayment
                                            ? const Color(0xFFE67E22)
                                                .withOpacity(0.2)
                                            : const Color(0xFF4CAF50)
                                                .withOpacity(0.2))
                                        : _historyStatusColor(statusText)
                                            .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isUpcoming
                                        ? (isPendingPayment
                                            ? 'Pending Payment'
                                            : 'Confirmed')
                                        : _historyStatusLabel(statusText),
                                    style: TextStyle(
                                      color: isUpcoming
                                          ? (isPendingPayment
                                              ? const Color(0xFFE67E22)
                                              : const Color(0xFF4CAF50))
                                          : _historyStatusColor(statusText),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (isUpcoming) _buildPaymentHint(appointment),
                            if (isUpcoming) const SizedBox(height: 10),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.calendar_today,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                            appointment['date'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12),
                                          ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                            appointment['time'] as String,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12),
                                          ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.timer,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              appointment['duration'] as String,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.local_offer,
                                              color: Colors.white, size: 16),
                                          const SizedBox(width: 8),
                                          Text(
                                            appointment['price'] as String,
                                            style: const TextStyle(
                                              color: AppBrand.accent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (appointment['rating'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8, top: 10),
                                    child: Text(
                                      appointment['rating'] as String,
                                      style: const TextStyle(
                                        color: AppBrand.accent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                    if (isUpcoming) ...[
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CompletedAppointmentDetailPage(
                                                appointment: appointment,
                                                isUpcoming: true,
                                              ),
                                            ),
                                          );
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppBrand.accent,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                        child: const Text(
                                          'View',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      if (paymentState != 'Paid')
                                            ElevatedButton(
                                              onPressed: isProcessing
                                                  ? null
                                                  : () => _retryPayment(
                                                      appointment),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: Colors.black,
                                                visualDensity: VisualDensity.compact,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 8),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6)),
                                              ),
                                              child: const Text(
                                                'Pay Now',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize: 11),
                                              ),
                                            ),
                                          OutlinedButton(
                                            onPressed: isProcessing ||
                                                    appointment['canReschedule'] != true
                                                ? null
                                                : () => _rescheduleAppointment(
                                                    appointment),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  appointment['canReschedule'] == true
                                                      ? AppBrand.accent
                                                      : Colors.white38,
                                              visualDensity: VisualDensity.compact,
                                              side: BorderSide(
                                                  color: appointment['canReschedule'] == true
                                                      ? AppBrand.accent
                                                      : Colors.white24,
                                                  width: 1),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                            ),
                                            child: const Text(
                                              'Reschedule',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11),
                                            ),
                                          ),
                                          OutlinedButton(
                                            onPressed: isProcessing
                                                ? null
                                                : () => _showCancelModal(
                                                    appointment),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  const Color(0xFFE74C3C),
                                              visualDensity: VisualDensity.compact,
                                              side: const BorderSide(
                                                  color: Color(0xFFE74C3C),
                                                  width: 1),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                            ),
                                            child: isProcessing
                                                ? const SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color: Color(
                                                                0xFFE74C3C)),
                                                  )
                                                : const Text(
                                                    'Cancel',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                          ),
                                    ] else ...[
                                          ElevatedButton(
                                            onPressed: isProcessing
                                                ? null
                                                : () => _handleBookAgain(
                                                    appointment),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                            ),
                                            child: isProcessing
                                                ? const SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.black),
                                                  )
                                                : const Text(
                                                    'Book Again',
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context)
                                                  .push(MaterialPageRoute(
                                                builder: (_) =>
                                                    CompletedAppointmentDetailPage(
                                                        appointment:
                                                            appointment),
                                              ));
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor:
                                                  AppBrand.accent,
                                              visualDensity: VisualDensity.compact,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                            ),
                                            child: const Text(
                                              'View',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11),
                                            ),
                                          ),
                                          OutlinedButton(
                                            onPressed: isProcessing
                                                ? null
                                                : () => _showFeedbackModal(
                                                    context, appointment),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              visualDensity: VisualDensity.compact,
                                              side: const BorderSide(
                                                  color: Colors.white24),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6)),
                                            ),
                                            child: const Text(
                                              'Feedback',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11),
                                            ),
                                          ),
                                    ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              if (!_loading && _error == null && allAppointments.isNotEmpty)
                PaginationControls(
                  currentPage: safePage,
                  totalPages: totalPages,
                  onPageChanged: (page) {
                    setState(() {
                      if (_selectedTab == 0) {
                        _upcomingPage = page;
                      } else if (_selectedTab == 1) {
                        _completedPage = page;
                      } else {
                        _cancelledPage = page;
                      }
                    });
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            navigateToCustomerHome(context);
          } else if (index == 1) {
            // already on Appointments
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

  int _totalPages(int totalItems) {
    if (totalItems <= 0) {
      return 1;
    }
    return ((totalItems - 1) ~/ _itemsPerPage) + 1;
  }

  List<Map<String, dynamic>> _paginateAppointments(
      List<Map<String, dynamic>> appointments, int page) {
    final start = (page - 1) * _itemsPerPage;
    if (start >= appointments.length) {
      return const <Map<String, dynamic>>[];
    }
    final end = (start + _itemsPerPage).clamp(0, appointments.length);
    return appointments.sublist(start, end);
  }

  Widget _buildPaymentChip(String state) {
    final normalized = state.trim();
    Color fg;
    Color bg;
    String label;

    switch (normalized) {
      case 'Paid':
        fg = const Color(0xFF4CAF50);
        bg = fg.withOpacity(0.18);
        label = 'Paid';
        break;
      case 'Verifying':
        fg = const Color(0xFF4FC3F7);
        bg = fg.withOpacity(0.18);
        label = 'Verifying';
        break;
      case 'Failed':
        fg = const Color(0xFFE74C3C);
        bg = fg.withOpacity(0.18);
        label = 'Failed';
        break;
      default:
        fg = const Color(0xFFE67E22);
        bg = fg.withOpacity(0.18);
        label = 'Unpaid';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  Widget _buildPaymentHint(Map<String, dynamic> appointment) {
    final paymentState = appointment['paymentState']?.toString() ?? 'Unpaid';
    final expiresAtRaw = appointment['intentExpiresAt']?.toString();
    final failureReason = appointment['intentFailureReason']?.toString();

    if (paymentState == 'Failed' &&
        failureReason != null &&
        failureReason.isNotEmpty) {
      return Text(
        failureReason,
        style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 11),
      );
    }

    if (paymentState == 'Unpaid' || paymentState == 'Verifying') {
      final holdEnds = reservationHoldEndsAt(
        holdExpiresAt: appointment['holdExpiresAt']?.toString(),
        intentCreatedAt: appointment['intentCreatedAt']?.toString(),
      );
      if (holdEnds != null) {
        final left = holdEnds.difference(DateTime.now());
        if (left.inSeconds > 0) {
          return Text(
            formatReservationHoldLabel(left),
            style: const TextStyle(
              color: Color(0xFFE67E22),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          );
        }
        return const Text(
          'Reservation hold expired — pay or rebook soon',
          style: TextStyle(color: Color(0xFFE67E22), fontSize: 11),
        );
      }
    }

    if (paymentState == 'Paid') {
      final receipt = appointment['receiptRef']?.toString();
      if (receipt != null && receipt.isNotEmpty) {
        return Text(
          'Receipt: $receipt',
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        );
      }
    }

    return const SizedBox.shrink();
  }

  Future<void> _retryPayment(Map<String, dynamic> appointment) async {
    final appointmentId =
        int.tryParse('${appointment['appointmentId'] ?? ''}') ?? 0;
    if (appointmentId <= 0) {
      return;
    }

    final priceText = appointment['price']?.toString() ?? '0';
    final amount = double.tryParse(priceText.replaceAll('₱', '').trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to determine payment amount.')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentPage(
          appointmentID: appointmentId,
          barberName: (appointment['barber']?.toString() ?? '')
              .replaceFirst('with ', ''),
          date: appointment['date']?.toString() ?? '',
          time: appointment['time']?.toString() ?? '',
          amount: amount.round(),
          haircutName: appointment['service']?.toString() ?? 'Haircut',
        ),
      ),
    );

    if (mounted) {
      _loadAppointments(force: true);
    }
  }

  Future<void> _rescheduleAppointment(Map<String, dynamic> appointment) async {
    final appointmentId =
        int.tryParse('${appointment['appointmentId'] ?? ''}') ?? 0;
    if (appointmentId <= 0) {
      return;
    }

    final canReschedule = appointment['canReschedule'] == true;
    if (!canReschedule) {
      final reason = appointment['rescheduleBlockedReason']?.toString() ??
          'Reschedule is not available for this appointment.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason)),
      );
      return;
    }

    final barberId = int.tryParse('${appointment['barberID'] ?? ''}') ?? 0;
    final barberName = (appointment['barber']?.toString() ?? '')
        .replaceFirst(RegExp(r'^with\s+', caseSensitive: false), '')
        .trim();
    if (barberId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barber information is missing.')),
      );
      return;
    }

    final remaining =
        int.tryParse('${appointment['reschedulesRemaining'] ?? ''}') ?? 0;

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CalendarPage(
          barberId: barberId,
          barberName: barberName.isNotEmpty ? barberName : 'Barber',
          rescheduleAppointmentId: appointmentId,
          reschedulesRemaining: remaining > 0 ? remaining : null,
        ),
      ),
    );

    if (!mounted) {
      return;
    }
    if (completed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment rescheduled.')),
      );
      _loadAppointments(force: true);
    }
  }

  String _addMinutes(String time, int minutes) {
    final parts = time.split(':');
    if (parts.length < 2) {
      return time;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final total = hour * 60 + minute + minutes;
    final endHour = (total ~/ 60) % 24;
    final endMinute = total % 60;
    return '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';
  }

  Future<void> _handleBookAgain(Map<String, dynamic> appointment) async {
    final appointmentId =
        int.tryParse('${appointment['appointmentId'] ?? ''}') ?? 0;
    if (appointmentId > 0 &&
        _processingAppointmentIds.contains(appointmentId)) {
      return;
    }
    if (appointmentId > 0 && mounted) {
      setState(() => _processingAppointmentIds.add(appointmentId));
    }

    try {
      UserSession.selectedVariantId =
          int.tryParse('${appointment['variantID'] ?? ''}');
      UserSession.selectedServiceId =
          int.tryParse('${appointment['serviceID'] ?? ''}');
      UserSession.selectedStyleName = appointment['service']?.toString();

      if (UserSession.selectedVariantId == null ||
          UserSession.selectedVariantId! <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Cannot book again because style details are missing.')),
        );
        return;
      }

      final result = await BookingSlotsService.fetchBestSuggestion();
      if (!mounted) {
        return;
      }

      if (!result.isSuccess || result.suggestion == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No auto-suggested slot available. Choose manually.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SuggestedAppointmentPage(
            suggestion: result.suggestion!,
            alternatives: result.alternatives,
          ),
        ),
      );
    } finally {
      if (mounted && appointmentId > 0) {
        setState(() => _processingAppointmentIds.remove(appointmentId));
      }
    }
  }

  Future<void> _showCancelModal(Map<String, dynamic> appointment) async {
    // The sheet owns its own controller and selection state.
    //
    // Previously the controller was created here and disposed immediately after
    // the sheet's future completed. showModalBottomSheet returns as soon as
    // pop() is called, while the route is still animating out and its TextField
    // is still mounted and listening to that controller -- disposing it then
    // tore down a widget that still had dependents, which is the
    // '_dependents.isEmpty' assertion seen on cancel. Letting the sheet's own
    // State dispose it ties the lifetime to the widget that actually uses it.
    //
    // It also fixes the reason dropdown, which never repainted the selected
    // value because the old builder had no setState.
    // Only ask for a number when there is money to send back and the profile
    // has none. Unpaid cancellations should not be interrogated.
    final isPaid = (appointment['paymentState']?.toString() ?? '')
            .toLowerCase()
            .contains('paid') ||
        (appointment['isPaid'] == true);
    // Only a paid cancellation needs a refund contact, so only that case is
    // worth a lookup. UserSession.phone is populated by the profile page, which
    // the customer may never have opened in this run -- fall back to the
    // persisted value, then to the profile itself, before asking them to type a
    // number the account already has.
    final hasPhone = isPaid ? await _resolveHasPhone() : true;
    if (!mounted) return;

    // Ask the server what cancelling right now actually costs. Refunds close
    // 24 hours out and pause after repeated use, and the customer should read
    // that before confirming, not discover it when no money arrives.
    final quote = isPaid ? await _fetchRefundQuote(appointment) : null;
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CancelAppointmentSheet(
        needsPhone: !hasPhone,
        refundQuote: quote,
      ),
    );

    final reason = result?['reason'] ?? '';
    if (reason.isEmpty) return;
    if (!mounted) return;
    await _cancelAppointment(
      appointment,
      reason,
      contactPhone: result?['contactPhone'],
    );
  }

  /// What cancelling this booking right now would refund, if anything.
  ///
  /// Returns null when the quote cannot be fetched; the sheet then says
  /// nothing about refunds rather than guessing, and the server still has the
  /// final say when the cancellation is submitted.
  Future<Map<String, dynamic>?> _fetchRefundQuote(
      Map<String, dynamic> appointment) async {
    final appointmentId = appointment['appointmentID'] ?? appointment['appointment_id'];
    if (appointmentId == null) return null;

    try {
      return await CustomerApi.postDecoded('booking.php', {
        'action': 'refundQuote',
        'appointmentID': appointmentId,
        'userID': UserSession.userId,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> _cancelAppointment(
      Map<String, dynamic> appointment, String reason,
      {String? contactPhone}) async {
    final appointmentId = appointment['appointmentId'];
    if (appointmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing appointment ID.')));
      return;
    }
    final normalizedId = int.tryParse('$appointmentId') ?? 0;
    if (normalizedId > 0 && _processingAppointmentIds.contains(normalizedId)) {
      return;
    }
    if (normalizedId > 0 && mounted) {
      setState(() => _processingAppointmentIds.add(normalizedId));
    }
    try {
      await CustomerApi.postDecoded('booking.php', {
        'action': 'cancel',
        'appointmentID': appointmentId,
        'userID': UserSession.userId,
        'reason': reason,
        if (contactPhone != null && contactPhone.trim().isNotEmpty)
          'contactPhone': contactPhone.trim(),
      });
      if (!mounted) {
        return;
      }
      await _loadAppointments(force: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Appointment cancelled')));
    } on CustomerApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel appointment: $e')));
    } finally {
      if (mounted && normalizedId > 0) {
        setState(() => _processingAppointmentIds.remove(normalizedId));
      }
    }
  }

  void _showFeedbackModal(
      BuildContext context, Map<String, dynamic> appointment) {
    int rating = 0;
    final controller = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Leave Feedback',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  appointment['service'] as String,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(5, (index) {
                    final isActive = index < rating;
                    return IconButton(
                      onPressed: () => setState(() => rating = index + 1),
                      icon: Icon(
                        isActive ? Icons.star : Icons.star_border,
                        color: AppBrand.accent,
                      ),
                    );
                  }),
                ),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Write your review (optional)',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _submitBarberFeedback(
                            appointment: appointment,
                            rating: rating,
                            comment: controller.text.trim(),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black),
                        child: const Text('Submit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitBarberFeedback({
    required Map<String, dynamic> appointment,
    required int rating,
    required String comment,
  }) async {
    final appointmentID =
        int.tryParse('${appointment['appointmentId'] ?? ''}') ?? 0;
    final barberID = int.tryParse('${appointment['barberID'] ?? ''}') ?? 0;
    final userID = UserSession.userId ?? 0;

    if (rating < 1 || rating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a rating from 1 to 5 stars.')),
      );
      return;
    }

    if (appointmentID <= 0 || barberID <= 0 || userID <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feedback details are incomplete.')),
      );
      return;
    }

    if (_processingAppointmentIds.contains(appointmentID)) {
      return;
    }

    if (mounted) {
      setState(() => _processingAppointmentIds.add(appointmentID));
    }

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: await CustomerApi.headers(),
        body: jsonEncode({
          'action': 'submitFeedback',
          'appointmentID': appointmentID,
          'barberID': barberID,
          'userID': userID,
          'rating': rating,
          'comment': comment,
        }),
      );

      if (!mounted) {
        return;
      }

      final data = CustomerApi.decodeJsonObject(response);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(data['message']?.toString() ?? 'Feedback submitted.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit feedback: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingAppointmentIds.remove(appointmentID));
      }
    }
  }

  Widget _buildAppointmentsSkeleton() {
    return AppShimmer(
      child: Column(
        children: List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmerBox(width: 160, height: 14, borderRadius: 6),
                SizedBox(height: 10),
                AppShimmerBox(width: 120, height: 12, borderRadius: 6),
                SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppShimmerBox(height: 12, borderRadius: 6),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: AppShimmerBox(height: 12, borderRadius: 6),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppShimmerBox(width: 88, height: 32, borderRadius: 6),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// True when the account already has a contact number for a refund, checking
/// memory, then persisted storage, then the profile API.
///
/// A network failure returns false, which asks for the number: better to
/// collect one that may be redundant than to cancel a paid booking with no way
/// to send the money back.
Future<bool> _resolveHasPhone() async {
  if (UserSession.hasUsablePhone) return true;

  await UserSession.loadPhone();
  if (UserSession.hasUsablePhone) return true;

  final userId = UserSession.userId;
  if (userId == null) return false;

  try {
    final body = await CustomerApi.postDecoded('profile.php', {
      'action': 'get',
      'userID': userId,
    });
    final profile = body['profile'];
    if (profile is Map) {
      await UserSession.setPhone(profile['phone']?.toString());
    }
  } catch (_) {
    return false;
  }
  return UserSession.hasUsablePhone;
}

/// Bottom sheet for cancelling an appointment. Owns the note controller so it
/// is disposed with the widget tree that uses it, not by the caller.
class _CancelAppointmentSheet extends StatefulWidget {
  /// True when the appointment was paid AND the account has no phone number.
  /// A manual refund cannot be sent without one, so it is collected here rather
  /// than chased afterwards.
  final bool needsPhone;

  /// The server's answer on whether this cancellation is refundable. Null when
  /// the booking was never paid, or the quote could not be fetched.
  final Map<String, dynamic>? refundQuote;

  const _CancelAppointmentSheet({this.needsPhone = false, this.refundQuote});

  @override
  State<_CancelAppointmentSheet> createState() =>
      _CancelAppointmentSheetState();
}

class _CancelAppointmentSheetState extends State<_CancelAppointmentSheet> {
  static const _reasons = [
    'Scheduling conflict',
    'Found another barber',
    'Too far/transport issues',
    'Not feeling well',
    'Other',
  ];

  final _controller = TextEditingController();
  final _phoneController = TextEditingController();
  String _selected = _reasons.first;
  String? _phoneError;

  @override
  void dispose() {
    _controller.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Whether the money comes back, said plainly before they confirm.
  ///
  /// The slot is always released -- that is worth more to the shop than
  /// holding a customer to a booking they cannot attend -- so the refusal
  /// cases make clear the cancellation itself still goes through.
  Widget _buildRefundNotice(Map<String, dynamic> quote) {
    final refundable = quote['refundable'] == true;
    final amount = (quote['amount'] as num?)?.toDouble() ?? 0;
    final reason = quote['reason']?.toString() ?? '';
    final accent = refundable ? const Color(0xFF5FC98A) : const Color(0xFFE0A23C);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                refundable ? Icons.payments_outlined : Icons.info_outline,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  refundable
                      ? 'Refund of ₱${amount.toStringAsFixed(2)}'
                      : 'No refund for this cancellation',
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
          if (refundable) ...[
            const SizedBox(height: 6),
            const Text(
              'Sent by hand once the desk confirms it, to the number on your '
              'account.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  void _close(Map<String, String>? result) {
    // Drop focus before popping: tearing the focus tree down in the same frame
    // as the route is what trips the framework assertion.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cancel Appointment',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          if (widget.refundQuote != null) ...[
            const SizedBox(height: 12),
            _buildRefundNotice(widget.refundQuote!),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selected,
            dropdownColor: const Color(0xFF1A1A1A),
            iconEnabledColor: Colors.white,
            decoration: const InputDecoration(
              labelText: 'Reason',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white)),
            ),
            items: _reasons
                .map((reason) => DropdownMenuItem(
                    value: reason,
                    child: Text(reason,
                        style: const TextStyle(color: Colors.white))))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _selected = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Optional note',
              hintStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          if (widget.needsPhone) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Contact number for your refund',
                labelStyle: const TextStyle(color: Colors.white70),
                helperText: 'This booking was paid. We need a number to send it to.',
                helperStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                errorText: _phoneError,
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _close(null),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Keep'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final note = _controller.text.trim();
                    final phone = _phoneController.text.trim();
                    // Same PH rule as registration. "Any 7+ characters" let a
                    // number through that the receptionist could not send money
                    // to, which defeats the point of collecting it.
                    if (widget.needsPhone && !PhPhone.isValid(phone)) {
                      setState(() => _phoneError = PhPhone.error);
                      return;
                    }
                    _close({
                      'reason':
                          _selected == 'Other' && note.isNotEmpty ? note : _selected,
                      if (phone.isNotEmpty) 'contactPhone': phone,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black),
                  child: const Text('Cancel Appointment'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
