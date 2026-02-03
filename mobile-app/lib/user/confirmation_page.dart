import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'barber_selection_page.dart';
import 'dashboard_page.dart';
import 'payment_page.dart';
import 'api_config.dart';
import 'user_session.dart';

class ConfirmationPage extends StatefulWidget {
  final String? frontViewUrl;
  final String? sideViewUrl;
  final String? backViewUrl;
  final String styleName;

  const ConfirmationPage({
    super.key,
    this.frontViewUrl,
    this.sideViewUrl,
    this.backViewUrl,
    required this.styleName,
  });

  @override
  State<ConfirmationPage> createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends State<ConfirmationPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late List<Animation<double>> _scaleAnimations;
  late PageController _pageController;
  Uint8List? _generatedImage;
  bool _generating = false;
  String? _generateError;
  final Map<String, Future<Uint8List>> _webImageCache = {};
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this);

    _scaleAnimations = List.generate(
      3,
      (index) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(index * 0.15, 0.3 + (index * 0.15), curve: Curves.elasticOut),
        ),
      ),
    );

    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateAiPreview();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _generateAiPreview() async {
    if (_generating) {
      return;
    }
    final styleName = widget.styleName.trim();
    if (styleName.isEmpty) {
      return;
    }

    final faceShape = UserSession.lastScan?['faceShape']?.toString();
    final hairTexture = UserSession.lastScan?['hairTexture']?.toString();
    final hairColor = UserSession.lastScan?['hairColor']?.toString();
    final scanImageUrl = UserSession.lastScan?['imageUrl']?.toString() ?? '';
    final promptParts = <String>[
      'Portrait photo of a person with a $styleName haircut',
      'realistic, studio lighting',
    ];
    if (faceShape != null && faceShape.isNotEmpty) {
      promptParts.add('face shape: ${faceShape.toLowerCase()}');
    }
    if (hairTexture != null && hairTexture.isNotEmpty) {
      promptParts.add('hair texture: ${hairTexture.toLowerCase()}');
    }
    if (hairColor != null && hairColor.isNotEmpty) {
      promptParts.add('hair color: ${hairColor.toLowerCase()}');
    }
    final prompt = promptParts.join(', ');

    setState(() {
      _generating = true;
      _generateError = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/ai_tryon.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'instantId',
          'prompt': prompt,
          'imageUrl': scanImageUrl,
        }),
      );
      if (!mounted) {
        return;
      }
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        final details = data['details']?.toString();
        setState(() {
          _generateError = details != null && details.isNotEmpty
              ? '${data['error']?.toString() ?? 'Image generation failed.'} ($details)'
              : (data['error']?.toString() ?? 'Image generation failed.');
        });
        return;
      }
      final base64Image = data['imageBase64']?.toString() ?? '';
      if (base64Image.isEmpty) {
        setState(() {
          _generateError = 'No image returned from model.';
        });
        return;
      }
      setState(() {
        _generatedImage = base64Decode(base64Image);
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generateError = 'Image generation failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _generating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = [
      widget.sideViewUrl,
      widget.frontViewUrl,
      widget.backViewUrl,
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('AI Style Preview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.styleName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Preview how the hairstyle looks from different angles',
                    style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 28),

                  // Swipeable Images Carousel with Navigation Buttons
                  Column(
                    children: [
                      Row(
                        children: [
                          // Left Button
                          SizedBox(
                            width: 48,
                            height: 360,
                            child: Center(
                              child: GestureDetector(
                                onTap: () {
                                  _pageController.previousPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.chevron_left, color: Colors.black, size: 28),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Carousel
                          Expanded(
                            child: SizedBox(
                              height: 360,
                              child: PageView.builder(
                                controller: _pageController,
                                onPageChanged: (index) {
                                  setState(() {});
                                },
                                itemCount: images.length,
                                itemBuilder: (context, index) {
                                  final labels = ['Left Side', 'Front View', 'Right Side'];
                                  final imageUrl = images[index];
                                  return ScaleTransition(
                                    scale: _scaleAnimations[index],
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            imageUrl != null && imageUrl.isNotEmpty
                                                ? (kIsWeb
                                                    ? _buildWebImage(imageUrl)
                                                    : Image(image: _buildImageProvider(imageUrl), fit: BoxFit.cover))
                                                : Container(color: const Color(0xFF111111)),
                                            Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(14),
                                                gradient: LinearGradient(
                                                  begin: Alignment.bottomCenter,
                                                  end: Alignment.topCenter,
                                                  colors: [Colors.black.withOpacity(0.5), Colors.transparent],
                                                ),
                                              ),
                                            ),
                                            Stack(
                                              children: [
                                                Align(
                                                  alignment: Alignment.bottomCenter,
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(16),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        labels[index],
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 12,
                                                  right: 12,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.6),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      '${index + 1}/3',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right Button
                          SizedBox(
                            width: 48,
                            height: 360,
                            child: Center(
                              child: GestureDetector(
                                onTap: () {
                                  _pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.chevron_right, color: Colors.black, size: 28),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Use ← → buttons to see all angles',
                        style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Info box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF1A1A1A), const Color(0xFF252525)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.check_circle, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ready to Book?',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Schedule your appointment with one of our expert barbers',
                                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  ElevatedButton(
                    onPressed: _booking ? null : _showAutoBookingModal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 8,
                      shadowColor: Colors.white.withOpacity(0.3),
                    ),
                    child: const Text(
                      'Book Now',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const DashboardPage()),
                        (route) => false,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(56),
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'View Another Style',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ImageProvider _buildImageProvider(String url) {
    if (url.startsWith('assets/')) {
      return AssetImage(url);
    }
    return NetworkImage(url, webHtmlElementStrategy: WebHtmlElementStrategy.prefer);
  }

  Future<Uint8List> _fetchWebImageBytes(String url) {
    return _webImageCache.putIfAbsent(url, () async {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Image load failed (${response.statusCode})');
      }
      return response.bodyBytes;
    });
  }

  Widget _buildWebImage(String url) {
    return FutureBuilder<Uint8List>(
      future: _fetchWebImageBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(color: const Color(0xFF111111));
        }
        if (!snapshot.hasData) {
          return Container(color: const Color(0xFF111111));
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }

    Future<Map<String, dynamic>?> _fetchSuggestedSlot() async {
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'suggestBestSlot'}),
        );
        if (response.statusCode != 200 || response.body.isEmpty) {
          return null;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['suggestion'] as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }

    Future<Map<String, dynamic>?> _loadDefaultService() async {
      try {
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}/services.php'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'action': 'list'}),
        );
        if (response.statusCode != 200 || response.body.isEmpty) {
          return null;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final services = (data['services'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        return services.firstWhere(
          (service) => (service['category']?.toString() ?? '').toLowerCase() == 'haircut',
          orElse: () => services.isNotEmpty ? services.first : <String, dynamic>{},
        );
      } catch (_) {
        return null;
      }
    }

    Future<void> _showAutoBookingModal() async {
      if (UserSession.userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in again.')));
        return;
      }
      if (UserSession.selectedVariantId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a hairstyle before booking.')));
        return;
      }

      setState(() => _booking = true);
      final suggestion = await _fetchSuggestedSlot();
      setState(() => _booking = false);

      if (!mounted) return;
      if (suggestion == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No available slots found.')));
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
        );
        return;
      }

      showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF111111),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final barberName = suggestion['barberName']?.toString() ?? 'Barber';
          final slotDate = suggestion['slotDate']?.toString() ?? '';
          final slotTime = suggestion['slotTime']?.toString() ?? '';
          final availableCount = suggestion['availableCount']?.toString() ?? '';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Suggested Appointment',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _suggestionRow('Barber', barberName),
                  _suggestionRow('Date', slotDate),
                  _suggestionRow('Time', slotTime),
                  if (availableCount.isNotEmpty)
                    _suggestionRow('Open slots', availableCount),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 1),
                          ),
                          child: const Text('No, thanks'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _proceedAutoBooking(suggestion);
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                          child: const Text('Proceed', style: TextStyle(color: Colors.black)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    Widget _suggestionRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            Expanded(
              child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    Future<void> _proceedAutoBooking(Map<String, dynamic> suggestion) async {
      if (UserSession.userId == null || UserSession.selectedVariantId == null) {
        return;
      }
      final service = await _loadDefaultService();
      if (service == null || service.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No haircut service configured.')));
        return;
      }

      final barberId = suggestion['barberID'] is int
          ? suggestion['barberID'] as int
          : int.tryParse('${suggestion['barberID']}') ?? 0;
      final barberName = suggestion['barberName']?.toString() ?? 'Barber';
      final appointmentDate = suggestion['slotDate']?.toString() ?? '';
      final startTime = suggestion['slotTime']?.toString() ?? '';
      if (barberId <= 0 || appointmentDate.isEmpty || startTime.isEmpty) {
        return;
      }

      final serviceId = service['service_id'] as int;
      final price = double.tryParse(service['base_price']?.toString() ?? '') ?? 0;
      final duration = int.tryParse(service['base_duration']?.toString() ?? '') ?? 0;
      final endTime = _addMinutes(startTime, duration);

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'create',
          'userID': UserSession.userId,
          'barberID': barberId,
          'appointmentDate': appointmentDate,
          'startTime': startTime,
          'endTime': endTime,
          'serviceIDs': [serviceId],
          'variantID': UserSession.selectedVariantId,
        }),
      );

      if (!mounted) return;
      if (response.statusCode != 201) {
        final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Booking failed.')),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            barberName: barberName,
            date: appointmentDate,
            time: startTime,
            amount: price.round(),
            haircutName: UserSession.selectedStyleName ?? 'Haircut',
          ),
        ),
      );
    }

    String _addMinutes(String time, int minutes) {
      if (time.isEmpty) {
        return time;
      }
      final parts = time.split(':');
      if (parts.length < 2) {
        return time;
      }
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final total = hour * 60 + minute + minutes;
      final endHour = (total ~/ 60) % 24;
      final endMinute = total % 60;
      return '${endHour.toString().padLeft(2, '0')}:${endMinute.toString().padLeft(2, '0')}:00';
    }
}
