import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dashboard_page.dart';
import 'quiz_upload.dart';
import 'widgets/app_top_bar.dart';
import 'api_config.dart';
import 'scan_results_page.dart';
import 'user_session.dart';
import 'web_camera_picker.dart';

class AiFaceScanPage extends StatefulWidget {
  const AiFaceScanPage({super.key});

  @override
  State<AiFaceScanPage> createState() => _AiFaceScanPageState();
}

class _AiFaceScanPageState extends State<AiFaceScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _scanImage;

  Future<void> _startScan() async {
    if (kIsWeb) {
      final supported = await isWebCameraSupported();
      if (!supported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Web camera requires https/localhost and permission. Use upload instead.')),
        );
        return;
      }
    }

    final file = kIsWeb
        ? await pickWebCameraImage()
        : await _picker.pickImage(source: ImageSource.camera);
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera cancelled or not supported.')),
      );
      return;
    }

    setState(() => _scanImage = file);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan captured. Uploading to AI...')),
    );

    await _uploadScan(file);
  }

  Future<void> _uploadScan(XFile file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/ai_scan.php'),
      );
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: file.name,
        ));
      } else {
        request.files.add(await http.MultipartFile.fromPath('image', file.path));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'AI scan failed.')),
        );
        return;
      }

      final recommendations = (data['recommendations'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      UserSession.lastScan = data;
      UserSession.lastRecommendations = recommendations;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanResultsPage(
            imageUrl: data['imageUrl']?.toString() ?? '',
            recommendations: recommendations,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI scan failed: $e')),
      );
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
            if (kIsWeb) ...[
              const SizedBox(height: 6),
              const Text(
                'Web camera requires https or localhost permission.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              height: 190,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Center(
                child: _scanImage == null
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.center_focus_strong, size: 44, color: Colors.white),
                          SizedBox(height: 10),
                          Text('Start AI Face Scan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('Keep your face centered and well-lit', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, size: 40, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(
                            _scanImage!.name,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text('Scan ready', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startScan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Start Scan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const QuizUploadPage()),
                );
              },
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: const Text('Upload Photo Instead'),
            ),
            const SizedBox(height: 18),
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
