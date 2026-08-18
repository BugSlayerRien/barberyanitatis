import 'dart:ui';

/// Maps ML Kit face boxes from the camera buffer into the same space as a
/// [BoxFit.cover] [CameraPreview] (rotated for the current UI orientation,
/// optionally mirrored).
class FacePreviewMapping {
  FacePreviewMapping._();

  static Rect normalizeBoundingBox({
    required Rect boundingBox,
    required Size imageSize,
    required int rotationDegrees,
    required bool mirrorX,
  }) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Rect.zero;
    }

    final left = boundingBox.left / imageSize.width;
    final top = boundingBox.top / imageSize.height;
    final width = boundingBox.width / imageSize.width;
    final height = boundingBox.height / imageSize.height;

    late final Rect rotated;
    switch (rotationDegrees % 360) {
      case 90:
        rotated = Rect.fromLTWH(top, 1.0 - left - width, height, width);
        break;
      case 270:
        rotated = Rect.fromLTWH(1.0 - top - height, left, height, width);
        break;
      case 180:
        rotated = Rect.fromLTWH(
          1.0 - left - width,
          1.0 - top - height,
          width,
          height,
        );
        break;
      default:
        rotated = Rect.fromLTWH(left, top, width, height);
    }

    final mirrored = mirrorX
        ? Rect.fromLTWH(
            1.0 - rotated.left - rotated.width,
            rotated.top,
            rotated.width,
            rotated.height,
          )
        : rotated;

    return Rect.fromLTRB(
      mirrored.left.clamp(0.0, 1.0),
      mirrored.top.clamp(0.0, 1.0),
      mirrored.right.clamp(0.0, 1.0),
      mirrored.bottom.clamp(0.0, 1.0),
    );
  }

  /// Maps a full-preview 0–1 rect into the visible [BoxFit.cover] viewport.
  static Rect sourceToCoverViewport({
    required Rect face,
    required double sourceAspect,
    required Size viewport,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0 || sourceAspect <= 0) {
      return face;
    }

    final containerAspect = viewport.width / viewport.height;
    if (sourceAspect > containerAspect) {
      final visibleW = containerAspect / sourceAspect;
      final padX = (1.0 - visibleW) * 0.5;
      return Rect.fromLTWH(
        (face.left - padX) / visibleW,
        face.top,
        face.width / visibleW,
        face.height,
      );
    }

    final visibleH = sourceAspect / containerAspect;
    final padY = (1.0 - visibleH) * 0.5;
    return Rect.fromLTWH(
      face.left,
      (face.top - padY) / visibleH,
      face.width,
      face.height / visibleH,
    );
  }

  /// Front [CameraPreview] is mirrored. Pose checks should use raw ML Kit yaw
  /// (positive Y = looking toward the camera's right = user turning left).
  static double? previewYaw(double? yaw, {required bool mirrorX}) {
    if (yaw == null) {
      return null;
    }
    return mirrorX ? -yaw : yaw;
  }
}
