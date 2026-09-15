import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_frame_orientation.dart';

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
  late final FaceDetector _faceDetector;
  bool _initialized = false;
  /// One line per session, not one per frame — this runs at camera frame rate.
  bool _loggedFrameShape = false;

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
          enableLandmarks: true,
          enableContours: true,
          enableClassification: false,
          enableTracking: true,
          minFaceSize: 0.07,
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
    DeviceOrientation deviceOrientation = DeviceOrientation.portraitUp,
    CameraLensDirection lensDirection = CameraLensDirection.front,
  }) async {
    if (!_initialized) {
      debugPrint('[FaceDetectorService] Not initialized yet');
      return null;
    }
    
    try {
      final rotationDegrees = CameraFrameOrientation.mlKitRotationDegrees(
        sensorOrientation: sensorOrientation,
        deviceOrientation: deviceOrientation,
        lensDirection: lensDirection,
      );
      final inputImage = _toInputImage(image, rotationDegrees);
      if (inputImage == null) {
        return null;
      }

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        return null;
      }

      final face = faces.first;
      final landmarks = <int, Map<String, double>>{};
      for (final entry in face.landmarks.entries) {
        final landmark = entry.value;
        if (landmark == null) {
          continue;
        }
        final position = landmark.position;
        landmarks[entry.key.index] = <String, double>{
          'x': (position.x / image.width).clamp(0.0, 1.0).toDouble(),
          'y': (position.y / image.height).clamp(0.0, 1.0).toDouble(),
        };
      }

      final faceContourPoints = face.contours[FaceContourType.face]?.points;
      final faceContour = faceContourPoints
          ?.map((point) => <String, double>{
                'x': (point.x / image.width).clamp(0.0, 1.0).toDouble(),
                'y': (point.y / image.height).clamp(0.0, 1.0).toDouble(),
              })
          .toList();

      return DetectedFaceFrame(
        boundingBox: face.boundingBox,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        headEulerAngleY: face.headEulerAngleY,
        headEulerAngleZ: face.headEulerAngleZ,
        landmarks: landmarks.isEmpty ? null : landmarks,
        faceContour: (faceContour == null || faceContour.isEmpty)
            ? null
            : faceContour,
      );
    } catch (e, st) {
      debugPrint('[FaceDetectorService] Processing error: $e\nStackTrace: $st');
      return null;
    }
  }

  InputImage? _toInputImage(CameraImage image, int rotationDegrees) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) {
      debugPrint('[FaceDetectorService] Unsupported image format: ${image.format.raw}');
      return null;
    }

    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) {
      debugPrint('[FaceDetectorService] Invalid image rotation: $rotationDegrees');
      return null;
    }

    try {
      if (image.planes.isEmpty) {
        debugPrint('[FaceDetectorService] CameraImage has no planes');
        return null;
      }

      // No copy needed: camera_android's ImageStreamReader already reads each
      // plane into a fresh byte[] before closing the image, so this buffer is
      // ours. On Android the nv21 format group yields a single plane.
      final bool isSinglePlane = image.planes.length == 1;
      final Uint8List bytes = isSinglePlane
          ? image.planes.first.bytes
          : _concatenatePlanes(image.planes);
      final int bytesPerRow = image.planes.first.bytesPerRow;

      if (bytes.isEmpty) {
        debugPrint('[FaceDetectorService] Empty frame buffer, skipping');
        return null;
      }

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      );

      if (!_loggedFrameShape) {
        _loggedFrameShape = true;
        debugPrint(
          '[FaceDetectorService] frame shape: ${image.width}x${image.height} '
          'planes=${image.planes.length} bytes=${bytes.length} '
          'bytesPerRow=$bytesPerRow rawFormat=${image.format.raw} '
          'format=$format rotation=$rotation',
        );
      }

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (e, st) {
      debugPrint('[FaceDetectorService] Image conversion error: $e\nStackTrace: $st');
      return null;
    }
  }

  /// Copies by design: the result outlives the camera frame it came from.
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final buffer = BytesBuilder();
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
