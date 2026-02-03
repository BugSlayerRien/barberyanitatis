import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'payment_page.dart';
import 'api_config.dart';
import 'user_session.dart';

class TimeSlotPage extends StatefulWidget {
  final int barberId;
  final String barberName;
  final DateTime selectedDate;

  const TimeSlotPage({required this.barberId, required this.barberName, required this.selectedDate, super.key});

  @override
  State<TimeSlotPage> createState() => _TimeSlotPageState();
}

class _TimeSlotPageState extends State<TimeSlotPage> {
  String? _selectedTime;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _slots = [];
  Map<String, dynamic>? _defaultService;

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadDefaultService();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listByBarberDate',
          'barberID': widget.barberId,
          'slotDate': _formatDate(widget.selectedDate),
        }),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load slots.';
          _loading = false;
        });
        return;
      }

      final slots = (data['slots'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final normalized = _normalizeSlots(slots.isNotEmpty ? slots : _buildDefaultSlots());

      setState(() {
        _slots = normalized;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load slots: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadDefaultService() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/services.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'list'}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        return;
      }

      final services = (data['services'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final haircutService = services.firstWhere(
        (service) => (service['category']?.toString() ?? '').toLowerCase() == 'haircut',
        orElse: () => services.isNotEmpty ? services.first : <String, dynamic>{},
      );

      if (mounted) {
        setState(() {
          _defaultService = haircutService.isNotEmpty ? haircutService : null;
        });
      }
    } catch (_) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Select Time', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Barber Info
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('For ${_formatDisplayDate(widget.selectedDate)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(
                            widget.barberName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Title
            const Text(
              'Available Times',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (UserSession.selectedStyleName != null || UserSession.selectedVariantId != null) ...[
              const Text('Selected Haircut', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  UserSession.selectedStyleName ?? 'Selected haircut',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (_loading)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_error != null)
              Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
            else if (_slots.isEmpty)
              const Center(child: Text('No available slots for this date.', style: TextStyle(color: Colors.white70)))
            else
              SizedBox(
                height: 260,
                child: ListView.separated(
                  itemCount: _slots.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final slot = _slots[index];
                    final time = slot['slot_time']?.toString() ?? '';
                    final isSelected = _selectedTime == time;
                    final status = slot['status']?.toString() ?? 'Available';
                    final normalized = status.toLowerCase();
                    final isAvailable = !(normalized == 'holiday' || normalized == 'unavailable' || normalized == 'booked');
                    return GestureDetector(
                      onTap: isAvailable ? () => setState(() => _selectedTime = time) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 50,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white
                              : (isAvailable ? const Color(0xFF1A1A1A) : const Color(0xFF121212)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white10,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            time,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.black
                                  : (isAvailable ? Colors.white : Colors.white38),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 32),

            // Book Button
            ElevatedButton(
              onPressed: _selectedTime != null
                  ? () async {
                      if (UserSession.userId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please log in again.')),
                        );
                        return;
                      }
                      if (UserSession.selectedVariantId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a hairstyle before booking.')),
                        );
                        return;
                      }
                      if (_defaultService == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No haircut service configured.')),
                        );
                        return;
                      }

                      final serviceId = _defaultService!['service_id'] as int;
                      final price = double.tryParse(_defaultService!['base_price']?.toString() ?? '') ?? 0;

                      final startTime = _selectedTime ?? '';
                      final duration = int.tryParse(_defaultService!['base_duration']?.toString() ?? '') ?? 0;
                      final endTime = _addMinutes(startTime, duration);

                      final response = await http.post(
                        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'action': 'create',
                          'userID': UserSession.userId,
                          'barberID': widget.barberId,
                          'appointmentDate': _formatDate(widget.selectedDate),
                          'startTime': startTime,
                          'endTime': endTime,
                          'serviceIDs': [serviceId],
                          'variantID': UserSession.selectedVariantId,
                        }),
                      );

                      if (!context.mounted) return;
                      if (response.statusCode != 201) {
                        final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['error']?.toString() ?? 'Booking failed.')),
                        );
                        return;
                      }

                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PaymentPage(
                          barberName: widget.barberName,
                          date: _formatDisplayDate(widget.selectedDate),
                          time: _selectedTime ?? '',
                          amount: price.round(),
                          haircutName: UserSession.selectedStyleName ?? 'Haircut',
                        ),
                      ));
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
                shadowColor: Colors.white.withOpacity(0.4),
              ),
              child: const Text(
                'Confirm Booking',
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

  String _formatDisplayDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _addMinutes(String time, int minutes) {
    if (time.isEmpty) {
      return time;
    }
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

  List<Map<String, dynamic>> _buildDefaultSlots() {
    final times = <String>[];
    for (var hour = 9; hour <= 18; hour++) {
      times.add('${hour.toString().padLeft(2, '0')}:00');
    }
    return times
        .map((time) => {
              'slot_time': time,
              'status': 'Available',
            })
        .toList();
  }

  List<Map<String, dynamic>> _normalizeSlots(List<Map<String, dynamic>> slots) {
    final Map<String, Map<String, dynamic>> byTime = {};
    for (final slot in slots) {
      final time = slot['slot_time']?.toString() ?? '';
      if (time.isEmpty) {
        continue;
      }
      final status = slot['status']?.toString() ?? 'Available';
      if (!byTime.containsKey(time)) {
        byTime[time] = slot;
      } else {
        final existing = byTime[time];
        final existingStatus = existing?['status']?.toString() ?? 'Available';
        if (existingStatus.toLowerCase() == 'available' && status.toLowerCase() != 'available') {
          byTime[time] = slot;
        }
      }
    }
    final sortedKeys = byTime.keys.toList()..sort();
    return sortedKeys.map((time) => byTime[time]!).toList();
  }
}
