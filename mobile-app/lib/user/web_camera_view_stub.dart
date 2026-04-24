import 'dart:typed_data';

import 'package:flutter/material.dart';

class WebFaceTrackingState {
  final Rect? faceRect;
  final double? headYaw;
  final double? headRoll;
  final double? eyeMidY;
  final double? eyeMidX;
  final double? eyeDistanceNorm;
  final double? videoAspect;
  final List<double>? faceTransformMatrix;
  final bool trackerReady;
  final bool trackerSupported;

  const WebFaceTrackingState({
    this.faceRect,
    this.headYaw,
    this.headRoll,
    this.eyeMidY,
    this.eyeMidX,
    this.eyeDistanceNorm,
    this.videoAspect,
    this.faceTransformMatrix,
    this.trackerReady = false,
    this.trackerSupported = false,
  });
}

class WebCameraController {
  final ValueNotifier<WebFaceTrackingState> tracking =
      ValueNotifier<WebFaceTrackingState>(const WebFaceTrackingState());

  bool get isStreaming => false;

  Future<bool> start() async => false;

  Future<void> stop() async {}

  Future<Uint8List?> capture() async => null;
}

class WebCameraView extends StatelessWidget {
  final WebCameraController controller;

  const WebCameraView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Web camera not available',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}
