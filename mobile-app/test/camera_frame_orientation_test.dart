import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/scanner/camera_frame_orientation.dart';
import 'package:tatis_barbershop/user/scanner/device_orientation_tracker.dart';

void main() {
  // Typical Android front camera.
  const frontSensor = 270;

  int rotationFor(DeviceOrientation orientation) {
    return CameraFrameOrientation.mlKitRotationDegrees(
      sensorOrientation: frontSensor,
      deviceOrientation: orientation,
      lensDirection: CameraLensDirection.front,
    );
  }

  group('ML Kit rotation', () {
    test('portrait and landscape need different compensation', () {
      // The kiosk bug in one assertion: a landscape device fed the portrait
      // value gets an image 90 degrees out, and ML Kit finds no face.
      expect(rotationFor(DeviceOrientation.portraitUp), 270);
      expect(rotationFor(DeviceOrientation.landscapeLeft), 0);
      expect(rotationFor(DeviceOrientation.landscapeRight), 180);
      expect(
        rotationFor(DeviceOrientation.landscapeLeft),
        isNot(rotationFor(DeviceOrientation.portraitUp)),
      );
    });

    test('every orientation maps to a rotation ML Kit accepts', () {
      for (final orientation in DeviceOrientation.values) {
        for (final lens in [
          CameraLensDirection.front,
          CameraLensDirection.back,
        ]) {
          final degrees = CameraFrameOrientation.mlKitRotationDegrees(
            sensorOrientation: frontSensor,
            deviceOrientation: orientation,
            lensDirection: lens,
          );
          expect([0, 90, 180, 270], contains(degrees),
              reason: '$orientation / $lens produced $degrees');
        }
      }
    });

    test('front and back lenses compensate in opposite directions', () {
      int back(DeviceOrientation o) => CameraFrameOrientation.mlKitRotationDegrees(
            sensorOrientation: 90,
            deviceOrientation: o,
            lensDirection: CameraLensDirection.back,
          );
      expect(back(DeviceOrientation.landscapeLeft), 0);
      expect(back(DeviceOrientation.portraitUp), 90);
    });
  });

  group('landscape detection', () {
    test('classifies both landscape orientations', () {
      expect(
          CameraFrameOrientation.isLandscape(DeviceOrientation.landscapeLeft),
          isTrue);
      expect(
          CameraFrameOrientation.isLandscape(DeviceOrientation.landscapeRight),
          isTrue);
      expect(CameraFrameOrientation.isLandscape(DeviceOrientation.portraitUp),
          isFalse);
    });
  });

  group('DeviceOrientationTracker', () {
    tearDown(() => DeviceOrientationTracker.debugSet(null));

    test('reports null until the platform says otherwise', () {
      DeviceOrientationTracker.debugSet(null);
      expect(DeviceOrientationTracker.latest, isNull);
    });

    test('retains the last platform orientation', () {
      DeviceOrientationTracker.debugSet(DeviceOrientation.landscapeRight);
      expect(DeviceOrientationTracker.latest, DeviceOrientation.landscapeRight);
    });
  });

  group('preview layout', () {
    const preview = Size(1280, 720);

    test('landscape keeps the camera size, portrait swaps it', () {
      expect(
        CameraFrameOrientation.previewLayoutSize(
            preview, DeviceOrientation.landscapeLeft),
        preview,
      );
      expect(
        CameraFrameOrientation.previewLayoutSize(
            preview, DeviceOrientation.portraitUp),
        const Size(720, 1280),
      );
    });
  });
}
