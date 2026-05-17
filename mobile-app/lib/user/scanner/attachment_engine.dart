import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'overlay_fit.dart';
import 'overlay_models.dart';

enum AttachmentEngineMode {
  auto,
  matrix,
  heuristic,
}

AttachmentEngineMode parseAttachmentEngineMode(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'matrix':
      return AttachmentEngineMode.matrix;
    case 'heuristic':
      return AttachmentEngineMode.heuristic;
    case 'auto':
    default:
      return AttachmentEngineMode.auto;
  }
}

String attachmentEngineModeLabel(AttachmentEngineMode mode) {
  switch (mode) {
    case AttachmentEngineMode.auto:
      return 'auto';
    case AttachmentEngineMode.matrix:
      return 'matrix';
    case AttachmentEngineMode.heuristic:
      return 'heuristic';
  }
}

AttachmentEngine createAttachmentEngine(AttachmentEngineMode mode) {
  switch (mode) {
    case AttachmentEngineMode.matrix:
      return const MatrixAttachmentEngine();
    case AttachmentEngineMode.heuristic:
      return const HeuristicAttachmentEngine();
    case AttachmentEngineMode.auto:
      return const MatrixAttachmentEngine();
  }
}

class AttachmentInput {
  final Rect face;
  final BoxConstraints constraints;
  final OverlayCalibration calibration;
  final bool isWeb;
  final double? headYaw;
  final double? headRoll;
  final double? foreheadAnchorY;
  final double? eyeMidX;
  final double? eyeDistanceNorm;
  final double? sourceAspect;
  final List<double>? faceTransformMatrix;
  final AttachmentCalibrationOffsets calibrationOffsets;

  const AttachmentInput({
    required this.face,
    required this.constraints,
    required this.calibration,
    required this.isWeb,
    required this.headYaw,
    required this.headRoll,
    required this.foreheadAnchorY,
    required this.eyeMidX,
    required this.eyeDistanceNorm,
    required this.sourceAspect,
    required this.faceTransformMatrix,
    required this.calibrationOffsets,
  });
}

class AttachmentCalibrationOffsets {
  final double offsetX;
  final double offsetY;
  final double scale;
  final double foreheadOffset;

  const AttachmentCalibrationOffsets({
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1.0,
    this.foreheadOffset = 0,
  });
}

abstract class AttachmentEngine {
  const AttachmentEngine();

  OverlayBox compute(AttachmentInput input);
}

class HeuristicAttachmentEngine extends AttachmentEngine {
  const HeuristicAttachmentEngine();

  @override
  OverlayBox compute(AttachmentInput input) {
    final box = computeOverlayBox(
      face: input.face,
      constraints: input.constraints,
      calibration: input.calibration,
      isWeb: input.isWeb,
      headYaw: input.headYaw,
      headRoll: input.headRoll,
      foreheadAnchorY: input.foreheadAnchorY,
      eyeMidX: input.eyeMidX,
      eyeDistanceNorm: input.eyeDistanceNorm,
      sourceAspect: input.sourceAspect,
    );
    return _applyCalibrationOffsets(box, input);
  }
}

class MatrixAttachmentEngine extends AttachmentEngine {
  final AttachmentEngine fallback;

  const MatrixAttachmentEngine({this.fallback = const HeuristicAttachmentEngine()});

