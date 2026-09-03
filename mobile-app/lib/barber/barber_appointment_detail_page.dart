import 'package:flutter/material.dart';

import '../user/time_format_utils.dart';
import '../user/widgets/appointment_preview_carousel.dart';

class BarberAppointmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const BarberAppointmentDetailPage({
    super.key,
    required this.appointment,
  });

  @override
  Widget build(BuildContext context) {
    final customerName = appointment['customerName']?.toString() ?? 'Customer';
    final serviceName = appointment['serviceName']?.toString() ??
        appointment['hairstyleName']?.toString() ??
        'Haircut';
    final date = appointment['appointmentDate']?.toString() ?? '-';
    final startTime = formatTo12Hour(appointment['startTime']?.toString() ?? '-');
    final endTime = formatTo12Hour(appointment['endTime']?.toString() ?? '-');
    final status = appointment['status']?.toString() ?? 'Unknown';
    final bookingCode = appointment['bookingCode']?.toString() ?? '-';
    final specialInstructions =
        appointment['specialInstructions']?.toString().trim() ?? '';
    final previewImages = previewImagesFromAppointment(appointment);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Appointment Details', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(title: 'Customer', value: customerName),
          const SizedBox(height: 12),
          _card(title: 'Haircut', value: serviceName),
          const SizedBox(height: 12),
          _card(title: 'Booking Code', value: bookingCode),
          const SizedBox(height: 12),
          _card(title: 'Date', value: date),
          const SizedBox(height: 12),
          _card(title: 'Start Time', value: startTime),
          const SizedBox(height: 12),
          _card(title: 'End Time', value: endTime),
          const SizedBox(height: 12),
          _card(title: 'Status', value: status),
          if (specialInstructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _card(
              title: 'Customer Note',
              value: specialInstructions,
              highlight: true,
            ),
          ],
          if (previewImages.isNotEmpty) ...[
            const SizedBox(height: 20),
            AppointmentPreviewCarousel(images: previewImages),
          ],
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF2A2410) : const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFFA99941) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
