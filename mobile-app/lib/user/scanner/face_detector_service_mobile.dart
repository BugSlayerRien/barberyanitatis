import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('[FaceDetectorService] Already initialized, skipping');
      return;
    }
    
    try {
      debugPrint('[FaceDetectorService] Initializing FaceDetector...');
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: false,
          enableContours: false,
          enableTracking: true,
        ),
      );
      _initialized = true;
      debugPrint('[FaceDetectorService] FaceDetector initialized successfully');
    } catch (e, st) {
      debugPrint('[FaceDetectorService] Initialization error: $e\nStackTrace: $st');
      rethrow;
    }
  }

  Future<DetectedFaceFrame?> processFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (!_initialized) {
      debugPrint('[FaceDetectorService] Not initialized yet');
      return null;
    }
    
    try {
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
    } catch (e, st) {
      debugPrint('[FaceDetectorService] Processing error: $e\nStackTrace: $st');
      return null;
    }
  }

  InputImage? _toInputImage(CameraImage image, int sensorOrientation) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      debugPrint('[FaceDetectorService] Unsupported image format: ${image.format.raw}');
      return null;
    }

    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) {
      debugPrint('[FaceDetectorService] Invalid sensor orientation: $sensorOrientation');
      return null;
    }

    try {
      if (image.planes.isEmpty) {
        debugPrint('[FaceDetectorService] CameraImage has no planes');
        return null;
      }

      final bool isSinglePlane = image.planes.length == 1;
      final Uint8List bytes = isSinglePlane
          ? image.planes.first.bytes
          : _concatenatePlanes(image.planes);
      final int bytesPerRow = image.planes.first.bytesPerRow;
      
      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (e, st) {
      debugPrint('[FaceDetectorService] Image conversion error: $e\nStackTrace: $st');
      return null;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final buffer = BytesBuilder(copy: false);
    for (final plane in planes) {
      buffer.add(plane.bytes);
    }
    return buffer.takeBytes();
  }

  Future<void> dispose() async {
    if (_initialized) {
      await _faceDetector.close();
      _initialized = false;
      debugPrint('[FaceDetectorService] Disposed');
    }
  }
}
