import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'confirmation_page.dart';
import 'appointments_page.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'user_session.dart';
import 'api_config.dart';

class HairstyleDetailPage extends StatefulWidget {
  final Map<String, dynamic> style;

  const HairstyleDetailPage({required this.style, super.key});

  @override
  State<HairstyleDetailPage> createState() => _HairstyleDetailPageState();
}

class _HairstyleDetailPageState extends State<HairstyleDetailPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final Map<String, Future<Uint8List>> _webImageCache = {};
  bool _isFavorite = false;
  bool _savingFavorite = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _loadFavoriteStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  bool _hasImage(String? url) {
    return url != null && url.isNotEmpty;
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

  int? _getVariantId() {
    final value = widget.style['variantId'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _loadFavoriteStatus() async {
    final userId = UserSession.userId;
    final variantId = _getVariantId();
    if (userId == null || variantId == null) {
      return;
    }
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'status', 'userID': userId, 'variantID': variantId}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _isFavorite = data['isFavorite'] == true);
    } catch (_) {
      // Ignore
    }
  }

  Future<void> _toggleFavorite() async {
    final userId = UserSession.userId;
    final variantId = _getVariantId();
    if (userId == null || variantId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login required to save haircuts.')),
      );
      return;
    }
    if (_savingFavorite) return;
    setState(() => _savingFavorite = true);
    try {
      final action = _isFavorite ? 'remove' : 'add';
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/favorites.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'userID': userId, 'variantID': variantId}),
      );
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() => _isFavorite = !_isFavorite);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFavorite ? 'Saved to bookmarks.' : 'Removed from bookmarks.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update saved haircuts.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update saved haircuts: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingFavorite = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Large image with gradient overlay
              Container(
                height: 380,
                decoration: const BoxDecoration(color: Color(0xFF0A0A0A)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_hasImage(widget.style['image']?.toString()))
                      kIsWeb
                          ? _buildWebImage(widget.style['image'].toString())
                          : Image(image: _buildImageProvider(widget.style['image'].toString()), fit: BoxFit.cover)
                    else
                      Container(color: const Color(0xFF111111)),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title with icon
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.style['name']?.toString() ?? 'Style',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Color(0xFFA99941), size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.style['rating']?.toString() ?? '★★★★★',
                                    style: const TextStyle(color: Color(0xFFA99941), fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _savingFavorite ? null : _toggleFavorite,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isFavorite ? Colors.white : Colors.transparent,
                                      foregroundColor: _isFavorite ? Colors.black : Colors.white,
                                      side: const BorderSide(color: Colors.white, width: 1),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                    icon: Icon(_isFavorite ? Icons.bookmark : Icons.bookmark_border, size: 18),
                                    label: Text(_isFavorite ? 'Saved' : 'Save'),
                                  ),
                                  if (_savingFavorite)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 10),
                                      child: SizedBox(
                                        height: 14,
                                        width: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Preview Details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Why This Works For You',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...((widget.style['details']?.toString() ?? '').split('\n').where((line) => line.trim().isNotEmpty).map(
                            (detail) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      detail,
                                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Buttons
                    ElevatedButton(
                      onPressed: () {
                        final variantId = widget.style['variantId'];
                        if (variantId is int) {
                          UserSession.selectedVariantId = variantId;
                          UserSession.selectedStyleName = widget.style['name']?.toString();
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ConfirmationPage(
                              frontViewUrl: widget.style['frontViewUrl']?.toString(),
                              sideViewUrl: widget.style['sideViewUrl']?.toString(),
                              backViewUrl: widget.style['backViewUrl']?.toString(),
                              styleName: widget.style['name']?.toString() ?? 'Style',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: Colors.white.withOpacity(0.3),
                      ),
                      child: const Text(
                        'Confirm and Proceed',
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
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        side: const BorderSide(color: Colors.white, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Choose Another',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // Bottom Navigation
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage()));
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppointmentsPage()));
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AiFaceScanPage()));
          } else if (index == 3) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SavedHaircutsPage()),
            );
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }
}
