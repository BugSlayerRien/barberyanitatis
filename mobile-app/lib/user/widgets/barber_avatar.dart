import 'package:flutter/material.dart';

import '../api_config.dart';

/// A barber's photo, falling back to their initials.
///
/// `barbers.php` returns `profile_image` on both the list and detail actions,
/// but the customer-facing screens only ever drew initials. The same
/// empty/'null'/broken-URL handling the staff profile page does is collected
/// here so the selection card and the detail dialog cannot drift apart.
class BarberAvatar extends StatelessWidget {
  final String? profileImage;
  final String barberName;
  final double size;
  final Color background;

  const BarberAvatar({
    super.key,
    required this.profileImage,
    required this.barberName,
    required this.size,
    this.background = Colors.black,
  });

  /// Pulls the image off an API row under either spelling, treating the empty
  /// string and a literal 'null' as no image.
  static String imageFieldOf(Map<String, dynamic>? barber) {
    if (barber == null) return '';
    final value = (barber['profile_image'] ?? barber['profileImage'] ?? '')
        .toString()
        .trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return '';
    return value;
  }

  static String initialsOf(String barberName) {
    final parts = barberName
        .trim()
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .take(2)
        .join()
        .toUpperCase();
    return parts.isEmpty ? 'B' : parts;
  }

  @override
  Widget build(BuildContext context) {
    final initials = initialsOf(barberName);
    final raw = profileImage?.trim() ?? '';
    final hasImage = raw.isNotEmpty && raw.toLowerCase() != 'null';

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: hasImage
          // Relative uploads are served through the PHP proxy (disk locally,
          // Storage in production), same as everywhere else in the app.
          ? Image.network(
              ApiConfig.resolveImageUrl(raw),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(initials),
            )
          : _initials(initials),
    );
  }

  Widget _initials(String initials) => Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.3,
          ),
        ),
      );
}
