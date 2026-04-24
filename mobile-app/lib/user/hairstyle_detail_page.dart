import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_funnel_service.dart';
import 'appointments_page.dart';
import 'barber_selection_page.dart';
import 'booking_guard.dart';
import 'dashboard_page.dart';
import 'profile_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'suggested_appointment_page.dart';
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
  bool _bookingInFlight = false;

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

  Future<Map<String, dynamic>?> _fetchSuggestedSlot() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'suggestBestSlot'}),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return {
          '_error': true,
          '_message': 'Unable to check available times right now.',
        };
      }
      if (response.body.isEmpty) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['suggestion'] as Map<String, dynamic>?;
    } catch (_) {
      return {
        '_error': true,
        '_message': 'Unable to check available times right now. Please try again.',
      };
    }
  }

  Future<void> _proceedToBookingFlow() async {
    final hasActive = await BookingGuard.hasActiveAppointment(userId: UserSession.userId);
    if (!mounted) {
      return;
    }
    if (hasActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You already have an active appointment.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AppointmentsPage()),
      );
      return;
    }

    setState(() => _bookingInFlight = true);
    final suggestion = await _fetchSuggestedSlot();
    if (mounted) {
      setState(() => _bookingInFlight = false);
    }

    if (!mounted) {
      return;
    }

    if (suggestion != null && suggestion['_error'] == true) {
      final message = suggestion['_message']?.toString() ?? 'Unable to check available times right now.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    if (suggestion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No open times available right now. You can still try this haircut.')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuggestedAppointmentPage(suggestion: suggestion),
      ),
    );
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

                    const SizedBox(height: 16),

                    // Buttons
                    ElevatedButton(
                      onPressed: _bookingInFlight
                          ? null
                          : () async {
                        final variantId = widget.style['variantId'] ?? widget.style['variantID'];
                        int? normalizedVariantId;
                        if (variantId is int) {
                          normalizedVariantId = variantId;
                        } else {
                          normalizedVariantId = int.tryParse(variantId?.toString() ?? '');
                        }

                        if (normalizedVariantId == null || normalizedVariantId <= 0) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('This haircut cannot be booked yet. Please choose another style.')),
                          );
                          return;
                        }

                        UserSession.selectedVariantId = normalizedVariantId;
                        UserSession.selectedStyleName = widget.style['name']?.toString();
                        UserSession.selectedEstimatedMinutes = int.tryParse(widget.style['estimatedMinutes']?.toString() ?? '');

                        final userId = UserSession.userId;
                        if (userId != null) {
                          try {
                            await AiFunnelService.saveSelection(
                              scanSessionId: UserSession.ensureScanSessionId(),
                              userId: userId,
                              variantId: normalizedVariantId,
                              styleName: UserSession.selectedStyleName ?? 'Style',
                              faceShape: UserSession.lastScan?['faceShape']?.toString(),
                              hairTexture: UserSession.lastScan?['hairTexture']?.toString(),
                              hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
                              hairLength: UserSession.lastScan?['hairLength']?.toString(),
                              estimatedMinutes: UserSession.selectedEstimatedMinutes,
                            );
                          } catch (_) {
                            // Do not block booking flow if tracking fails.
                          }
                        }

                        if (!context.mounted) {
                          return;
                        }
                        await _proceedToBookingFlow();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 8,
                        shadowColor: Colors.white.withOpacity(0.3),
                      ),
                      child: Text(
                        _bookingInFlight ? 'Checking slots...' : 'Confirm and Proceed',
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
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Try Haircut',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.4),
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
