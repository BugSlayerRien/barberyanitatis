import 'package:flutter/material.dart';

import 'api_config.dart';

class CompletedAppointmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const CompletedAppointmentDetailPage({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    final previewImages = _previewImages();
    final heroImage = previewImages.isNotEmpty
        ? previewImages.first.url
        : 'assets/images/kalbo.png';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Appointment Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA99941), width: 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildHeroImage(heroImage),
              ),
            ),
            const SizedBox(height: 16),
            Text(appointment['service'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(appointment['barber'] as String, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Color(0xFFA99941), size: 16),
                const SizedBox(width: 8),
                Text(appointment['date'] as String, style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time, color: Color(0xFFA99941), size: 16),
                const SizedBox(width: 8),
                Text(appointment['time'] as String, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Duration: ${appointment['duration']}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text('Price: ${appointment['price']}', style: const TextStyle(color: Color(0xFFA99941), fontWeight: FontWeight.bold)),
            if (previewImages.isNotEmpty) ...[
              const SizedBox(height: 20),
              _previewGallery(previewImages),
            ],
            const SizedBox(height: 24),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE74C3C),
                      side: const BorderSide(color: Color(0xFFE74C3C), width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA99941),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Done', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  Widget _buildHeroImage(String imageUrl) {
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(imageUrl, fit: BoxFit.cover);
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/images/kalbo.png',
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _previewGallery(List<_PreviewImage> images) {
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
}

class _PreviewImage {
  final String label;
  final String url;

  const _PreviewImage({required this.label, required this.url});
}
