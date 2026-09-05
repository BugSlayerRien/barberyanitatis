import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'user_session.dart';
import 'suggested_appointment_page.dart';
import 'barber_selection_page.dart';
import 'services/booking_slots_service.dart';
import 'payment_page.dart';
import 'calendar_page.dart';
import '../shared/pagination_controls.dart';
import '../main.dart';

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
  List<Map<String, dynamic>> _upcomingAppointments = [];
  List<Map<String, dynamic>> _completedAppointments = [];
  bool _loading = true;
  String? _error;
  final Set<int> _processingAppointmentIds = <int>{};
  bool _isRouteSubscribed = false;

  static const int _itemsPerPage = 4;

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

  Future<void> _loadAppointments() async {
    if (UserSession.userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
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
          completed.add(mapped);
        } else {
          upcoming.add(mapped);
        }
      }

      if (!mounted) return;
      setState(() {
        _upcomingAppointments = upcoming;
        _completedAppointments = completed;
        _upcomingPage = 1;
        _completedPage = 1;
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
        _selectedTab == 0 ? _upcomingAppointments : _completedAppointments;
    final currentPage = _selectedTab == 0 ? _upcomingPage : _completedPage;
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
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedTab = 0;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Upcoming',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 0
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedTab = 1;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Completed',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 1
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                        : 'No completed appointments.',
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
                                      color: Color(0xFFA99941),
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
                                              color: Color(0xFFA99941),
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
                                        color: Color(0xFFA99941),
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
                                          foregroundColor: const Color(0xFFA99941),
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
                                                      ? const Color(0xFFA99941)
                                                      : Colors.white38,
                                              visualDensity: VisualDensity.compact,
                                              side: BorderSide(
                                                  color: appointment['canReschedule'] == true
                                                      ? const Color(0xFFA99941)
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
                                                  const Color(0xFFA99941),
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
                      } else {
                        _completedPage = page;
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
      _loadAppointments();
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
      _loadAppointments();
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
    final reasons = [
      'Scheduling conflict',
      'Found another barber',
      'Too far/transport issues',
      'Not feeling well',
      'Other',
    ];
    String selected = reasons.first;
    final controller = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cancel Appointment',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selected,
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
              items: reasons
                  .map((reason) => DropdownMenuItem(
                      value: reason,
                      child: Text(reason,
                          style: const TextStyle(color: Colors.white))))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  selected = value;
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      FocusScope.of(ctx).unfocus();
                      Navigator.of(ctx).pop(false);
                    },
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Keep'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    // Drop focus before popping. Popping this sheet while the
                    // note TextField still holds focus (keyboard open) tears the
                    // focus/InheritedWidget tree down in the same frame as the
                    // route, which trips a '_dependents.isEmpty' assertion in
                    // the framework.
                    onPressed: () {
                      FocusScope.of(ctx).unfocus();
                      Navigator.of(ctx).pop(true);
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
      ),
    );

    if (confirmed != true) {
      controller.dispose();
      return;
    }

    final reason = selected == 'Other' && controller.text.trim().isNotEmpty
        ? controller.text.trim()
        : selected;
    controller.dispose();
    await _cancelAppointment(appointment, reason);
  }

  Future<void> _cancelAppointment(
      Map<String, dynamic> appointment, String reason) async {
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
      });
      if (!mounted) {
        return;
      }
      await _loadAppointments();
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
                        color: const Color(0xFFA99941),
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
