import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DetectedFaceFrame {
  final Rect boundingBox;
  final Size imageSize;
  final double? headEulerAngleY;
  final double? headEulerAngleZ;

  const DetectedFaceFrame({
    required this.boundingBox,
    required this.imageSize,
    this.headEulerAngleY,
    this.headEulerAngleZ,
  });
}

class FaceDetectorService {
  late final FaceDetector _faceDetector;

  Future<void> initialize() async {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableLandmarks: true,
        enableContours: false,
        enableTracking: true,
      ),
    );
  }

  Future<DetectedFaceFrame?> processFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    final inputImage = _toInputImage(image, sensorOrientation);
    if (inputImage == null) {
      return null;
    }

    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) {
      return null;
    }

    final face = faces.first;
    return DetectedFaceFrame(
      boundingBox: face.boundingBox,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
    );
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      return null;
    }

    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) {
      return null;
    }

    final bytes = _concatenatePlanes(image.planes);
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final buffer = BytesBuilder(copy: false);
    for (final plane in planes) {
      buffer.add(plane.bytes);
    }
    return buffer.takeBytes();
  }

  Future<void> dispose() async {
    await _faceDetector.close();
  }
}
