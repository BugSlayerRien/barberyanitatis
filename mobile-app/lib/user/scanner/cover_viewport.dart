import 'package:flutter/material.dart';

/// Maps face geometry from source-image normalized space (0–1) into widget space
/// when the source is shown with [BoxFit.cover] inside [constraints].
class CoverViewportMapper {
  CoverViewportMapper._();

  static MappedFaceGeometry map({
    required Rect face,
    required double sourceAspect,
    required BoxConstraints constraints,
    double? foreheadAnchorY,
    double? eyeMidX,
    double? eyeDistanceNorm,
  }) {
    final cw = constraints.maxWidth;
    final ch = constraints.maxHeight;
    if (cw <= 0 || ch <= 0 || sourceAspect <= 0) {
      return MappedFaceGeometry(
        face: face,
        foreheadAnchorY: foreheadAnchorY,
        eyeMidX: eyeMidX,
        eyeDistanceNorm: eyeDistanceNorm,
      );
    }

    final containerAspect = cw / ch;

    if (sourceAspect > containerAspect) {
      // Image is wider than the viewport: crop left/right.
      final visibleW = containerAspect / sourceAspect;
      final padX = (1.0 - visibleW) * 0.5;
      return MappedFaceGeometry(
        face: Rect.fromLTWH(
          padX + face.left * visibleW,
          face.top,
          face.width * visibleW,
          face.height,
        ),
        foreheadAnchorY: foreheadAnchorY,
        eyeMidX: eyeMidX != null ? padX + eyeMidX * visibleW : null,
        eyeDistanceNorm:
            eyeDistanceNorm != null ? eyeDistanceNorm * visibleW : null,
      );
    }

    // Image is taller than the viewport: crop top/bottom.
    final visibleH = sourceAspect / containerAspect;
    final padY = (1.0 - visibleH) * 0.5;
    return MappedFaceGeometry(
      face: Rect.fromLTWH(
        face.left,
        padY + face.top * visibleH,
        face.width,
        face.height * visibleH,
      ),
      foreheadAnchorY:
          foreheadAnchorY != null ? padY + foreheadAnchorY * visibleH : null,
      eyeMidX: eyeMidX,
      eyeDistanceNorm: eyeDistanceNorm,
    );
  }
}

class MappedFaceGeometry {
  final Rect face;
  final double? foreheadAnchorY;
  final double? eyeMidX;
  final double? eyeDistanceNorm;

  const MappedFaceGeometry({
    required this.face,
    this.foreheadAnchorY,
    this.eyeMidX,
    this.eyeDistanceNorm,
  });
}
