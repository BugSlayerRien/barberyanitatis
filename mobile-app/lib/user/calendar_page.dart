import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'time_slot_page.dart';
import 'api_config.dart';
import 'time_format_utils.dart';

class CalendarPage extends StatefulWidget {
  final int barberId;
  final String barberName;

  const CalendarPage({required this.barberId, required this.barberName, super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selectedDate;
  late DateTime _currentMonth;
  int _availableSlots = 0;
  int _totalSlots = 0;
  int _bookedSlots = 0;
  bool _loadingSlots = false;
  bool _loadingMonthAvailability = false;
  bool _continuing = false;
  Map<String, int> _availableByDate = {};

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

        final mapped = <String, int>{};
        for (final row in rows) {
          final key = row['slotDate']?.toString() ?? '';
          final count = row['availableCount'] is int
              ? row['availableCount'] as int
              : int.tryParse('${row['availableCount']}') ?? 0;
          if (key.isNotEmpty) {
            mapped[key] = count;
          }
        }

        if (!mounted) return;
        setState(() {
          _availableByDate = mapped;
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
        final slots = (data['slots'] as List<dynamic>? ?? []);
        final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final now = DateTime.now();
        final available = slots.where((slot) {
          final row = Map<String, dynamic>.from(slot as Map);
          final status = row['status']?.toString().toLowerCase() ?? '';
          if (status != 'available') {
            return false;
          }
          final slotTime = row['slot_time']?.toString() ?? '';
          final slotDateTime = tryParseSlotDateTime(date: selectedDay, time: slotTime);
          return slotDateTime != null && slotDateTime.isAfter(now);
        }).length;
        final booked = slots.where((slot) {
          final row = Map<String, dynamic>.from(slot as Map);
          final status = row['status']?.toString().toLowerCase() ?? '';
          return status == 'booked';
        }).length;
        setState(() {
          _availableSlots = available;
          _totalSlots = slots.length;
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

  @override
  Widget build(BuildContext context) {
    final showInitialSkeleton = _loadingMonthAvailability && _availableByDate.isEmpty;
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
          title: const Text('Select Date', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: _buildCalendarSkeleton(),
      );
    }

    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final bookingWindowEnd = todayDate.add(const Duration(days: 6));
    final currentMonthKey = DateTime(today.year, today.month);
    final canGoPrev = _currentMonth.isAfter(currentMonthKey);
    final slotsTaken = _bookedSlots.clamp(0, _totalSlots);
    final takenColor = slotsTaken > 5 ? Colors.yellow : Colors.red;
    final slotsTakenLabel = '$slotsTaken/$_totalSlots slots taken';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select Date', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select your preferred appointment date',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
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
                                final isSelected = _selectedDate.day == day &&
                                    _selectedDate.month == _currentMonth.month &&
                                    _selectedDate.year == _currentMonth.year;
                                final isPast = date.isBefore(todayDate);
                                final isBeyondWindow = date.isAfter(bookingWindowEnd);
                                final availableForDate = _availableByDate[dateKey] ?? 0;
                                final isEligible = !isPast && !isBeyondWindow && availableForDate > 0;

                                return GestureDetector(
                                  onTap: isEligible
                                      ? () {
                                          setState(() => _selectedDate = date);
                                          _fetchSlotCount();
                                        }
                                      : (isPast
                                          ? null
                                          : () {
                                              if (isBeyondWindow) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('You can book up to 7 days in advance.')),
                                                );
                                                return;
                                              }
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('No open times left on this date.')),
                                              );
                                            }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFFA99941)
                                          : (isEligible ? Colors.white : Colors.white12),
                                      borderRadius: BorderRadius.circular(8),
                                      border: !isEligible ? Border.all(color: Colors.white12) : null,
                                    ),
                                    child: Center(
                                      child: Text(
                                        day.toString(),
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : (isEligible ? Colors.black : Colors.white38),
                                          fontWeight: FontWeight.bold,
                                          fontSize: width < 360 ? 12 : 14,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: takenColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Slots taken',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                      _loadingSlots
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              _loadingMonthAvailability ? 'Checking dates...' : slotsTakenLabel,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Slots taken for ${_formatDate(_selectedDate)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  _loadingSlots
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(slotsTakenLabel, style: TextStyle(color: takenColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _continuing
                  ? null
                  : () async {
                      setState(() => _continuing = true);
                final today = DateTime.now();
                final minDate = DateTime(today.year, today.month, today.day);
                final maxDate = minDate.add(const Duration(days: 6));
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
                    const SnackBar(content: Text('You can only book within the next 7 days.')),
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
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TimeSlotPage(
                      barberId: widget.barberId,
                      barberName: widget.barberName,
                      selectedDate: _selectedDate,
                    ),
                  ),
                );
                if (mounted) {
                  setState(() => _continuing = false);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
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
                  : const Text(
                      'Continue',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
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
