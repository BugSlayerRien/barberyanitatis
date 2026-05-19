import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'attachment_engine.dart';
import 'overlay_asset_cache.dart';
import 'overlay_fit.dart';
import 'overlay_preview_image.dart';
import 'overlay_registry.dart';

/// Live-scanner-style preview: captured photo + positioned overlay (no JPEG re-encode).
class StaticFacePreview extends StatefulWidget {
  final String captureBase64;
  final String angleKey;
  final String styleName;
  final Rect? normalizedFaceRect;
  final double headYaw;

  const StaticFacePreview({
    super.key,
    required this.captureBase64,
    required this.angleKey,
    required this.styleName,
    this.normalizedFaceRect,
    this.headYaw = 0,
  });

  @override
  State<StaticFacePreview> createState() => _StaticFacePreviewState();
}

class _StaticFacePreviewState extends State<StaticFacePreview> {
  double? _sourceAspect;

  @override
  void initState() {
    super.initState();
    _loadAspect();
  }

  @override
  void didUpdateWidget(StaticFacePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureBase64 != widget.captureBase64) {
      _loadAspect();
    }
  }

  void _loadAspect() {
    try {
      final bytes = base64Decode(widget.captureBase64);
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.height > 0) {
        setState(() {
          _sourceAspect = decoded.width / decoded.height;
        });
      }
    } catch (_) {
      // Fallback applied in build.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(widget.captureBase64);
    final overlaySet = OverlayRegistry.resolve(widget.styleName);
    final assetPath = pickOverlayImageForYaw(overlaySet, widget.headYaw);
    final calibration = OverlayRegistry.calibrationFor(widget.styleName);
    final face = widget.normalizedFaceRect ??
        OverlayRegistry.normalizedFaceFallback(widget.angleKey);
    final sourceAspect = _sourceAspect ?? (3 / 4);

    return LayoutBuilder(
      builder: (context, constraints) {
        final engine = createAttachmentEngine(AttachmentEngineMode.heuristic);
        final box = engine.compute(
          AttachmentInput(
            face: face,
            constraints: constraints,
            calibration: calibration,
            isWeb: false,
            headYaw: widget.headYaw,
            headRoll: 0,
            foreheadAnchorY: face.top + (face.height * 0.12),
            eyeMidX: face.left + (face.width * 0.5),
            eyeDistanceNorm: face.width * 0.42,
            sourceAspect: sourceAspect,
            faceTransformMatrix: null,
            calibrationOffsets: const AttachmentCalibrationOffsets(),
          ),
        );

        if (box.width <= 1 || box.height <= 1) {
          return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.cover, width: double.infinity),
            Positioned(
              left: box.left,
              top: box.top,
              width: box.width,
              height: box.height,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: OverlayPreviewImage(
                  assetPath: assetPath,
                  fit: BoxFit.fitWidth,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Warms overlay decode cache for a style (optional).
Future<void> warmOverlayForStyle(String styleName) async {
  final set = OverlayRegistry.resolve(styleName);
  for (final path in [set.front, set.left, set.right]) {
    await OverlayAssetCache.loadBytes(path);
  }
}
