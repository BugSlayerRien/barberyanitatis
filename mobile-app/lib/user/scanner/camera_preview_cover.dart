import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Fills [constraints] with the camera feed using [BoxFit.cover].
/// Does not stretch: extra image is cropped, matching the live-preview scanner.
class CameraPreviewCover extends StatelessWidget {
  final CameraController controller;

  const CameraPreviewCover({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const ColoredBox(color: Color(0xFF111111));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        // Camera previewSize is landscape; the widget is typically portrait.
        final previewWidth = previewSize?.height ?? constraints.maxWidth;
        final previewHeight = previewSize?.width ?? constraints.maxHeight;

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: constraints.maxWidth,
            minHeight: constraints.maxHeight,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover,
              alignment: Alignment.center,
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}
