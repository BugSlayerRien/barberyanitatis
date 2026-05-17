import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shared preview frame dimensions for live scanner and static results.
class ScannerLayout {
  ScannerLayout._();

  static double previewHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    final isPortrait = media.orientation == Orientation.portrait;
    if (kIsWeb || isPortrait) {
      return (media.size.height * 0.62).clamp(360.0, 640.0);
    }
    return (media.size.height * 0.72).clamp(280.0, 480.0);
  }

  static Widget previewFrame({
    required BuildContext context,
    required Widget child,
  }) {
    final height = previewHeight(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          color: const Color(0xFF111111),
        ),
        child: child,
      ),
    );
  }
}
