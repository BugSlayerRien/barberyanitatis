import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai_funnel_service.dart';
import 'api_config.dart';
import 'app_brand.dart';
import 'services/face_scan_service.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'payment_page.dart';
import 'customer_api.dart';
import 'time_format_utils.dart';
import 'user_session.dart';
import 'services/booking_draft_service.dart';
import 'services/booking_slots_service.dart';

class SuggestedAppointmentPage extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final List<Map<String, dynamic>> alternatives;
  final bool skipPreviews;

  const SuggestedAppointmentPage({
    super.key,
    required this.suggestion,
    this.alternatives = const [],
    this.skipPreviews = false,
  });

  @override
  State<SuggestedAppointmentPage> createState() => _SuggestedAppointmentPageState();
}

class _SuggestedAppointmentPageState extends State<SuggestedAppointmentPage> {
  bool _booking = false;
  bool _refreshingSuggestion = false;
  bool _retriedAfterConflict = false;
  late Map<String, dynamic> _suggestion;
  late Map<String, dynamic> _recommended;
  late List<Map<String, dynamic>> _alternatives;

  @override
  void initState() {
    super.initState();
    _suggestion = Map<String, dynamic>.from(widget.suggestion);
    _recommended = Map<String, dynamic>.from(widget.suggestion);
    _alternatives = widget.alternatives
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    unawaited(_refreshSuggestionIfStale());
  }

