import 'dart:ui';

import 'package:camera/camera.dart';

class DetectedFaceFrame {
  final Rect boundingBox;
  final Size imageSize;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;
  final Map<int, Map<String, double>>? landmarks;
  final List<Map<String, double>>? faceContour;

  const DetectedFaceFrame({
    required this.boundingBox,
    required this.imageSize,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.landmarks,
    this.faceContour,
  });
}

class FaceDetectorService {
  Future<void> initialize() async {}

  Future<DetectedFaceFrame?> processFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    return null;
  }

  Future<void> dispose() async {}
}
