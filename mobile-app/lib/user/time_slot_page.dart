import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'appointments_page.dart';
import 'payment_page.dart';
import 'api_config.dart';
import 'customer_api.dart';
import 'time_format_utils.dart';
import 'haircuts_list_page.dart';
import 'booking_guard.dart';
import 'user_session.dart';
import 'services/face_scan_service.dart';
import 'services/booking_draft_service.dart';
import 'widgets/shimmer_skeleton.dart';
import 'widgets/style_length_warning.dart';

class TimeSlotPage extends StatefulWidget {
  final int barberId;
  final String barberName;
  final DateTime selectedDate;
  final int? rescheduleAppointmentId;
  final int? reschedulesRemaining;

  const TimeSlotPage({
    required this.barberId,
    required this.barberName,
    required this.selectedDate,
    this.rescheduleAppointmentId,
    this.reschedulesRemaining,
    super.key,
  });

  @override
  State<TimeSlotPage> createState() => _TimeSlotPageState();
}

class _TimeSlotPageState extends State<TimeSlotPage> {
  bool get _isRescheduleMode =>
      widget.rescheduleAppointmentId != null && widget.rescheduleAppointmentId! > 0;

  static const double _shopLatitude = 14.5995;
  static const double _shopLongitude = 120.9842;
  static const int _appointmentDurationMinutes = 60;

  String? _selectedTime;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _slots = [];
  Map<String, dynamic>? _defaultService;

  /// Every service the shop offers on this channel.
  ///
  /// The list was fetched, one entry picked from it, and the rest thrown
  /// away -- so a shop could add Perm, see it saved, and never find a way for
  /// a customer to book it. The services table, the booking endpoint and
  /// appointment_details all supported more than one service already; only
  /// this screen did not offer the choice.
  List<Map<String, dynamic>> _services = const [];
  bool _servicesLoading = true;
  bool _loadingWeatherAdvice = false;
  String? _weatherSummary;
  /// Hour-of-day (0-23) -> rain probability % / temperature C for the selected
  /// date. Empty when the forecast call failed or returned no hourly series.
  Map<int, double> _hourlyRain = const {};
  Map<int, double> _hourlyTemp = const {};
  String? _timeAdvice;
  bool _bookingInFlight = false;
  late DateTime _activeDate;
  bool _autoShiftedDate = false;
  /// Optional note the customer can leave for the barber. Sent as
  /// specialInstructions on booking.php 'create' and shown to the barber on the
  /// appointment detail screen.
  final TextEditingController _noteController = TextEditingController();

  /// What the barber is told when the customer booked a cut their hair is too
  /// short for. Set when the grow-out warning was accepted; '' otherwise.
  String get _growOutNote => UserSession.growOutBookingNote?.trim() ?? '';

  /// The customer's own note with the grow-out line in front of it.
  ///
  /// Prepended rather than merged into the text field: the field is theirs to
  /// write and clear, and this has to reach the barber whether they write
  /// anything or not.
  String _instructionsForBooking() {
    final own = _noteController.text.trim();
    if (_growOutNote.isEmpty) return own;

    return own.isEmpty ? _growOutNote : '$_growOutNote\n\n$own';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _activeDate = _resolveActiveDate(widget.selectedDate);
    _autoShiftedDate = !_isSameDay(_activeDate, widget.selectedDate);
    _loadSlots();
    _loadDefaultService();
    _loadWeatherAndSuggestion();
    _maybeShowDateShiftNotice();
  }

