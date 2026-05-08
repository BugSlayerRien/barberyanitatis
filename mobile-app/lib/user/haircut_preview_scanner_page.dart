import 'package:flutter/material.dart';

import 'ai_face_scan_page.dart';

class HaircutPreviewScannerPage extends StatelessWidget {
  final Map<String, dynamic> style;

  const HaircutPreviewScannerPage({super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return AiFaceScanPage(
      presetRecommendation: style,
      previewOnly: true,
    );
  }
}