  Future<void> _refreshSuggestionIfStale() async {
    final date = _suggestion['slotDate']?.toString() ?? '';
    final time = _suggestion['slotTime']?.toString() ?? '';
    if (date.isEmpty || time.isEmpty || !_isPastOrInvalidSlot(date: date, time: time)) {
      return;
    }

    setState(() => _refreshingSuggestion = true);
    try {
      final result = await BookingSlotsService.fetchBestSuggestion();
      if (!mounted || !result.isSuccess || result.suggestion == null) {
        return;
      }

      final refreshed = result.suggestion!;
      final refreshedDate = refreshed['slotDate']?.toString() ?? '';
      final refreshedTime = refreshed['slotTime']?.toString() ?? '';
      if (refreshedDate.isEmpty ||
          refreshedTime.isEmpty ||
          _isPastOrInvalidSlot(date: refreshedDate, time: refreshedTime)) {
        return;
      }

      setState(() {
        _suggestion = refreshed;
        _recommended = Map<String, dynamic>.from(refreshed);
        _alternatives = result.alternatives
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {
      // Keep the original suggestion; booking guard still blocks stale times.
    } finally {
      if (mounted) {
        setState(() => _refreshingSuggestion = false);
      }
    }
  }

  bool _isPastOrInvalidSlot({required String date, required String time}) {
    return isPastOrInvalidSuggestion(date: date, time: time);
  }

  Future<Map<String, dynamic>?> _loadDefaultService() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/services.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'list'}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final services = (data['services'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final selectedServiceId = UserSession.selectedServiceId;
      if (selectedServiceId != null) {
        for (final service in services) {
          final serviceId = int.tryParse(service['service_id']?.toString() ?? '');
          if (serviceId == selectedServiceId) {
            UserSession.selectedServiceId = serviceId;
            return service;
          }
        }
      }

      final chosen = services.firstWhere(
        (service) => (service['category']?.toString() ?? '').toLowerCase() == 'haircut',
        orElse: () => services.isNotEmpty ? services.first : <String, dynamic>{},
      );
      UserSession.selectedServiceId = int.tryParse(chosen['service_id']?.toString() ?? '');
      return chosen;
    } catch (_) {
      return null;
    }
  }

  Future<void> _proceedToPayment() async {
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

    setState(() => _booking = true);
    try {
      final hasActive = await BookingGuard.hasActiveAppointment(userId: UserSession.userId);
      if (!mounted) {
        return;
      }
      if (hasActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active appointment.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AppointmentsPage()),
        );
        return;
      }

      final service = await _loadDefaultService();
      if (!mounted) {
        return;
      }
      if (service == null || service.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No haircut service configured.')),
        );
        return;
      }

      final suggestion = _suggestion;
      final barberId = suggestion['barberID'] is int
          ? suggestion['barberID'] as int
          : int.tryParse('${suggestion['barberID']}') ?? 0;
      final barberName = suggestion['barberName']?.toString() ?? 'Barber';
      final appointmentDate = suggestion['slotDate']?.toString() ?? '';
      final startTime = suggestion['slotTime']?.toString() ?? '';

      if (barberId <= 0 || appointmentDate.isEmpty || startTime.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Suggested schedule is incomplete. Please choose manually.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      if (_isPastOrInvalidSlot(date: appointmentDate, time: startTime)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This suggested time has already passed. Please choose another schedule.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      final serviceId = int.tryParse(service['service_id']?.toString() ?? '') ?? 0;
      if (serviceId <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid service configuration.')),
        );
        return;
      }

      final price = double.tryParse(service['base_price']?.toString() ?? '') ?? 0;
      const duration = 60;
      final endTime = _addMinutes(startTime, duration);

      late final Map<String, dynamic> bookingData;
      try {
        bookingData = await CustomerApi.postDecoded(
          'booking.php',
          {
            'action': 'create',
            'userID': UserSession.userId,
            'barberID': barberId,
            'appointmentDate': appointmentDate,
            'startTime': startTime,
            'endTime': endTime,
            'serviceIDs': [serviceId],
            'variantID': UserSession.selectedVariantId,
            if (!widget.skipPreviews) ...FaceScanService.bookingPreviewPayload(),
          },
          okStatusCodes: {201},
        );
      } on CustomerApiException catch (e) {
        if (!mounted) {
          return;
        }
        if (e.statusCode == 409) {
          final errorText = e.message;
          if (errorText.contains('active appointment')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You already have an active appointment.')),
            );
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AppointmentsPage()),
            );
            return;
          }
          if (!_retriedAfterConflict) {
            _retriedAfterConflict = true;
            await _refreshSuggestionIfStale();
            if (!mounted) return;
            if (!_isPastOrInvalidSlot(
              date: _suggestion['slotDate']?.toString() ?? '',
              time: _suggestion['slotTime']?.toString() ?? '',
            )) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('That slot was just taken. Trying the next available time…')),
              );
              await _proceedToPayment();
              return;
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorText.isNotEmpty ? errorText : 'This slot is no longer available.')),
          );
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }

      final appointmentId = int.tryParse(bookingData['appointmentID']?.toString() ?? '') ?? 0;

      await BookingDraftService.clear();

      if (appointmentId > 0 && UserSession.userId != null && UserSession.selectedVariantId != null && !widget.skipPreviews) {
        await AiFunnelService.trackBookingCreated(
          scanSessionId: UserSession.ensureScanSessionId(),
          userId: UserSession.userId!,
          variantId: UserSession.selectedVariantId!,
          appointmentId: appointmentId,
          serviceId: serviceId,
          estimatedMinutes: duration,
          frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
          sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
          backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
        );
        if (bookingData['previewsAttached'] != true) {
          try {
            await FaceScanService.attachPreviewsToAppointment(
              appointmentId: appointmentId,
              scanSessionId: UserSession.ensureScanSessionId(),
              variantId: UserSession.selectedVariantId!,
            );
          } catch (e) {
            // Silent. This only matters when the customer actually
            // generated an AI try-on for this style; booking a Library
            // haircut with no generated preview has nothing to link, so
            // the warning was firing on a normal, successful booking.
            debugPrint('Preview attach failed: $e');
          }
        }
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            appointmentID: appointmentId,
            barberName: barberName,
            date: appointmentDate,
            time: formatTo12Hour(startTime),
            amount: price.round(),
            haircutName: UserSession.selectedStyleName ?? 'Haircut',
          ),
        ),
      );
    } on CustomerApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _booking = false);
      }
    }
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDisplayDate(String rawDate) {
    final parts = rawDate.split('-');
    if (parts.length != 3) {
      return rawDate;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return rawDate;
    }
    return '$month/$day/$year';
  }

  String _slotKey(Map<String, dynamic> slot) {
    return '${slot['barberID']}|${slot['slotDate']}|${slot['slotTime']}';
  }

  void _selectSlot(Map<String, dynamic> slot) {
    if (_booking || _refreshingSuggestion) {
      return;
    }
    setState(() => _suggestion = Map<String, dynamic>.from(slot));
  }

  Widget _slotChoiceCard(Map<String, dynamic> slot, {required bool recommended}) {
    final selected = _slotKey(slot) == _slotKey(_suggestion);
    final barberName = slot['barberName']?.toString() ?? 'Barber';
    final date = _formatDisplayDate(slot['slotDate']?.toString() ?? '');
    final time = formatTo12Hour(slot['slotTime']?.toString() ?? '');
    final reason = formatSuggestionReasonTo12h(
      slot['suggestionReason']?.toString() ?? '',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppBrand.goldTint : const Color(0xFF151515),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _selectSlot(slot),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppBrand.goldLine : AppBrand.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? AppBrand.gold : Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommended ? 'Recommended' : 'Also available',
                        style: TextStyle(
                          color: recommended ? AppBrand.gold : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$barberName · $date · $time',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (reason.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          reason,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barberName = _suggestion['barberName']?.toString() ?? 'Barber';
    final slotDate = _suggestion['slotDate']?.toString() ?? '';
    final slotTime = formatTo12Hour(_suggestion['slotTime']?.toString() ?? '');
    final isFallback = _recommended['isFallback'] == true;
    final suggestionReason = formatSuggestionReasonTo12h(
      _recommended['suggestionReason']?.toString() ?? '',
    );
    final isStale = slotDate.isNotEmpty &&
        _suggestion['slotTime']?.toString().isNotEmpty == true &&
        _isPastOrInvalidSlot(
          date: slotDate,
          time: _suggestion['slotTime']?.toString() ?? '',
        );

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.skipPreviews ? 'Quick Booking' : 'Suggested Appointment',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.skipPreviews ? 'Quick Booking' : 'Suggested Appointment',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (widget.skipPreviews)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(
                        'Booking with your usual style — no face scan needed.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    )
                  else if (suggestionReason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        suggestionReason,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    )
                  else if (isFallback)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        'We suggested a standard time because no slots were found yet.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                  if (_alternatives.isNotEmpty) ...[
                    _slotChoiceCard(_recommended, recommended: true),
                    // One alternative only. The backend often returns several
                    // slots from the same barber on the same day an hour apart,
                    // which read as duplicates and just add scrolling. "Pick
                    // Date & Time" covers anyone who wants the full list.
                    ..._alternatives
                        .where((slot) => _slotKey(slot) != _slotKey(_recommended))
                        .take(1)
                        .map((slot) => _slotChoiceCard(slot, recommended: false)),
                  ] else ...[
                    _detailRow('Barber', barberName),
                    _detailRow('Date', _formatDisplayDate(slotDate)),
                    _detailRow('Time', slotTime),
                  ],
                  if (_refreshingSuggestion)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Updating to the next available time...',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    )
                  else if (isStale)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'This suggested time is no longer available. Please choose manually.',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _booking
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 1),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: const Text('Pick Date & Time'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _booking || _refreshingSuggestion || isStale ? null : _proceedToPayment,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _booking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                )
                              : const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