  DateTime _resolveActiveDate(DateTime selected) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(selected.year, selected.month, selected.day);
    if (_isSameDay(selectedDay, today) && now.hour >= 20) {
      return selectedDay.add(const Duration(days: 1));
    }
    return selected;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _maybeShowDateShiftNotice() {
    if (!_autoShiftedDate) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('It\'s past closing time. Showing the next available date instead.')),
      );
    });
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
          'slotDate': _formatDate(_activeDate),
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
      final hasSelected = _selectedTime != null &&
          normalized.any((slot) => slot['slot_time']?.toString() == _selectedTime);

      setState(() {
        _slots = normalized;
        if (!hasSelected) {
          _selectedTime = null;
        }
        _loading = false;
      });
      _loadWeatherAndSuggestion();
    } catch (e) {
      setState(() {
        _error = 'Failed to load slots: $e';
        _loading = false;
      });
      _loadWeatherAndSuggestion();
    }
  }

  Future<void> _loadWeatherAndSuggestion() async {
    if (!mounted) {
      return;
    }

    if (!_isWithinWeatherForecastWindow(_activeDate)) {
      setState(() {
        _weatherSummary = null;
        _timeAdvice = null;
        _loadingWeatherAdvice = false;
      });
      return;
    }

    setState(() {
      _loadingWeatherAdvice = true;
    });

    final date = _formatDate(_activeDate);
    final availableSlots = _availableSlotsForAdvice();

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$_shopLatitude&longitude=$_shopLongitude'
          '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_mean'
          // Hourly series is what makes a per-slot recommendation possible: with
          // only the daily mean, every slot scored identically on weather and
          // the choice fell through to "nearest to midday" / earliest.
          '&hourly=precipitation_probability,temperature_2m'
          '&timezone=auto&start_date=$date&end_date=$date',
        ),
      );

      if (response.statusCode != 200 || response.body.isEmpty) {
        throw Exception('weather api error');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = data['daily'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final maxTemp = (daily['temperature_2m_max'] as List<dynamic>? ?? const [])
          .cast<dynamic>()
          .isNotEmpty
          ? double.tryParse('${(daily['temperature_2m_max'] as List<dynamic>).first}')
          : null;
      final minTemp = (daily['temperature_2m_min'] as List<dynamic>? ?? const [])
          .cast<dynamic>()
          .isNotEmpty
          ? double.tryParse('${(daily['temperature_2m_min'] as List<dynamic>).first}')
          : null;
      final rainChance = (daily['precipitation_probability_mean'] as List<dynamic>? ?? const [])
          .cast<dynamic>()
          .isNotEmpty
          ? double.tryParse('${(daily['precipitation_probability_mean'] as List<dynamic>).first}')
          : null;

      final hourly = data['hourly'] as Map<String, dynamic>? ?? <String, dynamic>{};
      _hourlyRain = _parseHourlySeries(hourly, 'precipitation_probability');
      _hourlyTemp = _parseHourlySeries(hourly, 'temperature_2m');

      final weatherSummary = _buildWeatherSummary(maxTemp, minTemp, rainChance);
      // The sentence is written from the same inputs that chose the slot, so
      // it cannot contradict the recommendation. It used to prefer a Gemini
      // sentence that was only checked for containing a digit, which let
      // through the wrong date format ("Best 2026-09-25" instead of "Best
      // today") and reasoning that argued against the slot it was naming --
      // "a good time to beat the afternoon heat" for a 1:00 PM booking.
      // Dropping it also takes a model round trip off a screen the customer
      // is waiting on.
      final advice = _buildHeuristicAdvice(
        maxTemp: maxTemp,
        rainChance: rainChance,
        availableSlots: availableSlots,
        allSlots: _slots,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _weatherSummary = weatherSummary;
        _timeAdvice = advice;
        _loadingWeatherAdvice = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _weatherSummary = 'Weather data is temporarily unavailable.';
        _timeAdvice = _buildHeuristicAdvice(
          maxTemp: null,
          rainChance: null,
          availableSlots: availableSlots,
          allSlots: _slots,
        );
        _loadingWeatherAdvice = false;
      });
    }
  }

  /// Open-Meteo daily forecast is reliable near-term; hide advice beyond 7 days.
  bool _isWithinWeatherForecastWindow(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final daysAhead = target.difference(today).inDays;
    return daysAhead >= 0 && daysAhead <= 7;
  }

  String _bestTimePrefix() {
    if (_isSameDay(_activeDate, DateTime.now())) {
      return 'Best today';
    }
    return 'Best for ${_formatDisplayDate(_activeDate)}';
  }

  List<Map<String, dynamic>> _availableSlotsForAdvice() {
    return _slots.where(_isSlotBookable).toList();
  }

  String _buildWeatherSummary(double? maxTemp, double? minTemp, double? rainChance) {
    final high = maxTemp != null ? '${maxTemp.toStringAsFixed(0)}C' : 'n/a';
    final low = minTemp != null ? '${minTemp.toStringAsFixed(0)}C' : 'n/a';
    final rain = rainChance != null ? '${rainChance.toStringAsFixed(0)}%' : 'n/a';
    final dayLabel = _isSameDay(_activeDate, DateTime.now())
        ? 'today'
        : _formatDisplayDate(_activeDate);
    return 'Forecast for $dayLabel: high $high, low $low, rain chance $rain.';
  }

  String _buildHeuristicAdvice({
    required double? maxTemp,
    required double? rainChance,
    required List<Map<String, dynamic>> availableSlots,
    required List<Map<String, dynamic>> allSlots,
  }) {
    if (availableSlots.isEmpty) {
      return 'No open times are available now. Please pick another date or barber.';
    }

    final preferred = _pickMostBufferedSlot(
      availableSlots: availableSlots,
      allSlots: allSlots,
      maxTemp: maxTemp,
      rainChance: rainChance,
    );

    final displayTime = preferred['display_time']?.toString() ?? preferred['slot_time']?.toString() ?? '';
    final prefix = _bestTimePrefix();
    if (rainChance != null && rainChance >= 60) {
      return '$prefix: $displayTime. It keeps distance from occupied times and lowers rain-travel risk.';
    }
    if (maxTemp != null && maxTemp >= 33) {
      return '$prefix: $displayTime. It stays buffered from occupied times and avoids hotter commute hours.';
    }
    return '$prefix: $displayTime. It is the most buffered slot from currently taken times.';
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

      if (mounted) {
        setState(() {
          _services = services;
          _servicesLoading = false;
        });
      }

      final selectedServiceId = UserSession.selectedServiceId;
      if (selectedServiceId != null) {
        for (final service in services) {
          final serviceId = int.tryParse(service['service_id']?.toString() ?? '');
          if (serviceId == selectedServiceId) {
            if (mounted) {
              setState(() {
                _defaultService = service;
              });
            }
            UserSession.selectedServiceId = serviceId;
            return;
          }
        }
      }

      final haircutService = services.firstWhere(
        (service) => (service['category']?.toString() ?? '').toLowerCase() == 'haircut',
        orElse: () => services.isNotEmpty ? services.first : <String, dynamic>{},
      );

      if (mounted) {
        setState(() {
          _defaultService = haircutService.isNotEmpty ? haircutService : null;
        });
      }
      UserSession.selectedServiceId = int.tryParse(haircutService['service_id']?.toString() ?? '');
    } catch (_) {
      if (mounted) {
        setState(() => _servicesLoading = false);
      }
    }
  }

  /// What the customer is booking, and what it costs.
  ///
  /// A single service renders as a line rather than a one-option dropdown:
  /// asking someone to choose between one thing is noise.
  Widget _buildServicePicker() {
    if (_servicesLoading) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
          ),
        ),
      );
    }
    if (_services.isEmpty) return const SizedBox.shrink();

    final selectedId = int.tryParse(
      _defaultService?['service_id']?.toString() ?? '',
    );

    if (_services.length == 1) {
      return _serviceSummary(_services.first);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final service in _services) ...[
          _serviceOption(service, isSelected: _serviceId(service) == selectedId),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  int _serviceId(Map<String, dynamic> service) =>
      int.tryParse(service['service_id']?.toString() ?? '') ?? 0;

  String _servicePrice(Map<String, dynamic> service) {
    final price = double.tryParse(service['base_price']?.toString() ?? '') ?? 0;

    return '\u20b1${price.toStringAsFixed(0)}';
  }

  /// The service's own duration, shown but not used for the slot.
  ///
  /// Every appointment occupies one hour: that is how availability, the
  /// suggestion engine and the barber's schedule all count. Showing the real
  /// figure keeps the price honest without quietly changing what a slot is.
  String _serviceDuration(Map<String, dynamic> service) {
    final minutes = int.tryParse(service['base_duration']?.toString() ?? '') ?? 0;

    return minutes > 0 ? 'about $minutes min' : '';
  }

  Widget _serviceSummary(Map<String, dynamic> service) {
    final duration = _serviceDuration(service);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service['service_name']?.toString() ?? 'Service',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (duration.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    duration,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Text(
            _servicePrice(service),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceOption(Map<String, dynamic> service, {required bool isSelected}) {
    final duration = _serviceDuration(service);
    final description = service['description']?.toString().trim() ?? '';

    return Material(
      color: isSelected ? const Color(0xFF1E1E1E) : const Color(0xFF141414),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _defaultService = service);
          UserSession.selectedServiceId = _serviceId(service);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white : Colors.white12,
              width: isSelected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: isSelected ? Colors.white : Colors.white38,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service['service_name']?.toString() ?? 'Service',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (duration.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        duration,
                        style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _servicePrice(service),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        title: Text(
          _isRescheduleMode ? 'Reschedule' : 'Select Time',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isRescheduleMode && widget.reschedulesRemaining != null) ...[
              Text(
                '${widget.reschedulesRemaining} reschedule(s) remaining for this appointment.',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
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
                          Text('For ${_formatDisplayDate(_activeDate)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
            if (_isWithinWeatherForecastWindow(_activeDate)) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.wb_sunny_outlined, color: Colors.white70, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _loadingWeatherAdvice
                        ? Text(
                            'Checking weather for ${_formatDisplayDate(_activeDate)} and suggested best time...',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _weatherSummary ?? 'Weather insight unavailable.',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _timeAdvice ?? 'Pick any open time that works for you.',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            ],

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
              _buildSlotsSkeleton()
            else if (_error != null)
              Center(
                child: Column(
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadSlots,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (_slots.isEmpty)
              const Center(child: Text('No slots available for this date.', style: TextStyle(color: Colors.white70)))
            else if (!_hasBookableSlots)
              const Center(
                child: Text(
                  'No bookable times left for this date.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth;
                  final crossAxisCount = width >= 700
                      ? 5
                      : width >= 560
                          ? 4
                          : width >= 390
                              ? 3
                              : 2;
                  final itemWidth = (width - ((crossAxisCount - 1) * 10)) / crossAxisCount;
                  final childAspectRatio = (itemWidth / 44).clamp(1.9, 3.6);

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: _slots.length,
                    itemBuilder: (context, index) {
                      final slot = _slots[index];
                      final canonicalTime = slot['slot_time']?.toString() ?? '';
                      final displayTime = slot['display_time']?.toString() ?? canonicalTime;
                      final isSelected = _selectedTime == canonicalTime;
                      final isAvailable = _isSlotBookable(slot);
                      final isFull = _isSlotFull(slot);
                      final availabilityColor = _slotAvailabilityColor(slot);
                      return GestureDetector(
                        onTap: isAvailable ? () => setState(() => _selectedTime = canonicalTime) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : (isAvailable
                                    ? availabilityColor.withOpacity(0.28)
                                    : (isFull
                                        ? availabilityColor.withOpacity(0.22)
                                        : const Color(0xFF121212))),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : (isAvailable
                                      ? availabilityColor.withOpacity(0.7)
                                      : (isFull
                                          ? availabilityColor.withOpacity(0.6)
                                          : Colors.white10)),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              displayTime,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : (isAvailable
                                        ? Colors.white
                                        : (isFull ? Colors.white70 : Colors.white38)),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            if (!_loading && _error == null && _slots.isNotEmpty && !_hasBookableSlots) ...[
              const SizedBox(height: 16),
              const Text(
                'All time slots for this date are already taken or have already passed.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _openTryHaircut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Try Haircut'),
              ),
            ],
            if (!_isRescheduleMode && _growOutNote.isNotEmpty) ...[
              const SizedBox(height: 24),
              // Shown, not hidden: the customer dismissed a warning to get
              // here, and they should see exactly what their barber will read
              // rather than find out at the chair.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x1FE0A23C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: GrowOutGoalBadge.color),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 14, color: GrowOutGoalBadge.color),
                        SizedBox(width: 6),
                        Text(
                          'Your barber will be told',
                          style: TextStyle(
                            color: GrowOutGoalBadge.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _growOutNote,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Rescheduling keeps the service the appointment already has;
            // offering to change it here would be a different booking.
            if (!_isRescheduleMode) ...[
              const SizedBox(height: 24),
              Text(
                _services.length > 1 ? 'Choose a service' : 'Service',
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              _buildServicePicker(),
            ],
            if (!_isRescheduleMode) ...[
              const SizedBox(height: 24),
              const Text(
                'Note for your barber (optional)',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 300,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'e.g. scissors only, sensitive scalp, keep the length on top',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  counterStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Book Button
            ElevatedButton(
              onPressed: _selectedTime != null && _hasBookableSlots && !_bookingInFlight
                  ? () async {
                      if (_bookingInFlight) {
                        return;
                      }
                      setState(() => _bookingInFlight = true);
                      try {
                      if (UserSession.userId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please log in again.')),
                        );
                        return;
                      }

                      final startTime = _selectedTime ?? '';
                      const duration = _appointmentDurationMinutes;
                      final endTime = _addMinutes(startTime, duration);

                      if (_isRescheduleMode) {
                        try {
                          final data = await CustomerApi.postDecoded('booking.php', {
                            'action': 'reschedule',
                            'appointmentID': widget.rescheduleAppointmentId,
                            'userID': UserSession.userId,
                            'appointmentDate': _formatDate(_activeDate),
                            'startTime': startTime,
                            'endTime': endTime,
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                data['message']?.toString() ?? 'Appointment rescheduled.',
                              ),
                            ),
                          );
                          Navigator.of(context).pop(true);
                          return;
                        } on CustomerApiException catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message)),
                          );
                          return;
                        }
                      }

                      if (UserSession.selectedVariantId == null) {
                        // Booking can start from a barber card (Favorite barber,
                        // Book again), which never passes through hairstyle
                        // selection. The old toast was a dead end: it refused the
                        // booking and left the customer on a screen with no way
                        // to satisfy it. Send them to pick a style, then they can
                        // come straight back to this time.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Pick a haircut to finish this booking.'),
                          ),
                        );
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const HaircutsListPage(),
                          ),
                        );
                        if (!context.mounted) return;
                        if (UserSession.selectedVariantId == null) return;
                      }
                      // No pre-check round trip: booking.php 'create' already
                      // rejects a second active appointment with 409, handled
                      // below. Asking first only added a wait before every
                      // booking to catch a case the server catches anyway.
                      final selectedDateTime = tryParseSlotDateTime(
                        date: _activeDate,
                        time: _selectedTime ?? '',
                      );
                      if (selectedDateTime == null || !isSlotBookableAt(selectedDateTime)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please choose a slot at least 1 hour ahead (next full hour after that).',
                            ),
                          ),
                        );
                        return;
                      }

                      if (_defaultService == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No haircut service configured.')),
                        );
                        return;
                      }

                      final serviceId = int.tryParse(_defaultService!['service_id']?.toString() ?? '') ?? 0;
                      if (serviceId <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid service configuration.')),
                        );
                        return;
                      }

                      final price = double.tryParse(_defaultService!['base_price']?.toString() ?? '') ?? 0;

                      late final Map<String, dynamic> bookingData;
                      try {
                        bookingData = await CustomerApi.postDecoded('booking.php', {
                          'action': 'create',
                          'userID': UserSession.userId,
                          'barberID': widget.barberId,
                          'appointmentDate': _formatDate(_activeDate),
                          'startTime': startTime,
                          'endTime': endTime,
                          'serviceIDs': [serviceId],
                          'variantID': UserSession.selectedVariantId,
                          'specialInstructions': _instructionsForBooking(),
                          ...FaceScanService.bookingPreviewPayload(),
                        }, okStatusCodes: {201});
                      } on CustomerApiException catch (e) {
                        if (!context.mounted) return;
                        if (e.statusCode == 409) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You already have an active appointment.')),
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                          );
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.message)),
                        );
                        return;
                      }
                      final appointmentId = int.tryParse(bookingData['appointmentID']?.toString() ?? '') ?? 0;
                      unawaited(BookingDraftService.clear());
                      // Analytics and preview linking are bookkeeping the
                      // customer never sees. Awaiting them held the payment
                      // screen behind two more round trips on a slow
                      // connection; they finish on their own.
                      if (appointmentId > 0 && UserSession.userId != null && UserSession.selectedVariantId != null) {
                        unawaited(AiFunnelService.trackBookingCreated(
                          scanSessionId: UserSession.ensureScanSessionId(),
                          userId: UserSession.userId!,
                          variantId: UserSession.selectedVariantId!,
                          appointmentId: appointmentId,
                          serviceId: serviceId,
                          estimatedMinutes: duration,
                          frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
                          sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
                          backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
                        ));
                        if (bookingData['previewsAttached'] != true) {
                          unawaited(
                            FaceScanService.attachPreviewsToAppointment(
                              appointmentId: appointmentId,
                              scanSessionId: UserSession.ensureScanSessionId(),
                              variantId: UserSession.selectedVariantId!,
                            ).catchError((Object e) {
                              // Silent: booking a Library haircut with no
                              // generated preview has nothing to link, so this
                              // warned on a perfectly successful booking.
                              debugPrint('Preview attach failed: $e');
                            }),
                          );
                        }
                      }

                      if (!context.mounted) return;

                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PaymentPage(
                          appointmentID: appointmentId,
                          barberName: widget.barberName,
                          date: _formatDisplayDate(_activeDate),
                          time: formatTo12Hour(_selectedTime ?? ''),
                          amount: price.round(),
                          haircutName: UserSession.selectedStyleName ?? 'Haircut',
                        ),
                      ));

                      // Leaving payment without paying used to strand the
                      // PendingPayment row and refuse every later attempt.
                      await BookingGuard.releaseIfUnpaid(
                        userId: UserSession.userId,
                        appointmentId: appointmentId,
                      );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Booking failed: $e')),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _bookingInFlight = false);
                        }
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 8,
                shadowColor: Colors.white.withOpacity(0.4),
              ),
              child: _bookingInFlight
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Text(
                      _isRescheduleMode ? 'Confirm Reschedule' : 'Confirm Booking',
                      style: const TextStyle(
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
    return shopHourlySlotTimesCanonical()
        .map((time) => {
              'slot_time': time,
              'display_time': _displayTime(time),
              'status': 'Available',
              'booked_count': 0,
              'capacity': 10,
            })
        .toList();
  }

  List<Map<String, dynamic>> _normalizeSlots(List<Map<String, dynamic>> slots) {
    final Map<String, Map<String, dynamic>> byTime = {};
    for (final slot in slots) {
      final time = _canonicalTime(slot['slot_time']?.toString() ?? '');
      if (time.isEmpty || !isShopHourlySlotTime(time)) {
        continue;
      }
      final status = slot['status']?.toString() ?? 'Available';
      if (!byTime.containsKey(time)) {
        byTime[time] = {
          ...slot,
          'slot_time': time,
          'display_time': _displayTime(time),
        };
      } else {
        final existing = byTime[time];
        final existingStatus = existing?['status']?.toString() ?? 'Available';
        final existingBooked = int.tryParse(existing?['booked_count']?.toString() ?? '') ?? 0;
        final incomingBooked = int.tryParse(slot['booked_count']?.toString() ?? '') ?? 0;
        if (existingStatus.toLowerCase() == 'available' && status.toLowerCase() != 'available') {
          byTime[time] = {
            ...slot,
            'slot_time': time,
            'display_time': _displayTime(time),
          };
        } else if (existingStatus.toLowerCase() == 'available' && status.toLowerCase() == 'available') {
          if (existing != null && incomingBooked > existingBooked) {
            byTime[time] = {
              ...existing,
              'booked_count': incomingBooked,
            };
          }
        }
      }
    }
    final normalized = <Map<String, dynamic>>[];
    for (final time in shopHourlySlotTimesCanonical()) {
      final slot = byTime[time];
      if (slot != null) {
        normalized.add(slot);
        continue;
      }
      normalized.add({
        'slot_time': time,
        'display_time': _displayTime(time),
        'status': 'Available',
        'booked_count': 0,
        'capacity': 10,
      });
    }
    return normalized;
  }

  String _canonicalTime(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      return value;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final second = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
  }

  String _displayTime(String canonical) {
    return formatTo12Hour(canonical);
  }

  bool get _hasBookableSlots {
    return _slots.any(_isSlotBookable);
  }

  bool _isStatusBookable(String status) {
    final normalized = status.toLowerCase();
    return normalized != 'holiday' &&
        normalized != 'unavailable' &&
        normalized != 'booked' &&
        normalized != 'break';
  }

  bool _isSlotTaken(Map<String, dynamic> slot) {
    final status = slot['status']?.toString() ?? 'Available';
    if (!_isStatusBookable(status)) {
      return true;
    }
    return _isSlotFull(slot);
  }

  Map<String, dynamic> _pickMostBufferedSlot({
    required List<Map<String, dynamic>> availableSlots,
    required List<Map<String, dynamic>> allSlots,
    required double? maxTemp,
    required double? rainChance,
  }) {
    if (availableSlots.isEmpty) {
      return <String, dynamic>{};
    }

    final occupiedMinutes = allSlots
        .where(_isSlotTaken)
        .map((slot) => _timeToMinutes(slot['slot_time']?.toString() ?? ''))
        .whereType<int>()
        .toList();

    Map<String, dynamic>? best;
    var bestBuffer = -1;
    var bestWeatherScore = -1 << 20;
    var bestCenterScore = -1 << 20;

    for (final candidate in availableSlots) {
      final minute = _timeToMinutes(candidate['slot_time']?.toString() ?? '');
      if (minute == null) {
        continue;
      }

      var nearestBuffer = 24 * 60;
      if (occupiedMinutes.isNotEmpty) {
        nearestBuffer = occupiedMinutes
            .map((taken) => (minute - taken).abs())
            .reduce((a, b) => a < b ? a : b);
      }

      final weatherScore = _weatherTieBreakerScore(
        slotMinute: minute,
        maxTemp: maxTemp,
        rainChance: rainChance,
      );
      final centerScore = -(minute - (12 * 60)).abs();

      // With real hourly forecast data, weather leads and schedule buffer breaks
      // ties. Buffer led before, but on an empty day every slot has the same
      // (infinite) buffer, so the weather score never got to matter at all.
      final weatherLeads = _hourlyRain.isNotEmpty;
      final bool better;
      if (weatherLeads) {
        better = weatherScore > bestWeatherScore ||
            (weatherScore == bestWeatherScore && nearestBuffer > bestBuffer) ||
            (weatherScore == bestWeatherScore &&
                nearestBuffer == bestBuffer &&
                centerScore > bestCenterScore);
      } else {
        better = nearestBuffer > bestBuffer ||
            (nearestBuffer == bestBuffer && weatherScore > bestWeatherScore) ||
            (nearestBuffer == bestBuffer &&
                weatherScore == bestWeatherScore &&
                centerScore > bestCenterScore);
      }

      if (better) {
        best = candidate;
        bestBuffer = nearestBuffer;
        bestWeatherScore = weatherScore;
        bestCenterScore = centerScore;
      }
    }

    return best ?? availableSlots.first;
  }

  /// Parses an Open-Meteo hourly series into hour-of-day -> value.
  Map<int, double> _parseHourlySeries(Map<String, dynamic> hourly, String key) {
    final times = hourly['time'] as List<dynamic>? ?? const [];
    final values = hourly[key] as List<dynamic>? ?? const [];
    if (times.isEmpty || values.length != times.length) return const {};

    final out = <int, double>{};
    for (var i = 0; i < times.length; i++) {
      // Entries look like "2026-09-09T14:00".
      final stamp = times[i]?.toString() ?? '';
      final tIndex = stamp.indexOf('T');
      if (tIndex < 0 || stamp.length < tIndex + 3) continue;
      final hour = int.tryParse(stamp.substring(tIndex + 1, tIndex + 3));
      final value = double.tryParse('${values[i]}');
      if (hour != null && value != null) out[hour] = value;
    }
    return out;
  }

  /// Weather desirability for one slot, higher is better.
  ///
  /// Scores each slot against the forecast for *its own hour*. Previously this
  /// only saw the whole-day rain mean, so every slot scored identically on
  /// weather and the pick collapsed to "closest to midday" -- which is why a
  /// day with an 88% daily rain chance still recommended the earliest slot
  /// without ever considering that the rain might be confined to the morning.
  int _weatherTieBreakerScore({
    required int slotMinute,
    required double? maxTemp,
    required double? rainChance,
  }) {
    final hour = slotMinute ~/ 60;
    final hourRain = _hourlyRain[hour];
    final hourTemp = _hourlyTemp[hour];

    if (hourRain != null) {
      // Rain probability dominates: a dry hour is worth far more than a
      // marginally cooler or more central one. Scaled by 10 so temperature and
      // midday preference only separate slots with similar rain.
      var score = -(hourRain.round() * 10);
      if (hourTemp != null && hourTemp >= 33) {
        score -= ((hourTemp - 33) * 5).round();
      }
      // Gentle nudge toward the middle of the day among equally dry slots.
      score -= ((slotMinute - (12 * 60)).abs() ~/ 60);
      return score;
    }

    // No hourly data: fall back to the original whole-day heuristics.
    if (rainChance != null && rainChance >= 60) {
      return -slotMinute;
    }

    if (maxTemp != null && maxTemp >= 33) {
      final isCoolerWindow = slotMinute <= (10 * 60) || slotMinute >= (16 * 60);
      return isCoolerWindow ? 1000 - (slotMinute - (10 * 60)).abs() : 0;
    }

    return -(slotMinute - (11 * 60)).abs();
  }

  int? _timeToMinutes(String value) {
    final canonical = _canonicalTime(value);
    final parts = canonical.split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return hour * 60 + minute;
  }

  bool _isSlotBookable(Map<String, dynamic> slot) {
    final status = slot['status']?.toString() ?? 'Available';
    if (!_isStatusBookable(status)) {
      return false;
    }

    if (_isSlotFull(slot)) {
      return false;
    }

    final canonicalTime = slot['slot_time']?.toString() ?? '';
    final slotDateTime = tryParseSlotDateTime(date: _activeDate, time: canonicalTime);
    if (slotDateTime == null) {
      return false;
    }
    return isSlotBookableAt(slotDateTime);
  }

  int _slotBookedCount(Map<String, dynamic> slot) {
    return int.tryParse(slot['booked_count']?.toString() ?? '') ?? 0;
  }

  int _slotCapacity(Map<String, dynamic> slot) {
    return int.tryParse(slot['capacity']?.toString() ?? '') ?? 10;
  }

  bool _isSlotFull(Map<String, dynamic> slot) {
    return _slotBookedCount(slot) >= _slotCapacity(slot);
  }

  Color _slotAvailabilityColor(Map<String, dynamic> slot) {
    final booked = _slotBookedCount(slot);
    if (booked >= 8) {
      return Colors.redAccent;
    }
    if (booked >= 5) {
      return Colors.amber;
    }
    return Colors.green;
  }

  void _openTryHaircut() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
    );
  }

  Widget _buildSlotsSkeleton() {
    return AppShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.7,
            ),
            itemCount: 9,
            itemBuilder: (_, __) => LayoutBuilder(
              builder: (context, constraints) => AppShimmerBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                borderRadius: 10,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const AppShimmerBox(height: 14, borderRadius: 6),
        ],
      ),
    );
  }
}
