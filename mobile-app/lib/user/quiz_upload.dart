import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dashboard_page.dart';
import 'api_config.dart';
import 'scan_results_page.dart';
import 'user_session.dart';
import 'web_camera_view_stub.dart'
  if (dart.library.html) 'web_camera_view.dart';

class QuizUploadPage extends StatefulWidget {
  const QuizUploadPage({super.key});

  @override
  State<QuizUploadPage> createState() => _QuizUploadPageState();
}

class _QuizUploadPageState extends State<QuizUploadPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _scanImage;
  Uint8List? _scanBytes;
  final WebCameraController _webCamera = WebCameraController();
  bool _cameraReady = false;
  bool _isSubmitting = false;
  bool _isStartingCamera = false;
  String _statusMessage = 'Ready to scan.';
  String? _debugMessage;

  @override
  void dispose() {
    _webCamera.stop();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (!kIsWeb) {
      setState(() {
        _statusMessage = 'Opening camera...';
        _debugMessage = 'Start camera requested (non-web).';
      });
      return;
    }
    if (_isStartingCamera) {
      return;
    }
    _isStartingCamera = true;
    try {
      setState(() => _debugMessage = 'Start camera requested (web).');
      final started = await _webCamera.start();
      if (!mounted) return;
      setState(() => _cameraReady = started);
      if (started) {
        setState(() => _statusMessage = 'Camera started.');
      }
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web camera unavailable. Use Take Photo to capture instead.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera preview failed. Use Take Photo to capture instead.')),
      );
    } finally {
      _isStartingCamera = false;
    }
  }

  Future<void> _pickImage() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
    if (img != null) {
      setState(() {
        _scanImage = img;
        _scanBytes = null;
        _statusMessage = 'Photo selected from gallery.';
          _debugMessage = 'Gallery image selected.';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (kIsWeb) {
      if (_webCamera.isStreaming) {
        final bytes = await _webCamera.capture();
        if (bytes == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Capture failed. Try again.')),
          );
          return;
        }
        if (!mounted) return;
        setState(() {
          _scanImage = null;
          _scanBytes = bytes;
          _statusMessage = 'Photo captured from camera.';
          _debugMessage = 'Captured image from web camera stream.';
        });
        return;
      }
      final file = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1200, maxHeight: 1200);
      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera capture cancelled or not supported.')),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _scanImage = file;
        _scanBytes = null;
        _statusMessage = 'Photo captured from camera.';
        _debugMessage = 'Captured image using browser camera picker.';
      });
      return;
    }

    final file = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1200, maxHeight: 1200);
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera cancelled or not supported.')),
      );
      return;
    }
    setState(() {
      _scanImage = file;
      _scanBytes = null;
      _statusMessage = 'Photo captured from camera.';
      _debugMessage = 'Captured image from device camera.';
    });
  }

  Future<void> _submitScan() async {
    if (_scanImage == null && _scanBytes == null) {
      if (kIsWeb && _webCamera.isStreaming) {
        final bytes = await _webCamera.capture();
        if (bytes != null) {
          if (!mounted) return;
          setState(() {
            _scanImage = null;
            _scanBytes = bytes;
            _statusMessage = 'Photo captured from camera.';
          });
        }
      }
    }

    if (_scanImage == null && _scanBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture a photo first.')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan captured. Uploading to AI...')),
    );
    setState(() {
      _statusMessage = 'Uploading scan to AI...';
      _debugMessage = 'Submitting scan to ai_scan.php';
    });

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      );
      if (kIsWeb && _scanBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          _scanBytes!,
          filename: 'scan.jpg',
        ));
      } else if (kIsWeb) {
        final bytes = await _scanImage!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: _scanImage!.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('image', _scanImage!.path));
      }
      if (UserSession.userId != null) {
        request.fields['userID'] = UserSession.userId.toString();
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;

        final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};
      if (response.statusCode != 200) {
        final details = data['details']?.toString();
        final message = details != null && details.isNotEmpty
            ? '${data['error']?.toString() ?? 'AI scan failed.'} ($details)'
            : (data['error']?.toString() ?? 'AI scan failed.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        setState(() {
          _statusMessage = message;
          _debugMessage = 'HTTP ${response.statusCode} | body: ${response.body}';
        });
        return;
      }

        final recommendations = (data['recommendations'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
        final imageUrl = data['imageUrl']?.toString() ?? '';
        final summary = data['summary']?.toString();

      UserSession.lastScan = data;
      UserSession.lastRecommendations = recommendations;
      setState(() {
        _statusMessage = 'Scan complete. Found ${recommendations.length} recommendations.';
        _debugMessage = 'HTTP ${response.statusCode} | keys: ${data.keys.join(', ')}';
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScanResultsPage(
            imageUrl: imageUrl,
            recommendations: recommendations,
            summary: summary,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI scan failed: $e')),
      );
      setState(() {
        _statusMessage = 'AI scan failed: $e';
        _debugMessage = 'Exception: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const DashboardPage()),
                            (route) => false,
                          );
                        },
                        child: const Text('Skip', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ],
                  ),
                  // Progress bar
                  const LinearProgressIndicator(
                    value: 1.0,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text('Step 3 of 3', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text('AI Face & Hair Scan', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text(
                    'Scan your face to get your best haircut match',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: (kIsWeb && !_cameraReady && _scanBytes == null && _scanImage == null) ? _startCamera : null,
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _scanBytes != null
                            ? Image.memory(_scanBytes!, fit: BoxFit.cover, width: double.infinity, height: 180)
                            : (_scanImage != null
                                ? (kIsWeb
                                    ? Image.network(_scanImage!.path, fit: BoxFit.cover, width: double.infinity, height: 180)
                                    : Image.file(File(_scanImage!.path), fit: BoxFit.cover, width: double.infinity, height: 180))
                                : (kIsWeb && _cameraReady)
                                    ? WebCameraView(controller: _webCamera)
                                    : const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.center_focus_strong, size: 40, color: Colors.white),
                                            SizedBox(height: 8),
                                            Text('Tap to start camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            SizedBox(height: 4),
                                            Text('Position your face within the frame', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                          ],
                                        ),
                                      )),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white54, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _isSubmitting ? 'Running scan... ${_statusMessage}' : _statusMessage,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Center(
                    child: InkResponse(
                      onTap: _isSubmitting ? null : _capturePhoto,
                      radius: 32,
                      child: Container(
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.black, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitScan,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(44)),
                    child: const Text('Run Scan'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _pickImage,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: Text(_scanImage == null && _scanBytes == null ? 'Upload Photo Instead' : 'Change Upload'),
                  ),

                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
