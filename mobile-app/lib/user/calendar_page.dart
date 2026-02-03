import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'time_slot_page.dart';
import 'api_config.dart';

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
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _fetchSlotCount();
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
        final available = slots.where((slot) => (slot as Map)['status'] == 'Available').length;
        setState(() {
          _availableSlots = available;
          _totalSlots = slots.length;
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
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday;
    final weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final today = DateTime.now();
    final currentMonthKey = DateTime(today.year, today.month);
    final canGoPrev = _currentMonth.isAfter(currentMonthKey);
    final slotsTaken = (_totalSlots - _availableSlots).clamp(0, _totalSlots);
    final takenColor = slotsTaken > 5 ? Colors.yellow : Colors.red;

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
                                ? () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1))
                                : null,
                            icon: Icon(Icons.chevron_left, color: canGoPrev ? Colors.white : Colors.white24),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1)),
                            icon: const Icon(Icons.chevron_right, color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.2,
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
                    childAspectRatio: 1,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      ...List.generate(
                        firstDayWeekday % 7,
                        (index) => const SizedBox.shrink(),
                      ),
                      ...List.generate(daysInMonth, (index) {
                        final day = index + 1;
                        final date = DateTime(_currentMonth.year, _currentMonth.month, day);
                        final isSelected = _selectedDate.day == day &&
                            _selectedDate.month == _currentMonth.month &&
                            _selectedDate.year == _currentMonth.year;
                        final isPast = date.isBefore(DateTime(today.year, today.month, today.day));

                        return GestureDetector(
                          onTap: isPast
                              ? null
                              : () {
                                  setState(() => _selectedDate = date);
                                  _fetchSlotCount();
                                },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFA99941) : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: isPast ? Border.all(color: Colors.black12) : null,
                            ),
                            child: Center(
                              child: Text(
                                day.toString(),
                                style: TextStyle(
                                  color: isPast
                                      ? Colors.black26
                                      : (isSelected ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
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
                          : Text('$slotsTaken', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      : Text('$slotsTaken', style: TextStyle(color: takenColor, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                final today = DateTime.now();
                final minDate = DateTime(today.year, today.month, today.day);
                if (_selectedDate.isBefore(minDate)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a valid date.')),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TimeSlotPage(
                      barberId: widget.barberId,
                      barberName: widget.barberName,
                      selectedDate: _selectedDate,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
                shadowColor: Colors.white.withOpacity(0.4),
              ),
              child: const Text(
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
}
