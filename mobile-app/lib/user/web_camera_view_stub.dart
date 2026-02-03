import 'dart:typed_data';

import 'package:flutter/material.dart';

class WebCameraController {
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
