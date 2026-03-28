import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dashboard_page.dart';
import 'scan_results_page.dart';
import 'widgets/app_top_bar.dart';
import 'api_config.dart';
import 'user_session.dart';
import 'web_camera_view_stub.dart'
  if (dart.library.html) 'web_camera_view.dart';


class AiFaceScanPage extends StatefulWidget {
  const AiFaceScanPage({super.key});

  @override
  State<AiFaceScanPage> createState() => _AiFaceScanPageState();
}

class _AiFaceScanPageState extends State<AiFaceScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _scanImage;
  Uint8List? _scanBytes;
  CameraController? _cameraController;
  final WebCameraController _webCamera = WebCameraController();
  bool _cameraReady = false;
  bool _isSubmitting = false;
  bool _isStartingCamera = false;
  String _statusMessage = 'Ready to scan.';
  String? _debugMessage;
  bool _isGeneratingPreview = false;
  String? _generatedImageUrl;
  String? _generatedImageBase64;
  String _aiStatusLabel = 'AI status: checking...';
  bool? _aiStatusOk;

  @override
  void initState() {
    super.initState();
    _loadAiStatus();
  }

  Future<void> _initializeCamera(ResolutionPreset preset) async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() => _cameraReady = false);
      }
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw Exception('No camera found on this device.');
    }
    final frontCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.isNotEmpty ? cameras.first : cameras.first,
    );
    _cameraController = CameraController(frontCamera, preset, enableAudio: false);
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera preview failed. Use Take Photo to capture instead.')),
      );
    } finally {
      _isStartingCamera = false;
    }
  }

  Future<void> _captureWebFallback() async {
    try {
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not available on this browser.')),
      );
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
      await _captureWebFallback();
      return;
    }

    final file = await _picker.pickImage(source: ImageSource.camera);
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

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
    if (file == null) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _scanImage = file;
      _scanBytes = null;
      _statusMessage = 'Photo selected from gallery.';
      _debugMessage = 'Gallery image selected.';
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _webCamera.stop();
    super.dispose();
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
    if (kIsWeb && _scanBytes != null) {
      await _uploadScan(null, bytes: _scanBytes!);
      return;
    }

    final file = _scanImage ?? XFile.fromData(_scanBytes!);
    await _uploadScan(file);
  }

  Future<void> _uploadScan(XFile? file, {Uint8List? bytes}) async {
    if (mounted) {
      setState(() => _isSubmitting = true);
    }
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      );
      if (kIsWeb) {
        final payload = bytes ?? await file!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          payload,
          filename: (file?.name.isNotEmpty ?? false) ? file!.name : 'scan.jpg',
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('image', file!.path));
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

      UserSession.lastScan = data;
      UserSession.lastRecommendations = recommendations;
      setState(() {
        _statusMessage = 'Scan complete. Found ${recommendations.length} recommendations.';
        _debugMessage = 'HTTP ${response.statusCode} | keys: ${data.keys.join(', ')}';
      });
      final imageUrl = data['imageUrl']?.toString() ?? '';
      final summary = data['summary']?.toString();
      if (!mounted) return;
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

  Future<void> _generateLowFadePreview(String imageUrl) async {
    if (imageUrl.isEmpty) {
      setState(() => _debugMessage = 'Missing imageUrl for AI preview.');
      return;
    }
    if (_isGeneratingPreview) return;
    setState(() {
      _isGeneratingPreview = true;
      _statusMessage = 'Generating AI low-fade preview...';
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_tryon.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'instantId',
          'prompt': 'Apply a low fade haircut. Keep same person and background.',
          'imageUrl': imageUrl,
          'negativePrompt': 'blurry, low quality, distorted face',
        }),
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
        final error = data['error']?.toString() ?? 'AI preview failed';
        final details = data['details']?.toString();
        final hint = data['hint']?.toString();
        final parts = [error];
        if (details != null && details.isNotEmpty) {
          parts.add(details);
        }
        if (hint != null && hint.isNotEmpty) {
          parts.add(hint);
        }
        setState(() => _debugMessage = 'AI preview failed (${response.statusCode}) | ${parts.join(' ')}');
        return;
      }
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      final generatedUrl = data['imageUrl']?.toString();
      final generatedBase64 = data['imageBase64']?.toString();
      if ((generatedUrl == null || generatedUrl.isEmpty) && (generatedBase64 == null || generatedBase64.isEmpty)) {
        setState(() => _debugMessage = 'AI preview did not return an image.');
        return;
      }
      setState(() {
        _generatedImageUrl = generatedUrl;
        _generatedImageBase64 = generatedBase64;
        _statusMessage = 'AI preview ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _debugMessage = 'AI preview exception: $e');
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPreview = false);
      }
    }
  }

  Future<void> _loadAiStatus() async {
    try {
      final response = await http.get(Uri.parse('${ApiConfig.baseUrl}/ai_status.php'));
      if (response.statusCode != 200 || response.body.isEmpty) {
        if (!mounted) return;
        setState(() {
          _aiStatusLabel = 'AI status: unavailable';
          _aiStatusOk = false;
        });
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final scan = data['scan'] as Map<String, dynamic>? ?? {};
      final tryon = data['tryon'] as Map<String, dynamic>? ?? {};
      final scanEnabled = scan['enabled'] == true;
      final tryonConfigured = tryon['configured'] == true;
      if (!mounted) return;
      setState(() {
        _aiStatusOk = scanEnabled || tryonConfigured;
        _aiStatusLabel = 'AI status: ${_aiStatusOk == true ? 'ready' : 'limited'}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiStatusLabel = 'AI status: unavailable';
        _aiStatusOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AI Face & Hair Scan',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get personalized hairstyle recommendations by scanning your face. This helps match '
              'face shape, hair texture, and style preferences with high accuracy.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _aiStatusOk == true ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: _aiStatusOk == true ? Colors.greenAccent : Colors.orangeAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(_aiStatusLabel, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: (kIsWeb && !_cameraReady && _scanBytes == null && _scanImage == null) ? _startCamera : null,
              child: Container(
                height: 190,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Center(
                  child: _scanBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(_scanBytes!, fit: BoxFit.cover, width: double.infinity, height: 190),
                        )
                      : (_scanImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: kIsWeb
                                  ? Image.network(_scanImage!.path, fit: BoxFit.cover, width: double.infinity, height: 190)
                                  : Image.file(File(_scanImage!.path), fit: BoxFit.cover, width: double.infinity, height: 190),
                            )
                          : (kIsWeb && _cameraReady)
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: WebCameraView(controller: _webCamera),
                                )
                              : const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.center_focus_strong, size: 44, color: Colors.white),
                                    SizedBox(height: 10),
                                    Text('Tap to start camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 6),
                                    Text('Keep your face centered and well-lit', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  ],
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
                    _isSubmitting ? 'Running scan... $_statusMessage' : _statusMessage,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Run Scan'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _pickImage,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('Upload From Gallery'),
            ),
            const SizedBox(height: 18),
            if (_isGeneratingPreview) ...[
              const SizedBox(height: 6),
              const Text('Generating AI preview...', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
            if (_generatedImageBase64 != null || _generatedImageUrl != null) ...[
              const SizedBox(height: 14),
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _generatedImageBase64 != null
                      ? Image.memory(base64Decode(_generatedImageBase64!), fit: BoxFit.cover)
                      : kIsWeb
                          ? Image.network(_generatedImageUrl!, fit: BoxFit.cover)
                          : Image.network(_generatedImageUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 6),
              const Text('AI generated low-fade preview', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
            _infoCard('Scan Tips', [
              'Face the camera directly with neutral expression.',
              'Use good lighting and remove hats or sunglasses.',
              'Keep hair visible around the forehead and sides.',
            ]),
            const SizedBox(height: 12),
            _infoCard('Privacy', [
              'Your scan is used only for hairstyle recommendations.',
              'You can choose manual upload anytime.',
            ]),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DashboardPage()),
                );
              },
              child: const Text('Skip for now', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String title, List<String> items) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
