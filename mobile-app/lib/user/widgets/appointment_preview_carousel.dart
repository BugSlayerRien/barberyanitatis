import 'package:flutter/material.dart';
import '../app_brand.dart';

import '../api_config.dart';

class AppointmentPreviewImage {
  final String label;
  final String url;

  const AppointmentPreviewImage({required this.label, required this.url});
}

List<AppointmentPreviewImage> previewImagesFromAppointment(
  Map<String, dynamic> appointment,
) {
  final entries = <AppointmentPreviewImage>[];

  void add(String label, dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) {
      return;
    }
    entries.add(
      AppointmentPreviewImage(label: label, url: ApiConfig.resolveImageUrl(value)),
    );
  }

  add('Front', appointment['customerFrontUrl'] ?? appointment['frontViewUrl'] ?? appointment['front_view_url']);
  add('Left', appointment['customerLeftUrl'] ?? appointment['sideViewUrl'] ?? appointment['side_view_url']);
  add('Right', appointment['customerRightUrl'] ?? appointment['backViewUrl'] ?? appointment['back_view_url']);
  return entries;
}

/// Swipeable hair preview gallery for appointment detail screens.
class AppointmentPreviewCarousel extends StatefulWidget {
  final List<AppointmentPreviewImage> images;
  final double height;

  const AppointmentPreviewCarousel({
    super.key,
    required this.images,
    this.height = 280,
  });

  @override
  State<AppointmentPreviewCarousel> createState() => _AppointmentPreviewCarouselState();
}

class _AppointmentPreviewCarouselState extends State<AppointmentPreviewCarousel> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) {
      return const SizedBox.shrink();
    }

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
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: widget.height,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) {
                final image = widget.images[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _PreviewImage(url: image.url),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      image.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.images.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (index) {
                final active = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppBrand.accent : Colors.white24,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  final String url;

  const _PreviewImage({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFF1B1B1B),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 40),
      ),
    );
  }
}
