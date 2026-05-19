// Web-only camera view/controller.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';
import 'dart:ui_web' as ui;

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

  WebFaceTrackingState copyWith({
    Rect? faceRect,
    double? headYaw,
    double? headRoll,
    double? eyeMidY,
    double? eyeMidX,
    double? eyeDistanceNorm,
    double? videoAspect,
    List<double>? faceTransformMatrix,
    bool? trackerReady,
    bool? trackerSupported,
    bool clearFace = false,
  }) {
    return WebFaceTrackingState(
      faceRect: clearFace ? null : (faceRect ?? this.faceRect),
      headYaw: clearFace ? null : (headYaw ?? this.headYaw),
      headRoll: clearFace ? null : (headRoll ?? this.headRoll),
      eyeMidY: clearFace ? null : (eyeMidY ?? this.eyeMidY),
      eyeMidX: clearFace ? null : (eyeMidX ?? this.eyeMidX),
      eyeDistanceNorm:
          clearFace ? null : (eyeDistanceNorm ?? this.eyeDistanceNorm),
      videoAspect: clearFace ? null : (videoAspect ?? this.videoAspect),
      faceTransformMatrix:
          clearFace ? null : (faceTransformMatrix ?? this.faceTransformMatrix),
      trackerReady: trackerReady ?? this.trackerReady,
      trackerSupported: trackerSupported ?? this.trackerSupported,
    );
  }
}

class WebCameraController {
  html.VideoElement? _video;
  html.MediaStream? _stream;
  String? _viewType;
  Timer? _trackingTimer;

  final ValueNotifier<WebFaceTrackingState> tracking =
      ValueNotifier<WebFaceTrackingState>(const WebFaceTrackingState());

  bool get isStreaming => _stream != null;

  Future<bool> start() async {
    if (_stream != null) {
      return true;
    }
    final media = html.window.navigator.mediaDevices;
    if (media == null) {
      return false;
    }

    _stream = await media.getUserMedia({
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
      'audio': false,
    });

    _video = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..style.width = '100%'
      ..style.height = '100%'
      ..srcObject = _stream;
    _video!.setAttribute('playsinline', 'true');

    _viewType = 'webcam-${DateTime.now().microsecondsSinceEpoch}';
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType!, (int viewId) => _video!);

    await _video!.play();
    await _waitForVideoDimensions(_video!);
    await _initFaceTracker();
    _startTrackingLoop();

    return true;
  }

  Future<void> _waitForVideoDimensions(html.VideoElement video) async {
    for (var attempt = 0; attempt < 80; attempt++) {
      if (video.videoWidth > 0 && video.videoHeight > 0) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> stop() async {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _video?.pause();
    _video?.srcObject = null;
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
    tracking.value = tracking.value.copyWith(clearFace: true);
  }

  Future<void> _initFaceTracker() async {
    try {
      if (js.context['initTatisFaceTracker'] == null) {
        throw StateError('initTatisFaceTracker is not defined. Check web/index.html MediaPipe scripts.');
      }
      js.context['tatisFaceTrackerReady'] = false;
      js.context.callMethod('initTatisFaceTracker');
      for (var attempt = 0; attempt < 300; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (js.context['tatisFaceTrackerReady'] == true) {
          tracking.value = tracking.value.copyWith(
            trackerReady: true,
            trackerSupported: true,
          );
          return;
        }
      }
      throw StateError('Face tracker init timed out. Check network access to MediaPipe CDN.');
    } catch (e) {
      debugPrint('[WebCamera] Face tracker init failed: $e');
      tracking.value = tracking.value.copyWith(
        trackerReady: false,
        trackerSupported: false,
        clearFace: true,
      );
    }
  }

  void _startTrackingLoop() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      _estimateFace();
    });
  }

  void _estimateFace() {
    final video = _video;
    if (video == null || _stream == null) {
      return;
    }

    try {
      final result = js.context.callMethod('tatisEstimateFace', [video]);
      if (result == null) {
        return;
      }

      if (result is! js.JsObject) {
        return;
      }

      final status = (result['status'] as String?)?.toLowerCase();
      if (status == 'stale') {
        return;
      }
      if (status == 'no_face' || status == 'error') {
        tracking.value = tracking.value.copyWith(clearFace: true);
        return;
      }

      final bbox = result['bbox'];
      if (bbox == null) {
        tracking.value = tracking.value.copyWith(clearFace: true);
        return;
      }

      if (bbox is! js.JsObject) {
        tracking.value = tracking.value.copyWith(clearFace: true);
        return;
      }

      final left = ((bbox['left'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
      final top = ((bbox['top'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
      final width = ((bbox['width'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
      final height = ((bbox['height'] as num?) ?? 0).toDouble().clamp(0.0, 1.0);
      final yaw = ((result['yaw'] as num?) ?? 0).toDouble();
      final roll = ((result['roll'] as num?) ?? 0).toDouble();
      final eyeMidY = ((result['eyeMidY'] as num?) ?? (top + (height * 0.36))).toDouble().clamp(0.0, 1.0);
      final eyeMidX = ((result['eyeMidX'] as num?) ?? (left + (width * 0.5)))
          .toDouble()
          .clamp(0.0, 1.0);
      final eyeDistanceNorm =
          ((result['eyeDistanceNorm'] as num?) ?? (width * 0.42))
              .toDouble()
              .clamp(0.04, 0.65);
      final videoAspect = (video.videoHeight <= 0)
          ? (16 / 9)
          : (video.videoWidth / video.videoHeight).clamp(0.3, 4.0);
        final faceTransformMatrix =
          _toDoubleList(result['transformMatrix'], expectedLength: 16);

      tracking.value = tracking.value.copyWith(
        faceRect: Rect.fromLTWH(left, top, width, height),
        headYaw: yaw,
        headRoll: roll,
        eyeMidY: eyeMidY,
        eyeMidX: eyeMidX,
        eyeDistanceNorm: eyeDistanceNorm,
        videoAspect: videoAspect,
        faceTransformMatrix: faceTransformMatrix,
      );
    } catch (_) {
      return;
    }
  }

  Future<Uint8List?> capture() async {
    if (_video == null || _stream == null) {
      return null;
    }
    final width = _video!.videoWidth;
    final height = _video!.videoHeight;
    if (width == 0 || height == 0) {
      return null;
    }

    final canvas = html.CanvasElement(width: width, height: height);
    final ctx = canvas.context2D;
    ctx.drawImage(_video!, 0, 0);
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.9);
    final base64Data = dataUrl.split(',').last;
    return Uint8List.fromList(base64Decode(base64Data));
  }

  Widget buildView() {
    if (_viewType == null) {
      return const SizedBox.shrink();
    }
    return HtmlElementView(viewType: _viewType!);
  }

  List<double>? _toDoubleList(dynamic value, {required int expectedLength}) {
    if (value == null || value is! js.JsObject) {
      return null;
    }

    final out = <double>[];
    for (var i = 0; i < expectedLength; i++) {
      final item = value[i];
      if (item is! num) {
        return null;
      }
      out.add(item.toDouble());
    }
    return out;
  }
}

class WebCameraView extends StatelessWidget {
  final WebCameraController controller;

  const WebCameraView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return controller.buildView();
  }
}
