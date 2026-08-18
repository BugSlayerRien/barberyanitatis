import 'dart:ui';

/// Position checks for the 3-angle capture flow.
///
/// ML Kit detection and these gates are separate: a detected face can still
/// be rejected here. Thresholds are sized for a typical arm's-length selfie,
/// not a locked-in pose.
class StagingFaceValidation {
  StagingFaceValidation._();

  static const int holdFrames = 8;
  static const int missDecay = 2;

  static const double minArea = 0.05;
  static const double maxArea = 0.42;
  static const double kioskMinArea = 0.04;

  static const double minCenterX = 0.18;
  static const double maxCenterX = 0.82;
  static const double minCenterY = 0.10;
  static const double maxCenterY = 0.86;

  /// Side poses must be a real turn, not a slight glance, and not a full profile.
  static const double minSideYaw = 18;
  static const double maxSideYaw = 75;

  static bool yawMatchesStage({
    required double? yaw,
    required double requiredYaw,
    required double tolerance,
  }) {
    if (requiredYaw.abs() < 15) {
      return yaw == null || yaw.abs() <= tolerance;
    }
    if (yaw == null) {
      return false;
    }
    if (yaw.abs() < minSideYaw || yaw.abs() > maxSideYaw) {
      return false;
    }
    return (yaw - requiredYaw).abs() <= tolerance;
  }

  static bool isWellPositioned({
    required Rect face,
    required double? yaw,
    required double requiredYaw,
    required double tolerance,
    bool kioskMode = false,
  }) {
    final cx = face.center.dx;
    final cy = face.center.dy;
    final area = face.width * face.height;
    final min = kioskMode ? kioskMinArea : minArea;
    return cx >= minCenterX &&
        cx <= maxCenterX &&
        cy >= minCenterY &&
        cy <= maxCenterY &&
        area >= min &&
        area <= maxArea &&
        yawMatchesStage(
          yaw: yaw,
          requiredYaw: requiredYaw,
          tolerance: tolerance,
        );
  }

  static String rejectReason({
    required Rect face,
    required double? yaw,
    required double requiredYaw,
    required double tolerance,
    required String fallbackHint,
    bool kioskMode = false,
  }) {
    final area = face.width * face.height;
    final min = kioskMode ? kioskMinArea : minArea;
    if (area < min) {
      return 'Move a little closer.';
    }
    if (area > maxArea) {
      return 'Move a little farther back.';
    }
    final cx = face.center.dx;
    final cy = face.center.dy;
    if (cx < minCenterX ||
        cx > maxCenterX ||
        cy < minCenterY ||
        cy > maxCenterY) {
      return 'Keep your face more toward the center.';
    }
    if (!yawMatchesStage(
      yaw: yaw,
      requiredYaw: requiredYaw,
      tolerance: tolerance,
    )) {
      if (requiredYaw.abs() < 15) {
        return 'Look straight at the camera.';
      }
      if (yaw == null) {
        return 'Hold still so we can read your head angle.';
      }
      if (yaw.abs() < minSideYaw) {
        return requiredYaw > 0
            ? 'Turn your face more to the left.'
            : 'Turn your face more to the right.';
      }
      if (yaw.sign != 0 && yaw.sign != requiredYaw.sign) {
        return requiredYaw > 0
            ? 'Turn the other way: left, not right.'
            : 'Turn the other way: right, not left.';
      }
      if (requiredYaw > 0) {
        return 'Turn your face more to the left.';
      }
      return 'Turn your face more to the right.';
    }
    return fallbackHint;
  }
}
