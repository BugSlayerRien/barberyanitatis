import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'hairstyle_detail_page.dart';
import 'appointments_page.dart';
import 'profile_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'haircuts_list_page.dart';
import 'ai_chatbot_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'api_config.dart';
import 'user_session.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0; // 0 = Recommended, 1 = Trendy (default: Recommended)
  int _selectedIndex = 0; // Home tab

  bool _showWelcome = true;
  Timer? _welcomeTimer;

  List<Map<String, dynamic>> _recommendedStyles = [];
  List<Map<String, dynamic>> _trendyStyles = [];
  bool _insightsLoading = true;
  Map<String, int> _paymentCounters = {
    'Unpaid': 0,
    'Verifying': 0,
    'Paid': 0,
    'Failed': 0,
  };
  String _queueSummary = 'Queue data unavailable';
  bool _loading = true;
  String? _error;
  static const String _dashboardSampleHairFront =
      'assets/images/overlays/blowout_taper/blowout_taper_front.png';

  static const Map<String, Map<String, String>> _localStyleAssets = {
    'blowout taper': {
      'front': 'assets/images/overlays/blowout_taper/blowout_taper_front.png',
      'side': 'assets/images/overlays/blowout_taper/blowout_taper_left.png',
      'back': 'assets/images/overlays/blowout_taper/blowout_taper_right.png',
    },
    'buzz cut': {
      'front': 'assets/images/overlays/buzz_cut/buzz_cut_front.png',
      'side': 'assets/images/overlays/buzz_cut/buzz_cut_left.png',
      'back': 'assets/images/overlays/buzz_cut/buzz_cut_right.png',
    },
    'low fade': {
      'front': 'assets/images/overlays/low_fade/low_fade_front.png',
      'side': 'assets/images/overlays/low_fade/low_fade_left.png',
      'back': 'assets/images/overlays/low_fade/low_fade_right.png',
    },
    'french crop': {
      'front': 'assets/images/overlays/french_crop/french_crop_front.png',
      'side': 'assets/images/overlays/french_crop/french_crop_left.png',
      'back': 'assets/images/overlays/french_crop/french_crop_right.png',
    },
  };

  String _styleIdentity(Map<String, dynamic> style) {
    final variantId = style['variantId']?.toString() ?? '';
    final styleName = style['name']?.toString().trim().toLowerCase() ?? '';
    return variantId.isNotEmpty ? 'variant:$variantId' : 'style:$styleName';
  }

  List<Map<String, dynamic>> _dedupeStyles(List<Map<String, dynamic>> styles) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final style in styles) {
      final key = _styleIdentity(style);
      if (seen.add(key)) {
        deduped.add(style);
      }
    }
    return deduped;
  }

  @override
  void initState() {
    super.initState();
    _loadStyles();
    _loadCustomerInsights();
    _welcomeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showWelcome = false;
      });
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStyles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final hasScan = UserSession.hasRecentRecommendations &&
      UserSession.lastRecommendations.isNotEmpty;
    final scanMapped = hasScan
        ? UserSession.lastRecommendations.map(_mapVariant).toList()
        : <Map<String, dynamic>>[];

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/haircuts.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'listByFaceShape'}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          final details = data['details']?.toString();
          _error = details != null && details.isNotEmpty
              ? '${data['error']?.toString() ?? 'Failed to load hairstyles.'} ($details)'
              : (data['error']?.toString() ?? 'Failed to load hairstyles.');
          _loading = false;
        });
        return;
      }

      final variants = (data['variants'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final mapped = variants.map(_mapVariant).toList();
      final dedupedMapped = _dedupeStyles(mapped);

      setState(() {
        if (hasScan) {
          final recommended = _dedupeStyles(scanMapped).take(3).toList();
          final recommendedKeys = recommended.map(_styleIdentity).toSet();
          final trendy = dedupedMapped
              .where((style) => !recommendedKeys.contains(_styleIdentity(style)))
              .toList();

          _recommendedStyles = recommended;
          _trendyStyles = trendy;
        } else {
          // No scan: Recommended is empty (will show placeholder), Trendy shows API results deduped
          _recommendedStyles = <Map<String, dynamic>>[];
          _trendyStyles = dedupedMapped;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load hairstyles: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadCustomerInsights() async {
    final userId = UserSession.userId;
    if (userId == null) {
      setState(() => _insightsLoading = false);
      return;
    }

    setState(() => _insightsLoading = true);

    try {
      final bookingResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/booking.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'listByCustomer', 'userID': userId}),
      );
      final bookingData = bookingResponse.body.isNotEmpty
          ? jsonDecode(bookingResponse.body) as Map<String, dynamic>
          : <String, dynamic>{};
      final appointments = (bookingData['appointments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final counters = <String, int>{'Unpaid': 0, 'Verifying': 0, 'Paid': 0, 'Failed': 0};

      for (final appt in appointments) {
        final state = appt['paymentState']?.toString() ?? 'Unpaid';
        counters[state] = (counters[state] ?? 0) + 1;
      }

      final queueResponse = await http.get(Uri.parse('${ApiConfig.baseUrl}/receptionist_dashboard.php'));
      final queueData = queueResponse.body.isNotEmpty
          ? jsonDecode(queueResponse.body) as Map<String, dynamic>
          : <String, dynamic>{};
      int walkins = 0;
      int inProgress = 0;
      int availableBarbers = 0;
      for (final stat in (queueData['stats'] as List<dynamic>? ?? [])) {
        final item = Map<String, dynamic>.from(stat as Map);
        final title = item['title']?.toString() ?? '';
        final value = int.tryParse(item['value']?.toString() ?? '0') ?? 0;
        if (title == 'Walk-ins') {
          walkins = value;
        }
        if (title == 'In Progress') {
          inProgress = value;
        }
        if (title == 'Available Barbers') {
          availableBarbers = value;
        }
      }

      setState(() {
        _paymentCounters = counters;
        _queueSummary = 'Walk-ins today: $walkins • In progress: $inProgress • Active barbers: $availableBarbers';
        _insightsLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _insightsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = _selectedTab == 0 ? _recommendedStyles : _trendyStyles;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            
            // Welcome Card
            if (_showWelcome) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  UserSession.fullName != null ? 'Welcome ${UserSession.fullName}' : 'Welcome',
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Choose Your Style',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HaircutsListPage()),
                      );
                    },
                    icon: const Icon(Icons.folder_open, color: Colors.white),
                    tooltip: 'Haircut Library',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tabs with gradient (Trendy first, Recommended second)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Recommended',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 0 ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Trendy',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 1 ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildInlineOverview(),
            const SizedBox(height: 24),

            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.white)))
            else if (_error != null)
              Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
            else if (styles.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    _selectedTab == 1
                        ? 'Scan to show recommended haircuts.'
                        : 'No hairstyles available.',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: styles.length,
                itemBuilder: (context, index) => _hairStyleCard(context, styles[index]),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard_ai_chat_fab',
        backgroundColor: const Color(0xFFA99941),
        foregroundColor: Colors.black,
        tooltip: 'Open AI Barber Chat',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AiChatbotPage()),
          );
        },
        child: const Icon(Icons.support_agent_rounded),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            // already on Home
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AppointmentsPage()),
            );
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
            );
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

  Widget _hairStyleCard(BuildContext context, Map<String, dynamic> style) {
    final styleName = style['name']?.toString() ?? 'Style';
    final previewImage = _resolvePreviewImage(style);
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => HairstyleDetailPage(style: style)));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: Colors.white),
                    if (previewImage.startsWith('assets/'))
                      Image.asset(
                          previewImage,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('[Dashboard] Image.asset error for $previewImage: $error');
                          return const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.black38,
                              size: 34,
                            ),
                          );
                        },
                      )
                    else
                      Image.network(
                        previewImage,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                              _dashboardSampleHairFront,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          );
                        },
                      ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withOpacity(0.3), Colors.transparent],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Title and rating
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(styleName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    style['description']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineOverview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Overview', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_insightsLoading)
            const Text('Loading overview...', style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _paymentCounters.entries
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${e.key}: ${e.value}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(_queueSummary, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _mapVariant(Map<String, dynamic> variant) {
    final confidence = double.tryParse(variant['confidence_score']?.toString() ?? '') ?? 0.0;
    final styleName = variant['style_name']?.toString().trim().toLowerCase() ?? '';
    final frontRaw = variant['front_view_url']?.toString() ?? variant['frontViewUrl']?.toString() ?? '';
    final sideRaw = variant['side_view_url']?.toString() ?? variant['sideViewUrl']?.toString() ?? '';
    final backRaw = variant['back_view_url']?.toString() ?? variant['backViewUrl']?.toString() ?? '';
    final localAssets = _localStyleAssets[styleName];
    final front = localAssets?['front'] ?? _resolveImage(frontRaw) ?? _dashboardSampleHairFront;
    final side = localAssets?['side'] ?? _resolveImage(sideRaw) ?? front;
    final back = localAssets?['back'] ?? _resolveImage(backRaw) ?? front;

    debugPrint('[Dashboard] Mapped variant: style=${variant['style_name']} frontRaw=$frontRaw resolved=$front');

    return {
      'name': variant['style_name']?.toString() ?? 'Style',
      'description': variant['description']?.toString() ?? 'AI recommended',
      'image': front,
      'details': _buildDetails(variant),
      'rating': _scoreToRating(confidence),
      'frontViewUrl': front,
      'sideViewUrl': side,
      'backViewUrl': back,
      'variantId': variant['variant_id'],
      'serviceId': variant['service_id'] ?? variant['serviceID'],
    };
  }

  String _resolvePreviewImage(Map<String, dynamic> style) {
    final styleName = style['name']?.toString().trim().toLowerCase() ?? '';
    final localAssets = _localStyleAssets[styleName];
    final raw = style['image']?.toString() ??
        style['frontViewUrl']?.toString() ??
        '';
    if (localAssets != null) {
      return localAssets['front'] ?? _dashboardSampleHairFront;
    }
    if (raw.isEmpty) {
      return _dashboardSampleHairFront;
    }
    return raw;
  }

  String? _resolveImage(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('assets/')) {
      return raw;
    }
    final resolved = ApiConfig.resolveImageUrl(raw);
    debugPrint('[Dashboard] _resolveImage: raw=$raw -> resolved=$resolved');
    return resolved;
  }

  String _buildDetails(Map<String, dynamic> variant) {
    final instructions = variant['barber_instructions']?.toString();
    final faceShape = variant['face_shape']?.toString();
    final hairTexture = variant['hair_texture']?.toString();
    final details = <String>[];
    if (instructions != null && instructions.isNotEmpty) {
      details.add(instructions);
    }
    if (faceShape != null && faceShape.isNotEmpty) {
      details.add('Face shape: $faceShape');
    }
    if (hairTexture != null && hairTexture.isNotEmpty) {
      details.add('Hair texture: $hairTexture');
    }
    return details.join('\n');
  }

  String _scoreToRating(double score) {
    final stars = (score * 5).clamp(1, 5).round();
    return '★' * stars + '☆' * (5 - stars);
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;

  const _BulletPoint(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
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
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
      ],
    );
  }
}
