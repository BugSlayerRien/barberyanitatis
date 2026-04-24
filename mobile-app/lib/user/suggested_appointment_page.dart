import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'ai_funnel_service.dart';
import 'api_config.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'payment_page.dart';
import 'time_format_utils.dart';
import 'user_session.dart';

class SuggestedAppointmentPage extends StatefulWidget {
  final Map<String, dynamic> suggestion;

  const SuggestedAppointmentPage({
    super.key,
    required this.suggestion,
  });

  @override
  State<SuggestedAppointmentPage> createState() => _SuggestedAppointmentPageState();
}

class _SuggestedAppointmentPageState extends State<SuggestedAppointmentPage> {
  bool _booking = false;

  bool _isPastOrInvalidSlot({required String date, required String time}) {
    final dateParts = date.split('-');
    if (dateParts.length != 3) {
      return true;
    }
    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    if (year == null || month == null || day == null) {
      return true;
    }

    final slotDateTime = tryParseSlotDateTime(
      date: DateTime(year, month, day),
      time: time,
    );
    if (slotDateTime == null) {
      return true;
    }

    return !slotDateTime.isAfter(DateTime.now());
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

    final hasActive = await BookingGuard.hasActiveAppointment(userId: UserSession.userId);
    if (!mounted) {
      return;
    }
    if (hasActive) {
      setState(() => _booking = false);
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
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No haircut service configured.')),
      );
      return;
    }

    final suggestion = widget.suggestion;
    final barberId = suggestion['barberID'] is int
        ? suggestion['barberID'] as int
        : int.tryParse('${suggestion['barberID']}') ?? 0;
    final barberName = suggestion['barberName']?.toString() ?? 'Barber';
    final appointmentDate = suggestion['slotDate']?.toString() ?? '';
    final startTime = suggestion['slotTime']?.toString() ?? '';

    if (barberId <= 0 || appointmentDate.isEmpty || startTime.isEmpty) {
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suggested schedule is incomplete. Please choose manually.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    if (_isPastOrInvalidSlot(date: appointmentDate, time: startTime)) {
      setState(() => _booking = false);
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
      setState(() => _booking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid service configuration.')),
      );
      return;
    }

    final price = double.tryParse(service['base_price']?.toString() ?? '') ?? 0;
    final baseDuration = int.tryParse(service['base_duration']?.toString() ?? '') ?? 0;
    final durationHint = UserSession.selectedEstimatedMinutes;
    final duration = durationHint != null && durationHint > 0 ? durationHint : baseDuration;
    final endTime = _addMinutes(startTime, duration);

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/booking.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'create',
        'userID': UserSession.userId,
        'barberID': barberId,
        'appointmentDate': appointmentDate,
        'startTime': startTime,
        'endTime': endTime,
        'serviceIDs': [serviceId],
        'variantID': UserSession.selectedVariantId,
      }),
    );

    if (!mounted) {
      return;
    }

    if (response.statusCode != 201) {
      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      setState(() => _booking = false);
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

    final bookingData = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};
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

    if (!mounted) {
      return;
    }

    setState(() => _booking = false);

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

  @override
  Widget build(BuildContext context) {
    final barberName = widget.suggestion['barberName']?.toString() ?? 'Barber';
    final slotDate = widget.suggestion['slotDate']?.toString() ?? '';
    final slotTime = formatTo12Hour(widget.suggestion['slotTime']?.toString() ?? '');
    final isFallback = widget.suggestion['isFallback'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Suggested Appointment', style: TextStyle(color: Colors.white)),
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
                  const Text(
                    'Suggested Appointment',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (isFallback)
                    const Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        'We suggested a standard time because no slots were found yet.',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    )
                  else
                    const SizedBox(height: 12),
                  _detailRow('Barber', barberName),
                  _detailRow('Date', slotDate),
                  _detailRow('Time', slotTime),
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
                          child: const Text('Choose Manually'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _booking ? null : _proceedToPayment,
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
                              : const Text('Yes, Proceed'),
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
