import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'attachment_engine.dart';
import 'overlay_asset_cache.dart';
import 'overlay_fit.dart';
import 'overlay_models.dart';
import 'overlay_registry.dart';

/// Composites hairstyle overlays onto captured JPEGs (used when saving for appointments).
class FaceScanCompositor {
  static Future<Map<String, String>> compositeAllAngles({
    required Map<String, String> capturesBase64,
    required String styleName,
    Map<String, Rect>? faceRectsByAngle,
  }) async {
    final overlaySet = OverlayRegistry.resolve(styleName);
    final calibration = OverlayRegistry.calibrationFor(styleName);
    final output = <String, String>{};

    for (final angle in ['front', 'left', 'right']) {
      final captureB64 = capturesBase64[angle];
      if (captureB64 == null || captureB64.isEmpty) continue;

      final yaw = OverlayRegistry.yawForCaptureAngle(angle);
      final assetPath = pickOverlayImageForYaw(overlaySet, yaw);
      final faceRect = faceRectsByAngle?[angle] ??
          OverlayRegistry.normalizedFaceFallback(angle);

      final faceBytes = base64Decode(captureB64);
      final overlayBytes = await OverlayAssetCache.loadBytes(assetPath);
      final composited = _compositeWithPlacement(
        faceBytes: faceBytes,
        overlayBytes: overlayBytes,
        imageWidth: 0,
        imageHeight: 0,
        faceRect: faceRect,
        calibration: calibration,
        headYaw: yaw,
      );
      output[angle] = base64Encode(composited);
    }
    return output;
  }

  static Uint8List _compositeWithPlacement({
    required List<int> faceBytes,
    required Uint8List overlayBytes,
    required int imageWidth,
    required int imageHeight,
    required Rect faceRect,
    required OverlayCalibration calibration,
    required double headYaw,
  }) {
    final face = img.decodeImage(Uint8List.fromList(faceBytes));
    final overlay = img.decodeImage(overlayBytes);
    if (face == null || overlay == null) {
      throw Exception('Unable to decode images for compositing');
    }

    final w = face.width.toDouble();
    final h = face.height.toDouble();
    final constraints = BoxConstraints(maxWidth: w, maxHeight: h);

    final engine = createAttachmentEngine(AttachmentEngineMode.heuristic);
    final box = engine.compute(
      AttachmentInput(
        face: faceRect,
        constraints: constraints,
        calibration: calibration,
        isWeb: false,
        headYaw: headYaw,
        headRoll: 0,
        foreheadAnchorY: faceRect.top + (faceRect.height * 0.06),
        eyeMidX: faceRect.left + (faceRect.width * 0.5),
        eyeDistanceNorm: faceRect.width * 0.42,
        sourceAspect: w / h,
        faceTransformMatrix: null,
        calibrationOffsets: const AttachmentCalibrationOffsets(),
      ),
    );

    final canvas = img.copyResize(face, width: face.width, height: face.height);
    final targetW = box.width.round().clamp(8, face.width);
    final targetH = box.height.round().clamp(8, face.height);
    final resizedOverlay = img.copyResize(
      overlay,
      width: targetW,
      height: targetH,
    );

    img.compositeImage(
      canvas,
      resizedOverlay,
      dstX: box.left.round().clamp(0, face.width - 1),
      dstY: box.top.round().clamp(0, face.height - 1),
    );

    return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
  }
}
