import 'dart:convert';

import 'package:flutter/material.dart';
import '../user/app_brand.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';
import '../user/time_format_utils.dart';
import '../user/user_session.dart';

const Color _kGold = AppBrand.accent;

class BarberCalendarPage extends StatefulWidget {
  const BarberCalendarPage({super.key});

  @override
  State<BarberCalendarPage> createState() => _BarberCalendarPageState();
}

class _BarberCalendarPageState extends State<BarberCalendarPage> {
  static const int _bookingWindowDays = 30;
  static const Color _closedHolidayFill = Color(0xFF3A1F1F);
  static const Color _closedHolidayText = Color(0xFFFFB4B4);
  static const Color _closedWeeklyFill = Color(0xFF1C1C1C);

  late DateTime _currentMonth;
  late DateTime _selectedDate;
  bool _loading = true;
  bool _hasLoadedOnce = false;
  int _loadSeq = 0;
  String? _error;
  List<Map<String, dynamic>> _appointments = [];
  Map<String, int> _bookedByDate = {};
  Map<String, String> _requestStatusByDate = {};
  Map<String, Map<String, dynamic>> _closureByDate = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _load();
  }

  /// Paid leave left this year, as reported by listMonth. Null until loaded.
  Map<String, dynamic>? _leaveBalance;

  int get _leaveRemaining => (_leaveBalance?['remaining'] as num?)?.toInt() ?? -1;

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _monthLabel(DateTime month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  String _dateKey(String raw) {
    final value = raw.trim();
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  Future<void> _load() async {
    final barberId = UserSession.userId;
    if (barberId == null) return;

    final seq = ++_loadSeq;
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    setState(() {
      _loading = true;
      _error = null;
      _bookedByDate = {};
      _requestStatusByDate = {};
      _closureByDate = {};
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barber_schedule.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listMonth',
          'barberID': barberId,
          'year': year,
          'month': month,
        }),
      );
      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (seq != _loadSeq || !mounted) {
        return;
      }

      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load schedule';
          _loading = false;
          _hasLoadedOnce = true;
        });
        return;
      }

      final appointments = (data['appointments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final requests = (data['requests'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final booked = <String, int>{};
      for (final appt in appointments) {
        final key = _dateKey(appt['appointment_date']?.toString() ?? '');
        if (key.isEmpty) continue;
        booked[key] = (booked[key] ?? 0) + 1;
      }

      final requestMap = <String, String>{};
      for (final req in requests) {
        final key = _dateKey(req['request_date']?.toString() ?? '');
        if (key.isEmpty) continue;
        requestMap[key] = req['status']?.toString() ?? 'Pending';
      }

      final rawBalance = data['leaveBalance'];
      final leaveBalance =
          rawBalance is Map ? Map<String, dynamic>.from(rawBalance) : null;

      final closures = <String, Map<String, dynamic>>{};
      final rawClosures = data['closures'];
      if (rawClosures is Map) {
        rawClosures.forEach((key, value) {
          final dateKey = _dateKey(key.toString());
          if (dateKey.isEmpty || value is! Map) return;
          closures[dateKey] = Map<String, dynamic>.from(value);
        });
      }

      setState(() {
        _appointments = appointments;
        _bookedByDate = booked;
        _requestStatusByDate = requestMap;
        _closureByDate = closures;
        _leaveBalance = leaveBalance ?? _leaveBalance;
        _loading = false;
        _hasLoadedOnce = true;
      });
    } catch (e) {
      if (seq != _loadSeq || !mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _hasLoadedOnce = true;
      });
    }
  }

  /// How much paid leave is left, and how much of it is still unapproved.
  ///
  /// A barber could file unlimited days off and had no way of knowing how many
  /// they had taken. Pending days are shown separately because they already
  /// count against the allowance -- the receptionist has not agreed to them
  /// yet, but the day is spoken for.
  Widget _buildLeaveBalanceCard() {
    final balance = _leaveBalance!;
    final allowance = (balance['allowance'] as num?)?.toInt() ?? 0;
    final used = (balance['used'] as num?)?.toInt() ?? 0;
    final pending = (balance['pending'] as num?)?.toInt() ?? 0;
    final remaining = (balance['remaining'] as num?)?.toInt() ?? 0;
    final year = (balance['year'] as num?)?.toInt();
    final ratio = allowance > 0 ? (used / allowance).clamp(0.0, 1.0) : 0.0;
    final accent = remaining == 0
        ? Colors.orangeAccent
        : (remaining <= 3 ? const Color(0xFFE0A23C) : _kGold);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.beach_access_rounded, size: 16, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Paid leave${year != null ? ' · $year' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$remaining of $allowance left',
                style: TextStyle(
                  color: accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: const Color(0xFF262626),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            pending > 0
                ? '$used day${used == 1 ? '' : 's'} used, including $pending awaiting approval.'
                : '$used day${used == 1 ? '' : 's'} used so far.',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _appointmentsForSelectedDay() {
    final key = _formatDate(_selectedDate);
    return _appointments
        .where((a) => _dateKey(a['appointment_date']?.toString() ?? '') == key)
        .toList();
  }

  Future<void> _requestDayOff(DateTime day) async {
    final barberId = UserSession.userId;
    if (barberId == null) return;

    final today = DateTime.now();
    final dayOnly = DateTime(day.year, day.month, day.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (dayOnly.isBefore(todayOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot request time off for past dates.')),
      );
      return;
    }

    final dateKey = _formatDate(day);
    final existing = _requestStatusByDate[dateKey];
    if (existing == 'Pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have a pending request for this date.')),
      );
      return;
    }
    if (existing == 'Approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This date is already approved as unavailable.')),
      );
      return;
    }

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'Request day off · ${day.month}/${day.day}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: noteController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Optional note for receptionist',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/barber_schedule.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'submitUnavailability',
        'barberID': barberId,
        'requestDate': dateKey,
        'note': noteController.text.trim(),
      }),
    );
    noteController.dispose();
    if (!mounted) return;

    final data = response.body.isNotEmpty
        ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
        : <String, dynamic>{};

    final returnedBalance = data['leaveBalance'];
    if (returnedBalance is Map) {
      setState(() => _leaveBalance = Map<String, dynamic>.from(returnedBalance));
    }

    if (response.statusCode == 200) {
      final left = (data['leaveBalance']?['remaining'] as num?)?.toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            left == null
                ? 'Request sent to receptionist for approval.'
                : 'Request sent for approval. $left paid leave day${left == 1 ? '' : 's'} left.',
          ),
        ),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error']?.toString() ?? 'Could not submit request.')),
      );
    }
  }

  void _onDayTap(DateTime date, {required bool isPast}) {
    setState(() => _selectedDate = date);
    if (isPast) return;

    final dateKey = _formatDate(date);
    final status = _requestStatusByDate[dateKey];
    if (status == 'Approved') {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final count = _bookedByDate[dateKey] ?? 0;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.month}/${date.day}/${date.year}',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                count > 0 ? '$count appointment(s) scheduled' : 'No appointments',
                style: const TextStyle(color: Colors.white70),
              ),
              if (status != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Time-off request: $status',
                  style: TextStyle(
                    color: status == 'Approved'
                        ? Colors.redAccent
                        : (status == 'Rejected' || status == 'Expired')
                            ? Colors.orange
                            : _kGold,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Refusing here rather than at the server keeps the barber from
              // filling in a note for a request that cannot be accepted.
              if (status != 'Pending' && _leaveRemaining == 0)
                const Text(
                  'You have used all your paid leave days for this year.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                )
              else if (status != 'Pending')
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _requestDayOff(date);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    child: const Text('Request day off'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_hasLoadedOnce) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0A),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.white70))),
      );
    }

    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final bookingWindowEnd = todayDate.add(Duration(days: _bookingWindowDays - 1));
    final currentMonthKey = DateTime(today.year, today.month);
    final viewingThisMonth =
        _currentMonth.year == currentMonthKey.year && _currentMonth.month == currentMonthKey.month;
    final canGoPrev = !viewingThisMonth;
    final canGoNext = viewingThisMonth;
    final dayAppointments = _appointmentsForSelectedDay();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('My schedule', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tap a date to view bookings or request time off (receptionist must approve).',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            if (_leaveBalance != null) ...[
              const SizedBox(height: 14),
              _buildLeaveBalanceCard(),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _monthLabel(_currentMonth),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: canGoPrev
                                ? () {
                                    setState(() {
                                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                                    });
                                    _load();
                                  }
                                : null,
                            icon: Icon(Icons.chevron_left, color: canGoPrev ? Colors.white : Colors.white24),
                          ),
                          IconButton(
                            onPressed: canGoNext
                                ? () {
                                    setState(() {
                                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                                    });
                                    _load();
                                  }
                                : null,
                            icon: Icon(Icons.chevron_right, color: canGoNext ? Colors.white : Colors.white24),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 2.2,
                    children: weekdays
                        .map(
                          (d) => Center(
                            child: Text(
                              d,
                              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.0,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      ...List.generate(firstDayWeekday % 7, (_) => const SizedBox.shrink()),
                      ...List.generate(daysInMonth, (index) {
                        final day = index + 1;
                        final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                        final dateKey = _formatDate(date);
                        final isSelected = _selectedDate.year == date.year &&
                            _selectedDate.month == date.month &&
                            _selectedDate.day == date.day;
                        final isPast = date.isBefore(todayDate);
                        final isBeyondWindow = date.isAfter(bookingWindowEnd);
                        final booked = _bookedByDate[dateKey] ?? 0;
                        final reqStatus = _requestStatusByDate[dateKey];
                        final isApprovedOff = reqStatus == 'Approved';
                        final isPending = reqStatus == 'Pending';
                        final closure = _closureByDate[dateKey];
                        final isClosed = closure?['isClosed'] == true;
                        final isHolidayClosed = closure?['closureStatus']?.toString() == 'closed_holiday';

                        Color bg;
                        Color fg;
                        if (isSelected) {
                          bg = isClosed ? _closedHolidayFill : _kGold;
                          fg = Colors.white;
                        } else if (isPast || isBeyondWindow) {
                          bg = Colors.white12;
                          fg = Colors.white38;
                        } else if (isClosed) {
                          bg = isHolidayClosed ? _closedHolidayFill : _closedWeeklyFill;
                          fg = isHolidayClosed ? _closedHolidayText : Colors.white54;
                        } else if (isApprovedOff) {
                          bg = Colors.white12;
                          fg = Colors.white38;
                        } else if (booked > 0) {
                          bg = Colors.white;
                          fg = Colors.black;
                        } else {
                          bg = const Color(0xFF2A2A2A);
                          fg = Colors.white;
                        }

                        return GestureDetector(
                          onTap: () => _onDayTap(date, isPast: isPast),
                          child: Container(
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(8),
                              border: isPending
                                  ? Border.all(color: _kGold, width: 2)
                                  : (reqStatus == 'Rejected' || reqStatus == 'Expired'
                                      ? Border.all(color: Colors.orange, width: 1)
                                      : null),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$day',
                                  style: TextStyle(
                                    color: fg,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                if (booked > 0 && !isApprovedOff)
                                  Text(
                                    '$booked',
                                    style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 9),
                                  ),
                                if (isPending)
                                  const Text('*', style: TextStyle(color: _kGold, fontSize: 10)),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: const [
                      _LegendDot(color: Colors.white, label: 'Has bookings'),
                      _LegendDot(color: Color(0xFF3A1F1F), label: 'Closed'),
                      _LegendDot(color: _kGold, label: 'Pending off'),
                      _LegendDot(color: Colors.white38, label: 'Approved off / unavailable'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Appointments · ${_formatDate(_selectedDate)}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (dayAppointments.isEmpty)
              const Text('No appointments on this date.', style: TextStyle(color: Colors.white54))
            else
              ...dayAppointments.map((appt) {
                final isGroup = appt['is_group'] == true;
                final label = appt['display_title']?.toString() ?? 'Customer';
                final timeLabel = (appt['time_range']?.toString().isNotEmpty ?? false)
                    ? appt['time_range']!.toString()
                    : formatTo12Hour(appt['start_time']?.toString() ?? '');
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$label · $timeLabel · ${appt['status']}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (isGroup)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _kGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kGold),
                          ),
                          child: Text(
                            'Group',
                            style: const TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
