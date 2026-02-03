import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../config/api_config.dart';
import 'recommendations_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  XFile? _image;
  Uint8List? _capturedBytes;
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (!kIsWeb) {
      return;
    }
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.isNotEmpty ? cameras.first : CameraDescription(
          name: 'webcam',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
      );
      _cameraController = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Camera init failed: $e');
    }
  }

  Future<void> _startCamera() async {
    if (_cameraReady) return;
    setState(() => _error = null);
    await _initCamera();
  }

  Future<void> _captureFromCamera() async {
    if (kIsWeb) {
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        setState(() => _error = 'Start camera first.');
        return;
      }
      final file = await _cameraController!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _capturedBytes = bytes;
        _image = null;
        _error = null;
      });
      return;
    }
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _image = image;
        _capturedBytes = null;
        _error = null;
      });
    }
  }

  Future<void> _runScan() async {
    if (_image == null && _capturedBytes == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = _capturedBytes ?? await _image!.readAsBytes();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageBase64': base64Encode(bytes)}),
      );

      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Scan failed.';
          _loading = false;
        });
        return;
      }

      final recommendations = (data['recommendations'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() => _loading = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecommendationsScreen(
            imageBytes: bytes,
            recommendations: recommendations,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Scan failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Scan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: _capturedBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(_capturedBytes!, fit: BoxFit.cover),
                      )
                    : (_image != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: kIsWeb
                                ? Image.network(_image!.path, fit: BoxFit.cover)
                                : Image.file(File(_image!.path), fit: BoxFit.cover),
                          )
                        : (kIsWeb && _cameraReady && _cameraController != null)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CameraPreview(_cameraController!),
                              )
                            : const Center(
                                child: Text('Start camera to preview', style: TextStyle(color: Colors.white54)),
                              )),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _loading ? null : (kIsWeb ? _startCamera : _captureFromCamera),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(kIsWeb ? 'Start Camera' : 'Capture'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loading ? null : _captureFromCamera,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                    child: const Text('Take Photo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _runScan,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                child: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Text('Run Scan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
