import 'package:flutter/material.dart';

import '../user/api_config.dart';
import '../user/time_format_utils.dart';

class BarberAppointmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const BarberAppointmentDetailPage({
    super.key,
    required this.appointment,
  });

  @override
  Widget build(BuildContext context) {
    final customerName = appointment['customerName']?.toString() ?? 'Customer';
    final date = appointment['appointmentDate']?.toString() ?? '-';
    final startTime = formatTo12Hour(appointment['startTime']?.toString() ?? '-');
    final endTime = formatTo12Hour(appointment['endTime']?.toString() ?? '-');
    final status = appointment['status']?.toString() ?? 'Unknown';
    final bookingCode = appointment['bookingCode']?.toString() ?? '-';
    final previewImages = _previewImages();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Appointment Details', style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            title: 'Customer',
            value: customerName,
          ),
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
          if (previewImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _imageGallery(previewImages),
          ],
        ],
      ),
    );
  }

  List<_PreviewImage> _previewImages() {
    final entries = <_PreviewImage>[];
    void add(String label, dynamic raw) {
      final value = raw?.toString().trim() ?? '';
      if (value.isEmpty) {
        return;
      }
      entries.add(_PreviewImage(label: label, url: ApiConfig.resolveImageUrl(value)));
    }

    add('Front', appointment['customerFrontUrl'] ?? appointment['frontViewUrl'] ?? appointment['front_view_url']);
    add('Left', appointment['customerLeftUrl'] ?? appointment['sideViewUrl'] ?? appointment['side_view_url']);
    add('Right', appointment['customerRightUrl'] ?? appointment['backViewUrl'] ?? appointment['back_view_url']);
    return entries;
  }

  Widget _imageGallery(List<_PreviewImage> images) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hair Preview',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: images.map((image) {
              return SizedBox(
                width: 108,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          image.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF1B1B1B),
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      image.label,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
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

class _PreviewImage {
  final String label;
  final String url;

  const _PreviewImage({required this.label, required this.url});
}
