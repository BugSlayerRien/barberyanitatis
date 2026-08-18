import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'camera_frame_orientation.dart';

/// Fills [constraints] with the camera feed using [BoxFit.cover].
/// Does not stretch: extra image is cropped.
///
/// Sizes the preview the same way [CameraPreview] does: swapped (portrait)
/// when the device is portrait, native buffer size when landscape.
class CameraPreviewCover extends StatelessWidget {
  final CameraController controller;

  const CameraPreviewCover({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) {
          return const ColoredBox(color: Color(0xFF111111));
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final previewSize = value.previewSize;
            final layout = previewSize == null
                ? Size(constraints.maxWidth, constraints.maxHeight)
                : CameraFrameOrientation.previewLayoutSize(
                    previewSize,
                    CameraFrameOrientation.previewOrientation(controller),
                  );

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
                    width: layout.width,
                    height: layout.height,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
