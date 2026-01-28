import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dashboard_page.dart';
import 'quiz_upload.dart';
import 'widgets/app_top_bar.dart';

class AiFaceScanPage extends StatefulWidget {
  const AiFaceScanPage({super.key});

  @override
  State<AiFaceScanPage> createState() => _AiFaceScanPageState();
}

class _AiFaceScanPageState extends State<AiFaceScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _scanImage;

  Future<void> _startScan() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera cancelled.')),
      );
      return;
    }

    setState(() {
      _scanImage = file;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan captured. Uploading to AI...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
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
