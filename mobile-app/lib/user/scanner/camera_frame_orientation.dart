import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared camera / ML Kit orientation math for portrait (customer) and
/// landscape (kiosk) UIs.
///
/// Android ML Kit rotation must include device orientation. Passing only
/// [CameraDescription.sensorOrientation] works in portrait and fails in
/// landscape. Preview layout must match [CameraPreview]'s own landscape check.
class CameraFrameOrientation {
  CameraFrameOrientation._();

  static const Map<DeviceOrientation, int> _deviceDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static bool isLandscape(DeviceOrientation orientation) {
    return orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
  }

  /// Same orientation [CameraPreview] uses for AspectRatio + Android RotatedBox.
  static DeviceOrientation previewOrientation(CameraController controller) {
    final value = controller.value;
    if (value.isRecordingVideo && value.recordingOrientation != null) {
      return value.recordingOrientation!;
    }
    return value.previewPauseOrientation ??
        value.lockedCaptureOrientation ??
        value.deviceOrientation;
  }

  static DeviceOrientation landscapeLockTarget(CameraController controller) {
    final current = controller.value.deviceOrientation;
    return isLandscape(current) ? current : DeviceOrientation.landscapeLeft;
  }

  /// Degrees to pass as ML Kit [InputImage] rotation.
  static int mlKitRotationDegrees({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required CameraLensDirection lensDirection,
  }) {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS) {
      return sensorOrientation % 360;
    }

    final compensation = _deviceDegrees[deviceOrientation] ?? 0;
    if (lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + compensation) % 360;
    }
    return (sensorOrientation - compensation + 360) % 360;
  }

  static int mlKitRotationDegreesFor(CameraController controller) {
    return mlKitRotationDegrees(
      sensorOrientation: controller.description.sensorOrientation,
      deviceOrientation: previewOrientation(controller),
      lensDirection: controller.description.lensDirection,
    );
  }

  /// Size of [CameraPreview]'s AspectRatio child before BoxFit.cover.
  static Size previewLayoutSize(
    Size previewSize,
    DeviceOrientation orientation,
  ) {
    if (isLandscape(orientation)) {
      return previewSize;
    }
    return Size(previewSize.height, previewSize.width);
  }

  static Size previewLayoutSizeFor(CameraController controller) {
    final preview = controller.value.previewSize;
    if (preview == null) {
      return Size.zero;
    }
    return previewLayoutSize(preview, previewOrientation(controller));
  }
}
