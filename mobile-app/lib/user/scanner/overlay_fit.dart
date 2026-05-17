import 'package:flutter/material.dart';

import 'cover_viewport.dart';
import 'overlay_models.dart';

const double kOverlayTargetFaceAreaWeb = 0.145;
const double kOverlayTargetFaceAreaMobile = 0.165;

String pickOverlayImageForYaw(OverlayImageSet set, double? yawDeg) {
  final yaw = yawDeg ?? 0;
  if (yaw >= 12) {
    return set.left;
  }
  if (yaw <= -12) {
    return set.right;
  }
  return set.front;
}

OverlayBox computeOverlayBox({
  required Rect face,
  required BoxConstraints constraints,
  required OverlayCalibration calibration,
  required bool isWeb,
  required double? headYaw,
  required double? headRoll,
  required double? foreheadAnchorY,
  required double? eyeMidX,
  required double? eyeDistanceNorm,
  double? sourceAspect,
}) {
  var mappedFace = face;
  var mappedEyeMidX = eyeMidX;
  var mappedEyeDistanceNorm = eyeDistanceNorm;
  var mappedForeheadAnchorY = foreheadAnchorY;

  // Face rects are in raw camera/photo space; map through BoxFit.cover crop.
  if (sourceAspect != null && sourceAspect > 0) {
    final mapped = CoverViewportMapper.map(
      face: face,
      sourceAspect: sourceAspect,
      constraints: constraints,
      foreheadAnchorY: foreheadAnchorY,
      eyeMidX: eyeMidX,
      eyeDistanceNorm: eyeDistanceNorm,
    );
    mappedFace = mapped.face;
    mappedEyeMidX = mapped.eyeMidX;
    mappedEyeDistanceNorm = mapped.eyeDistanceNorm;
    mappedForeheadAnchorY = mapped.foreheadAnchorY;
  }

  final faceWidth = mappedFace.width * constraints.maxWidth;
  final faceHeight = mappedFace.height * constraints.maxHeight;
  final faceAspect = (mappedFace.width / mappedFace.height).clamp(0.55, 1.35);

  final faceAreaNorm = (mappedFace.width * mappedFace.height).clamp(0.03, 0.45);
  final targetArea =
      isWeb ? kOverlayTargetFaceAreaWeb : kOverlayTargetFaceAreaMobile;

  // Don't render overlay if face is too small (too far from camera)
  if (faceAreaNorm < 0.06) {
    return OverlayBox(
      left: 0,
      top: 0,
      width: 0,
      height: 0,
      yawScale: 1.0,
    );
  }

  final distanceFactor = (targetArea / faceAreaNorm).clamp(0.72, 1.28);
  final distanceVerticalFactor =
      1.0 + ((faceAreaNorm - targetArea) * 1.2).clamp(-0.12, 0.18);

  final slimFaceNorm = ((0.90 - faceAspect) / 0.40).clamp(0.0, 1.0);
  final wideFaceNorm = ((faceAspect - 0.82) / 0.35).clamp(0.0, 1.0);
  final nearCameraNorm =
    ((faceAreaNorm - targetArea) / targetArea).clamp(0.0, 1.0);
  final farCameraNorm =
    ((targetArea - faceAreaNorm) / targetArea).clamp(0.0, 1.0);

  final adaptiveWidthBoost =
    (1.0 + (slimFaceNorm * 0.22) - (wideFaceNorm * 0.08));
  final adaptiveHeightBoost =
    (1.0 + (wideFaceNorm * 0.16) + (slimFaceNorm * 0.04));
  final distanceWidthComp =
    (1.0 + (farCameraNorm * 0.12) - (nearCameraNorm * 0.06));
  final distanceHeightComp =
    (1.0 + (nearCameraNorm * 0.10) + (farCameraNorm * 0.06));

  final yawDeg = headYaw ?? 0;
  final yawAbsNorm = (yawDeg.abs() / 45.0).clamp(0.0, 1.0);
  final yawWidthFactor = (1.0 - (yawAbsNorm * 0.30)).clamp(0.62, 1.0);
  final yawHeightFactor = (1.0 - (yawAbsNorm * 0.12)).clamp(0.85, 1.0);
  final yawHorizontalShift = yawDeg.sign * yawAbsNorm * 0.08;

    final eyeDistNorm =
      (mappedEyeDistanceNorm ?? (mappedFace.width * 0.42)).clamp(0.05, 0.70);
  final eyeDistPx = eyeDistNorm * constraints.maxWidth;
  final widthFromEyes = eyeDistPx * 2.65;
  final eyeWidthBlend = isWeb ? 0.66 : 0.58;

  final rollDeg = headRoll ?? 0;
  final rollNorm = (rollDeg.abs() / 25.0).clamp(0.0, 1.0);
  final rollTiltFactor = rollDeg.sign;

  final width = faceWidth *
      calibration.widthScale *
      distanceFactor *
      adaptiveWidthBoost *
      distanceWidthComp *
      yawWidthFactor *
      (1.0 - (rollNorm * 0.04));
    final eyeAnchoredWidth =
      (width * (1.0 - eyeWidthBlend)) + (widthFromEyes * eyeWidthBlend);

  final height = faceHeight *
      calibration.heightScale *
      distanceFactor *
      adaptiveHeightBoost *
      distanceHeightComp *
      yawHeightFactor *
      (1.0 + (rollNorm * 0.03));

    final clampedWidth = (eyeAnchoredWidth * (1.0 - (yawAbsNorm * 0.08)))
      .clamp(faceWidth * 0.80, faceWidth * 1.92);
    final clampedHeight = height.clamp(faceHeight * 0.95, faceHeight * 2.05);

    final anchorXNorm =
      (mappedEyeMidX ?? (mappedFace.left + (mappedFace.width * 0.5)))
        .clamp(0.0, 1.0);
  final faceCenterX = anchorXNorm * constraints.maxWidth;
  final xOffsetPx = faceWidth * (calibration.xOffset + yawHorizontalShift);
  final sideBias = yawDeg.sign * yawAbsNorm * clampedWidth * 0.10;
    final left = (faceCenterX - (clampedWidth * 0.5) + xOffsetPx + sideBias)
      .clamp(-clampedWidth * 0.45, constraints.maxWidth - (clampedWidth * 0.55));

  double anchorYNorm;
  if (mappedForeheadAnchorY != null) {
    anchorYNorm = mappedForeheadAnchorY.clamp(0.0, 1.0);
  } else {
    anchorYNorm = (mappedFace.top + (mappedFace.height * 0.06)).clamp(0.0, 1.0);
  }

  final yawAnchorShift = -yawAbsNorm * 0.02 * yawDeg.sign;
  final adjustedAnchorYNorm = (anchorYNorm + yawAnchorShift).clamp(0.02, 0.32);
  final anchorY = adjustedAnchorYNorm * constraints.maxHeight;

  final yOffsetFactor =
      (mappedForeheadAnchorY != null && mappedEyeMidX != null) ? 0.35 : 0.85;

  // hairClipFactor = fraction of overlay height above the forehead anchor (hairline in PNG).
  final hairAnchorRatio = calibration.hairClipFactor.clamp(0.50, 0.66);

  final topRaw = anchorY -
      (clampedHeight * hairAnchorRatio) +
      (faceHeight * calibration.yOffset * distanceVerticalFactor * yOffsetFactor) +
      (rollTiltFactor * rollNorm * faceHeight * 0.01);

  final top = topRaw
      .clamp(-clampedHeight * 0.42, constraints.maxHeight - (clampedHeight * 0.12));

  return OverlayBox(
    left: left.toDouble(),
    top: top.toDouble(),
    width: clampedWidth.toDouble(),
    height: clampedHeight.toDouble(),
    yawScale: yawWidthFactor,
  );
}
