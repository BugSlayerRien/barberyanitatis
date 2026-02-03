// Web-only camera view/controller.
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

class WebCameraController {
  html.VideoElement? _video;
  html.MediaStream? _stream;
  String? _viewType;

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

    return true;
  }

  Future<void> stop() async {
    _video?.pause();
    _video?.srcObject = null;
    _stream?.getTracks().forEach((track) => track.stop());
    _stream = null;
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
}

class WebCameraView extends StatelessWidget {
  final WebCameraController controller;

  const WebCameraView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return controller.buildView();
  }
}
