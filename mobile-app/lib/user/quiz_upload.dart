import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dashboard_page.dart';
import 'api_config.dart';
import 'scan_results_page.dart';
import 'user_session.dart';
import 'web_camera_picker.dart';

class QuizUploadPage extends StatefulWidget {
  const QuizUploadPage({super.key});

  @override
  State<QuizUploadPage> createState() => _QuizUploadPageState();
}

class _QuizUploadPageState extends State<QuizUploadPage> {
  XFile? _picked;
  bool _isSubmitting = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? img = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000, maxHeight: 1000);
    if (img != null) setState(() => _picked = img);
  }

  Future<void> _captureImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      if (kIsWeb) {
        final supported = await isWebCameraSupported();
        if (!supported) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Web camera requires https/localhost and permission. Use Upload if unavailable.')),
          );
          return;
        }
      }

      final XFile? img = kIsWeb
          ? await pickWebCameraImage()
          : await picker.pickImage(source: ImageSource.camera, maxWidth: 1000, maxHeight: 1000);
      if (img != null) setState(() => _picked = img);
      if (kIsWeb && img == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera capture cancelled or not supported on this browser.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera not available on this device.')),
      );
    }
  }

  Future<void> _uploadScan() async {
    if (_picked == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo first.')),
      );
      return;
    }

    if (mounted) {
      setState(() => _isSubmitting = true);
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      );
      if (kIsWeb) {
        final bytes = await _picked!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: _picked!.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('image', _picked!.path));
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
        return;
      }

        final recommendations = (data['recommendations'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
        final imageUrl = data['imageUrl']?.toString() ?? '';

      UserSession.lastScan = data;
      UserSession.lastRecommendations = recommendations;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScanResultsPage(
            imageUrl: imageUrl,
            recommendations: recommendations,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI scan failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
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
                  const Text('AI FACE SCAN', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text('Scan your face to get your best haircut match', style: TextStyle(color: Colors.white70)),
                  if (kIsWeb) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Web camera requires https or localhost permission.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _picked == null
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.center_focus_strong, size: 40, color: Colors.white),
                                  SizedBox(height: 8),
                                  Text('Start AI Face Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  SizedBox(height: 4),
                                  Text('Position your face within the frame', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            )
                          : kIsWeb
                              ? Image.network(_picked!.path, fit: BoxFit.cover, width: double.infinity, height: 180)
                              : Image.file(File(_picked!.path), fit: BoxFit.cover, width: double.infinity, height: 180),
                    ),
                  ),

                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _captureImage,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.camera_alt, size: 18),
                    label: const Text('Start Camera Scan'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: Text(_picked == null ? 'Upload Photo' : 'Change Upload'),
                  ),

                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _uploadScan,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
                          child: _isSubmitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text('SUBMIT'),
                        ),
                      ),
                    ],
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
