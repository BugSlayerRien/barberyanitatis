import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'time_slot_page.dart';
import 'api_config.dart';
import 'time_format_utils.dart';

class CalendarPage extends StatefulWidget {
  final int barberId;
  final String barberName;
  final int? rescheduleAppointmentId;
  final int? reschedulesRemaining;

  const CalendarPage({
    required this.barberId,
    required this.barberName,
    this.rescheduleAppointmentId,
    this.reschedulesRemaining,
    super.key,
  });

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _DayAvailability {
  const _DayAvailability({
    required this.availableCount,
    required this.bookedCount,
    required this.totalSlots,
    required this.isClosed,
    required this.closureStatus,
    required this.closureReason,
    required this.closureMessage,
  });

  final int availableCount;
  final int bookedCount;
  final int totalSlots;
  final bool isClosed;
  final String closureStatus;
  final String closureReason;
  final String closureMessage;

  factory _DayAvailability.fromJson(Map<String, dynamic> row) {
    return _DayAvailability(
      availableCount: _asInt(row['availableCount']),
      bookedCount: _asInt(row['bookedCount']),
      totalSlots: _asInt(row['totalSlots']),
      isClosed: row['isClosed'] == true,
      closureStatus: row['closureStatus']?.toString() ?? 'open',
      closureReason: row['closureReason']?.toString() ?? '',
      closureMessage: row['closureMessage']?.toString() ?? '',
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse('$value') ?? 0;
  }
}

class _CalendarPageState extends State<CalendarPage> {
  static const int _bookingWindowDays = 30;
  static const Color _closedHolidayFill = Color(0xFF3A1F1F);
  static const Color _closedHolidayText = Color(0xFFFFB4B4);
  static const Color _closedWeeklyFill = Color(0xFF1C1C1C);

  String get _pageTitle =>
      widget.rescheduleAppointmentId != null ? 'Reschedule' : 'Select Date';

  late DateTime _selectedDate;
  late DateTime _currentMonth;
  int _availableSlots = 0;
  int _totalSlots = 0;
  int _bookedSlots = 0;
  bool _selectedIsClosed = false;
  String _selectedClosureMessage = '';
  String _selectedClosureReason = '';
  bool _loadingSlots = false;
  bool _loadingMonthAvailability = false;
  bool _continuing = false;
  Map<String, _DayAvailability> _dayByDate = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadMonthAvailability();
    _fetchSlotCount();
  }

  Future<void> _loadMonthAvailability() async {
    setState(() => _loadingMonthAvailability = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'availabilityByBarberMonth',
          'barberID': widget.barberId,
          'year': _currentMonth.year,
          'month': _currentMonth.month,
        }),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        final rows = (data['availability'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        final mapped = <String, _DayAvailability>{};
        for (final row in rows) {
          final key = row['slotDate']?.toString() ?? '';
          if (key.isNotEmpty) {
            mapped[key] = _DayAvailability.fromJson(row);
          }
        }

        if (!mounted) return;
        setState(() {
          _dayByDate = mapped;
        });
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _loadingMonthAvailability = false);
      }
    }
  }

  Future<void> _fetchSlotCount() async {
    setState(() => _loadingSlots = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listByBarberDate',
          'barberID': widget.barberId,
          'slotDate': _formatDate(_selectedDate),
        }),
      );

      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};
      if (response.statusCode == 200) {
        final isClosed = data['isClosed'] == true;
        final closureMessage = data['closureMessage']?.toString() ?? '';
        final closureReason = data['closureReason']?.toString() ?? '';

        if (isClosed) {
          setState(() {
            _selectedIsClosed = true;
            _selectedClosureMessage = closureMessage.isNotEmpty
                ? closureMessage
                : "We're closed this day.";
            _selectedClosureReason = closureReason;
            _availableSlots = 0;
            _totalSlots = 0;
            _bookedSlots = 0;
          });
          return;
        }

        final slots = (data['slots'] as List<dynamic>? ?? []);
        final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final now = DateTime.now();
        final availableFromPayload = data['availableCount'];
        final bookedFromPayload = data['bookedCount'];
        final totalFromPayload = data['totalSlots'];

        int available;
        int booked;
        int total;
        if (availableFromPayload != null && bookedFromPayload != null && totalFromPayload != null) {
          available = _DayAvailability._asInt(availableFromPayload);
          booked = _DayAvailability._asInt(bookedFromPayload);
          total = _DayAvailability._asInt(totalFromPayload);
        } else {
          available = slots.where((slot) {
            final row = Map<String, dynamic>.from(slot as Map);
            final status = row['status']?.toString().toLowerCase() ?? '';
            if (status != 'available') {
              return false;
            }
            final slotTime = row['slot_time']?.toString() ?? '';
            final slotDateTime = tryParseSlotDateTime(date: selectedDay, time: slotTime);
            return slotDateTime != null && slotDateTime.isAfter(now);
          }).length;
          booked = slots.where((slot) {
            final row = Map<String, dynamic>.from(slot as Map);
            final status = row['status']?.toString().toLowerCase() ?? '';
            return status == 'booked';
          }).length;
          total = slots.length;
        }

        setState(() {
          _selectedIsClosed = false;
          _selectedClosureMessage = '';
          _selectedClosureReason = '';
          _availableSlots = available;
          _totalSlots = total;
          _bookedSlots = booked;
        });
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) {
        setState(() => _loadingSlots = false);
      }
    }
  }

  void _onDayTapped({
    required DateTime date,
    required bool inBookingWindow,
    required bool isPast,
    required bool isBeyondWindow,
    required _DayAvailability? dayInfo,
  }) {
    final isClosed = dayInfo?.isClosed == true;

    if (isPast) {
      return;
    }

    if (isBeyondWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can book up to $_bookingWindowDays days in advance.'),
        ),
      );
      return;
    }

    if (isClosed) {
      setState(() => _selectedDate = date);
      _fetchSlotCount();
      final message = (dayInfo?.closureMessage.isNotEmpty == true)
          ? dayInfo!.closureMessage
          : "We're closed this day.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (inBookingWindow) {
      setState(() => _selectedDate = date);
      _fetchSlotCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showInitialSkeleton = _loadingMonthAvailability && _dayByDate.isEmpty;
    if (showInitialSkeleton) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(_pageTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: _buildCalendarSkeleton(),
      );
    }

    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final bookingWindowEnd = todayDate.add(Duration(days: _bookingWindowDays - 1));
    final currentMonthKey = DateTime(today.year, today.month);
    final canGoPrev = _currentMonth.isAfter(currentMonthKey);
    final slotsBooked = _bookedSlots.clamp(0, _totalSlots > 0 ? _totalSlots : _bookedSlots);
    final slotsOpen = _availableSlots.clamp(0, _totalSlots > 0 ? _totalSlots : _availableSlots);
    final usageColor = _slotUsageColor(slotsBooked, _totalSlots);
    final slotsSummaryLabel = _totalSlots > 0
        ? '$slotsBooked of $_totalSlots slots booked · $slotsOpen open'
        : (_selectedIsClosed ? 'Closed' : 'No slots');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_pageTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.rescheduleAppointmentId != null && widget.reschedulesRemaining != null
                  ? 'Pick a new date. ${widget.reschedulesRemaining} reschedule(s) left. '
                  : 'Book from today through ${_formatWindowEnd(bookingWindowEnd)} ($_bookingWindowDays days). '
              'White days have open times with ${_barberNameLabel()}. Red-tinted days are closed. Gray days are past, outside the window, or fully booked.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
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
                                    setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1));
                                    _loadMonthAvailability();
                                  }
                                : null,
                            icon: Icon(Icons.chevron_left, color: canGoPrev ? Colors.white : Colors.white24),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1));
                              _loadMonthAvailability();
                            },
                            icon: const Icon(Icons.chevron_right, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, box) {
                      final width = box.maxWidth;
                      final daySpacing = width < 360 ? 4.0 : 8.0;
                      final cellWidth = (width - (daySpacing * 6)) / 7;
                      final weekdayAspect = (cellWidth / 24).clamp(1.0, 2.4);
                      final dayAspect = (cellWidth / (width < 360 ? 36 : 42)).clamp(0.8, 1.3);

                      return Column(
                        children: [
                          GridView.count(
                            crossAxisCount: 7,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: weekdayAspect,
                            children: List.generate(
                              7,
                              (index) => Center(
                                child: Text(
                                  weekdays[index],
                                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          GridView.count(
                            crossAxisCount: 7,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            childAspectRatio: dayAspect,
                            mainAxisSpacing: daySpacing,
                            crossAxisSpacing: daySpacing,
                            children: [
                              ...List.generate(
                                firstDayWeekday % 7,
                                (index) => const SizedBox.shrink(),
                              ),
                              ...List.generate(daysInMonth, (index) {
                                final day = index + 1;
                                final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                                final dateKey = _formatDate(date);
                                final dayInfo = _dayByDate[dateKey];
                                final isSelected = _selectedDate.day == day &&
                                    _selectedDate.month == _currentMonth.month &&
                                    _selectedDate.year == _currentMonth.year;
                                final isPast = date.isBefore(todayDate);
                                final isBeyondWindow = date.isAfter(bookingWindowEnd);
                                final isClosed = dayInfo?.isClosed == true;
                                final availableForDate = dayInfo?.availableCount ?? 0;
                                final inBookingWindow = !isPast && !isBeyondWindow;
                                final hasOpenSlots = !isClosed && availableForDate > 0;
                                final isHolidayClosed = dayInfo?.closureStatus == 'closed_holiday';

                                Color fill;
                                Color textColor;
                                Border? border;
                                if (isSelected) {
                                  fill = isClosed ? _closedHolidayFill : const Color(0xFFA99941);
                                  textColor = Colors.white;
                                  border = isClosed
                                      ? Border.all(color: const Color(0xFFFF8A80), width: 1.5)
                                      : null;
                                } else if (isPast || isBeyondWindow) {
                                  fill = Colors.white12;
                                  textColor = Colors.white38;
                                  border = Border.all(color: Colors.white12);
                                } else if (isClosed) {
                                  fill = isHolidayClosed ? _closedHolidayFill : _closedWeeklyFill;
                                  textColor = isHolidayClosed ? _closedHolidayText : Colors.white54;
                                  border = Border.all(
                                    color: isHolidayClosed
                                        ? const Color(0x66DC5050)
                                        : Colors.white12,
                                  );
                                } else if (hasOpenSlots) {
                                  fill = Colors.white;
                                  textColor = Colors.black;
                                } else {
                                  fill = const Color(0xFF2A2A2A);
                                  textColor = Colors.white70;
                                }

                                return GestureDetector(
                                  onTap: () => _onDayTapped(
                                    date: date,
                                    inBookingWindow: inBookingWindow,
                                    isPast: isPast,
                                    isBeyondWindow: isBeyondWindow,
                                    dayInfo: dayInfo,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: fill,
                                      borderRadius: BorderRadius.circular(8),
                                      border: border,
                                    ),
                                    child: Center(
                                      child: Text(
                                        day.toString(),
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: width < 360 ? 12 : 14,
                                          decoration: isClosed && !isPast ? TextDecoration.lineThrough : null,
                                          decorationColor: textColor.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: const [
                      _LegendDot(color: Colors.white, label: 'Open'),
                      _LegendDot(color: Color(0xFF3A1F1F), label: 'Closed', borderColor: Color(0x66DC5050)),
                      _LegendDot(color: Color(0xFF2A2A2A), label: 'Fully booked'),
                      _LegendDot(color: Colors.white12, label: 'Unavailable'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _selectedIsClosed ? _closedHolidayText : usageColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _selectedIsClosed ? 'Shop closed' : 'Slot availability',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      _loadingSlots
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Flexible(
                              child: Text(
                                _loadingMonthAvailability ? 'Checking dates...' : slotsSummaryLabel,
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedIsClosed ? const Color(0x66DC5050) : Colors.white,
                  width: 1,
                ),
              ),
              child: _loadingSlots
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                    )
                  : _selectedIsClosed
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Closed on ${_formatDate(_selectedDate)}',
                              style: const TextStyle(
                                color: _closedHolidayText,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _selectedClosureMessage.isNotEmpty
                                  ? _selectedClosureMessage
                                  : "We're closed this day.",
                              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                            if (_selectedClosureReason.isNotEmpty &&
                                !_selectedClosureMessage.contains(_selectedClosureReason)) ...[
                              const SizedBox(height: 4),
                              Text(
                                _selectedClosureReason,
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected: ${_formatDate(_selectedDate)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _totalSlots > 0
                                  ? '$slotsBooked of $_totalSlots slots booked'
                                  : 'No slots for this date',
                              style: TextStyle(
                                color: usageColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _totalSlots > 0
                                  ? '$slotsOpen of $_totalSlots still available with ${_barberNameLabel()}'
                                  : 'Pick another date to continue.',
                              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: (_continuing || _selectedIsClosed || _availableSlots <= 0)
                  ? null
                  : () async {
                      setState(() => _continuing = true);
                      final today = DateTime.now();
                      final minDate = DateTime(today.year, today.month, today.day);
                      final maxDate = minDate.add(Duration(days: _bookingWindowDays - 1));
                      if (_selectedDate.isBefore(minDate)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a valid date.')),
                        );
                        if (mounted) {
                          setState(() => _continuing = false);
                        }
                        return;
                      }
                      if (_selectedDate.isAfter(maxDate)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('You can only book within the next $_bookingWindowDays days.')),
                        );
                        if (mounted) {
                          setState(() => _continuing = false);
                        }
                        return;
                      }
                      if (_selectedIsClosed) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _selectedClosureMessage.isNotEmpty
                                  ? _selectedClosureMessage
                                  : "We're closed this day.",
                            ),
                          ),
                        );
                        if (mounted) {
                          setState(() => _continuing = false);
                        }
                        return;
                      }
                      if (_availableSlots <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No open times left on this date. Please pick another date.')),
                        );
                        if (mounted) {
                          setState(() => _continuing = false);
                        }
                        return;
                      }
                      final slotResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => TimeSlotPage(
                            barberId: widget.barberId,
                            barberName: widget.barberName,
                            selectedDate: _selectedDate,
                            rescheduleAppointmentId: widget.rescheduleAppointmentId,
                            reschedulesRemaining: widget.reschedulesRemaining,
                          ),
                        ),
                      );
                      if (mounted) {
                        setState(() => _continuing = false);
                      }
                      if (widget.rescheduleAppointmentId != null &&
                          slotResult == true &&
                          context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white24,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
                shadowColor: Colors.white.withOpacity(0.4),
              ),
              child: _continuing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      _selectedIsClosed ? 'Closed — pick another date' : 'Continue',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: (_selectedIsClosed || _availableSlots <= 0) ? Colors.white54 : Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Color _slotUsageColor(int booked, int total) {
    if (total <= 0) return Colors.white70;
    final ratio = booked / total;
    if (ratio >= 0.8) return const Color(0xFFFF8A80);
    if (ratio >= 0.5) return const Color(0xFFFFD54F);
    return const Color(0xFF81C784);
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatWindowEnd(DateTime end) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[end.month - 1]} ${end.day}';
  }

  String _barberNameLabel() {
    final name = widget.barberName.trim();
    return name.isEmpty ? 'this barber' : name;
  }

  Widget _buildCalendarSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 240,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
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
              children: [
                Container(
                  width: double.infinity,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: 35,
                  itemBuilder: (_, __) => Container(
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.borderColor,
  });

  final Color color;
  final String label;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: borderColor ?? Colors.white24),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