  @override
  OverlayBox compute(AttachmentInput input) {
    final matrix = input.faceTransformMatrix;
    if (matrix == null || matrix.length < 16) {
      return fallback.compute(input);
    }

    final stabilized = _applyMatrixAnchor(input);

    final scaleX = math.sqrt((matrix[0] * matrix[0]) + (matrix[1] * matrix[1]));
    final scaleY = math.sqrt((matrix[4] * matrix[4]) + (matrix[5] * matrix[5]));
    final matrixScale = ((scaleX + scaleY) * 0.5).clamp(0.55, 1.55);
    final inferredRoll = math.atan2(matrix[1], matrix[0]) * (180 / math.pi);
    final tx = matrix[12].clamp(-1.5, 1.5);
    final ty = matrix[13].clamp(-1.5, 1.5);

    final adjustedCalibration = OverlayCalibration(
      widthScale: (input.calibration.widthScale * (1.0 + ((matrixScale - 1.0) * 0.14)))
          .clamp(0.90, 1.75)
          .toDouble(),
      heightScale:
          (input.calibration.heightScale * (1.0 + ((matrixScale - 1.0) * 0.11)))
              .clamp(0.98, 1.95)
              .toDouble(),
      xOffset: (input.calibration.xOffset + (tx * 0.035)).clamp(-0.16, 0.16).toDouble(),
      yOffset: (input.calibration.yOffset + (ty * 0.030)).clamp(-0.36, 0.10).toDouble(),
      hairClipFactor: input.calibration.hairClipFactor,
      visualScale: input.calibration.visualScale,
      yawShiftFactor: input.calibration.yawShiftFactor,
    );

    final box = computeOverlayBox(
      face: stabilized.face,
      constraints: input.constraints,
      calibration: adjustedCalibration,
      isWeb: input.isWeb,
      headYaw: input.headYaw,
      headRoll: input.headRoll ?? inferredRoll,
      foreheadAnchorY: input.foreheadAnchorY,
      eyeMidX: stabilized.eyeMidX,
      eyeDistanceNorm: stabilized.eyeDistanceNorm,
      sourceAspect: input.sourceAspect,
    );
    return _applyCalibrationOffsets(box, input);
  }

  _MatrixAnchorResult _applyMatrixAnchor(AttachmentInput input) {
    final matrix = input.faceTransformMatrix;
    if (matrix == null || matrix.length < 16) {
      return _MatrixAnchorResult(
        face: input.face,
        eyeMidX: input.eyeMidX,
        eyeDistanceNorm: input.eyeDistanceNorm,
      );
    }

    // Use the translation components as a gentle stabilizer so the overlay
    // does not drift laterally when the head turns.
    final tx = matrix[12].clamp(-1.5, 1.5);
    final ty = matrix[13].clamp(-1.5, 1.5);
    final shiftX = (tx * 0.06).clamp(-0.12, 0.12);
    final shiftY = (ty * 0.05).clamp(-0.10, 0.10);

    final face = input.face;
    final newLeft = (face.left + shiftX).clamp(0.0, 1.0 - face.width);
    final newTop = (face.top + shiftY).clamp(0.0, 1.0 - face.height);
    final anchoredFace = Rect.fromLTWH(newLeft, newTop, face.width, face.height);

    final eyeMidX = input.eyeMidX != null
        ? (input.eyeMidX! + shiftX).clamp(0.0, 1.0)
        : null;

    return _MatrixAnchorResult(
      face: anchoredFace,
      eyeMidX: eyeMidX,
      eyeDistanceNorm: input.eyeDistanceNorm,
    );
  }
}

class _MatrixAnchorResult {
  final Rect face;
  final double? eyeMidX;
  final double? eyeDistanceNorm;

  const _MatrixAnchorResult({
    required this.face,
    required this.eyeMidX,
    required this.eyeDistanceNorm,
  });
}

OverlayBox _applyCalibrationOffsets(OverlayBox base, AttachmentInput input) {
  final cal = input.calibrationOffsets;
  final scale = cal.scale.clamp(0.7, 1.3);
  final width = base.width * scale;
  final height = base.height * scale;

  final scaledLeft = base.left - ((width - base.width) * 0.5);
  final scaledTop = base.top - ((height - base.height) * 0.15);

  final left = scaledLeft + (width * cal.offsetX.clamp(-0.2, 0.2));
  final top = scaledTop +
      (height * cal.offsetY.clamp(-0.15, 0.15)) -
      (input.constraints.maxHeight * cal.foreheadOffset.clamp(-0.1, 0.1));

  return OverlayBox(
    left: left,
    top: top,
    width: width,
    height: height,
    yawScale: base.yawScale,
  );
}
