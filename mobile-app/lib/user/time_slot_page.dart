import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'ai_face_scan_page.dart';
import 'ai_funnel_service.dart';
import 'appointments_page.dart';
import 'booking_guard.dart';
import 'payment_page.dart';
import 'api_config.dart';
import 'time_format_utils.dart';
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
  static const double _shopLatitude = 14.5995;
  static const double _shopLongitude = 120.9842;
  static const String _aiApiKey =
      'REMOVED_GEMINI_KEY';
  static const String _aiModelName = 'gemini-2.5-flash';

  String? _selectedTime;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _slots = [];
  Map<String, dynamic>? _defaultService;
  bool _loadingWeatherAdvice = false;
  String? _weatherSummary;
  String? _timeAdvice;
  bool _bookingInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadDefaultService();
    _loadWeatherAndSuggestion();
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
    setState(() {
      _loadingWeatherAdvice = true;
    });

    final date = _formatDate(widget.selectedDate);
    final availableSlots = _availableSlotsForAdvice();

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$_shopLatitude&longitude=$_shopLongitude&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_mean&timezone=auto&start_date=$date&end_date=$date',
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

      final weatherSummary = _buildWeatherSummary(maxTemp, minTemp, rainChance);
      final fallbackAdvice = _buildHeuristicAdvice(
        maxTemp: maxTemp,
        rainChance: rainChance,
        availableSlots: availableSlots,
      );
      final aiAdvice = await _getAiTimeAdvice(
        date: date,
        weatherSummary: weatherSummary,
        maxTemp: maxTemp,
        minTemp: minTemp,
        rainChance: rainChance,
        availableSlots: availableSlots,
      );
      final validatedAiAdvice = _validateAiAdvice(aiAdvice, availableSlots);

      if (!mounted) {
        return;
      }
      setState(() {
        _weatherSummary = weatherSummary;
        _timeAdvice = validatedAiAdvice ?? fallbackAdvice;
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
        );
        _loadingWeatherAdvice = false;
      });
    }
  }

  List<Map<String, dynamic>> _availableSlotsForAdvice() {
    return _slots.where(_isSlotBookable).toList();
  }

  String _buildWeatherSummary(double? maxTemp, double? minTemp, double? rainChance) {
    final high = maxTemp != null ? '${maxTemp.toStringAsFixed(0)}C' : 'n/a';
    final low = minTemp != null ? '${minTemp.toStringAsFixed(0)}C' : 'n/a';
    final rain = rainChance != null ? '${rainChance.toStringAsFixed(0)}%' : 'n/a';
    return 'Forecast: high $high, low $low, rain chance $rain.';
  }

  String _buildHeuristicAdvice({
    required double? maxTemp,
    required double? rainChance,
    required List<Map<String, dynamic>> availableSlots,
  }) {
    if (availableSlots.isEmpty) {
      return 'No open times are available now. Please pick another date or barber.';
    }

    final morning = availableSlots.where((slot) {
      final hour = int.tryParse((slot['slot_time']?.toString() ?? '00:00:00').split(':').first) ?? 0;
      return hour >= 9 && hour <= 11;
    }).toList();
    final coolerWindow = availableSlots.where((slot) {
      final hour = int.tryParse((slot['slot_time']?.toString() ?? '00:00:00').split(':').first) ?? 0;
      return hour <= 10 || hour >= 16;
    }).toList();

    final preferred = rainChance != null && rainChance >= 60
        ? (morning.isNotEmpty ? morning.first : availableSlots.first)
        : (maxTemp != null && maxTemp >= 33
            ? (coolerWindow.isNotEmpty ? coolerWindow.first : availableSlots.first)
            : (morning.isNotEmpty ? morning.first : availableSlots.first));

    final displayTime = preferred['display_time']?.toString() ?? preferred['slot_time']?.toString() ?? '';
    if (rainChance != null && rainChance >= 60) {
      return 'Best today: $displayTime. Earlier slots are safer before possible rain.';
    }
    if (maxTemp != null && maxTemp >= 33) {
      return 'Best today: $displayTime. Cooler hours are better for comfort and travel.';
    }
    return 'Best today: $displayTime. It balances convenience with expected weather.';
  }

  String? _validateAiAdvice(String? aiAdvice, List<Map<String, dynamic>> availableSlots) {
    if (aiAdvice == null) {
      return null;
    }

    final cleaned = aiAdvice.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return null;
    }

    final lower = cleaned.toLowerCase();
    if (lower == 'best today:' || cleaned.endsWith(':')) {
      return null;
    }

    final hasTimeToken = RegExp(r'\b\d{1,2}(:\d{2})?\s?(AM|PM|am|pm)?\b').hasMatch(cleaned);
    final mentionsKnownSlot = availableSlots.any((slot) {
      final display = slot['display_time']?.toString() ?? '';
      final canonical = slot['slot_time']?.toString() ?? '';
      return (display.isNotEmpty && cleaned.contains(display)) ||
          (canonical.isNotEmpty && cleaned.contains(canonical));
    });

    if (!hasTimeToken && !mentionsKnownSlot) {
      return null;
    }

    return cleaned;
  }

  Future<String?> _getAiTimeAdvice({
    required String date,
    required String weatherSummary,
    required double? maxTemp,
    required double? minTemp,
    required double? rainChance,
    required List<Map<String, dynamic>> availableSlots,
  }) async {
    if (availableSlots.isEmpty || !_aiApiKey.isNotEmpty) {
      return null;
    }

    final slotText = availableSlots
        .map((slot) => slot['display_time']?.toString() ?? slot['slot_time']?.toString() ?? '')
        .where((slot) => slot.isNotEmpty)
        .join(', ');
    if (slotText.isEmpty) {
      return null;
    }

    final prompt = '''
You are a scheduling assistant for a barbershop.
Pick the best appointment time for the customer based on weather and available slots.
Date: $date
Weather summary: $weatherSummary
High temp: ${maxTemp?.toStringAsFixed(1) ?? 'n/a'}
Low temp: ${minTemp?.toStringAsFixed(1) ?? 'n/a'}
Rain chance: ${rainChance?.toStringAsFixed(1) ?? 'n/a'}
Available slots: $slotText

Return exactly one short sentence in this format:
Best today: <time>. <reason>
Keep the total response under 24 words.
''';

    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_aiModelName:generateContent?key=$_aiApiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.3,
            'topP': 0.9,
            'maxOutputTokens': 120,
          }
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300 || response.body.isEmpty) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) {
        return null;
      }
      final first = candidates.first as Map<String, dynamic>;
      final content = first['content'] as Map<String, dynamic>? ?? const {};
      final parts = content['parts'] as List<dynamic>? ?? const [];
      if (parts.isEmpty) {
        return null;
      }
      final text = (parts.first as Map<String, dynamic>)['text']?.toString().trim();
      if (text == null || text.isEmpty) {
        return null;
      }
      return text;
    } catch (_) {
      return null;
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
                        ? const Text(
                            'Checking weather and suggested best time...',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
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
                      return GestureDetector(
                        onTap: isAvailable ? () => setState(() => _selectedTime = canonicalTime) : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : (isAvailable ? const Color(0xFF1A1A1A) : const Color(0xFF121212)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white10,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              displayTime,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : (isAvailable ? Colors.white : Colors.white38),
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
                      if (UserSession.selectedVariantId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a hairstyle before booking.')),
                        );
                        return;
                      }
                      final hasActive = await BookingGuard.hasActiveAppointment(userId: UserSession.userId);
                      if (!context.mounted) return;
                      if (hasActive) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('You already have an active appointment.')),
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                        );
                        return;
                      }

                      final selectedDateTime = tryParseSlotDateTime(
                        date: widget.selectedDate,
                        time: _selectedTime ?? '',
                      );
                      if (selectedDateTime == null || !selectedDateTime.isAfter(DateTime.now())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This time has already passed. Please pick a new time.')),
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

                      final startTime = _selectedTime ?? '';
                      final baseDuration = int.tryParse(_defaultService!['base_duration']?.toString() ?? '') ?? 0;
                      final durationHint = UserSession.selectedEstimatedMinutes;
                      final duration = durationHint != null && durationHint > 0
                          ? durationHint
                          : baseDuration;
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
                        if (response.statusCode == 409) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('You already have an active appointment.')),
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                          );
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(data['error']?.toString() ?? 'Booking failed.')),
                        );
                        return;
                      }

                      final bookingData = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
                      final appointmentId = int.tryParse(bookingData['appointmentID']?.toString() ?? '') ?? 0;
                      if (appointmentId > 0 && UserSession.userId != null && UserSession.selectedVariantId != null) {
                        await AiFunnelService.trackBookingCreated(
                          scanSessionId: UserSession.ensureScanSessionId(),
                          userId: UserSession.userId!,
                          variantId: UserSession.selectedVariantId!,
                          appointmentId: appointmentId,
                          serviceId: serviceId,
                          estimatedMinutes: duration,
                        );
                      }

                      if (!context.mounted) return;

                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PaymentPage(
                          appointmentID: appointmentId,
                          barberName: widget.barberName,
                          date: _formatDisplayDate(widget.selectedDate),
                          time: formatTo12Hour(_selectedTime ?? ''),
                          amount: price.round(),
                          haircutName: UserSession.selectedStyleName ?? 'Haircut',
                        ),
                      ));
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
                  : const Text(
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
    const startMinutes = 9 * 60;
    const endMinutes = 16 * 60 + 30;
    for (var minutes = startMinutes; minutes <= endMinutes; minutes += 50) {
      final hour = minutes ~/ 60;
      final minute = minutes % 60;
      times.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    }
    return times
        .map((time) => {
              'slot_time': _canonicalTime(time),
              'display_time': _displayTime(_canonicalTime(time)),
              'status': 'Available',
            })
        .toList();
  }

  List<Map<String, dynamic>> _normalizeSlots(List<Map<String, dynamic>> slots) {
    final Map<String, Map<String, dynamic>> byTime = {};
    for (final slot in slots) {
      final time = _canonicalTime(slot['slot_time']?.toString() ?? '');
      if (time.isEmpty) {
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
        if (existingStatus.toLowerCase() == 'available' && status.toLowerCase() != 'available') {
          byTime[time] = {
            ...slot,
            'slot_time': time,
            'display_time': _displayTime(time),
          };
        }
      }
    }
    final sortedKeys = byTime.keys.toList()..sort();
    return sortedKeys.map((time) => byTime[time]!).toList();
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
    return normalized != 'holiday' && normalized != 'unavailable' && normalized != 'booked';
  }

  bool _isSlotBookable(Map<String, dynamic> slot) {
    final status = slot['status']?.toString() ?? 'Available';
    if (!_isStatusBookable(status)) {
      return false;
    }

    final canonicalTime = slot['slot_time']?.toString() ?? '';
    final slotDateTime = tryParseSlotDateTime(date: widget.selectedDate, time: canonicalTime);
    if (slotDateTime == null) {
      return false;
    }
    return slotDateTime.isAfter(DateTime.now());
  }

  void _openTryHaircut() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
    );
  }

  Widget _buildSlotsSkeleton() {
    return Column(
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
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}
