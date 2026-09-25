import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:http/http.dart' as http;
import 'group_size_page.dart';
import 'appointments_page.dart';
import 'profile_page.dart';
import 'dashboard_page.dart';
import 'ai_face_scan_page.dart';
import 'saved_haircuts_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/menu_sheet.dart';
import 'widgets/barber_avatar.dart';
import 'api_config.dart';
import 'services/booking_draft_service.dart';

class BarberSelectionPage extends StatefulWidget {
  const BarberSelectionPage({super.key});

  @override
  State<BarberSelectionPage> createState() => _BarberSelectionPageState();
}

class _BarberSelectionPageState extends State<BarberSelectionPage> {
  int _selectedIndex = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _barbers = [];
  int? _detailsLoadingBarberId;
  int? _openingCalendarBarberId;

  @override
  void initState() {
    super.initState();
    _loadBarbers();
  }

  Future<void> _loadBarbers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'list', 'channel': 'appointment'}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load barbers.';
          _loading = false;
        });
        return;
      }

      final barbers = (data['barbers'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _barbers = barbers;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load barbers: $e';
        _loading = false;
      });
    }
  }

  Future<void> _showBarberDetails(int barberId) async {
    if (_detailsLoadingBarberId == barberId) {
      return;
    }

    setState(() => _detailsLoadingBarberId = barberId);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barbers.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'detail', 'barberID': barberId}),
      );
      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Failed to load barber info.')),
        );
        return;
      }
      final barber = data['barber'] as Map<String, dynamic>? ?? {};
      final todayCount = data['appointmentsToday'] is int
          ? data['appointmentsToday'] as int
          : int.tryParse('${data['appointmentsToday']}') ?? 0;

      showDialog(
        context: context,
        builder: (_) => BarberDetailDialog(
          barberName: barber['full_name']?.toString() ?? 'Barber',
          profileImage: BarberAvatar.imageFieldOf(barber),
          specialty: barber['specialty']?.toString() ?? 'General',
          yearsExperience: barber['years_experience'] is int
              ? barber['years_experience'] as int
              : int.tryParse('${barber['years_experience']}') ?? 0,
          rating: double.tryParse('${barber['rating']}') ?? 5.0,
          // ratingCount and recentFeedback were already in the response and
          // thrown away, leaving a bare score with nothing behind it.
          ratingCount: int.tryParse('${data['ratingCount']}') ?? 0,
          recentFeedback: (data['recentFeedback'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList() ??
              const [],
          bio: barber['bio']?.toString() ?? '',
          todayAppointments: todayCount,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load barber info.')),
      );
    } finally {
      if (mounted) {
        setState(() => _detailsLoadingBarberId = null);
      }
    }
  }

  Future<void> _openCalendar(int barberId, String barberName) async {
    if (_openingCalendarBarberId != null) {
      return;
    }

    setState(() => _openingCalendarBarberId = barberId);
    await BookingDraftService.saveFromSession(
      step: 'calendar',
      barberId: barberId,
      barberName: barberName,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupSizePage(
          barberId: barberId,
          barberName: barberName,
        ),
      ),
    );
    if (mounted) {
      setState(() => _openingCalendarBarberId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        onProfileTap: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        },
      ),
      body: _loading
          ? _buildBarberSkeletonList()
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _barbers.length,
        itemBuilder: (context, index) {
          final barber = _barbers[index];
          final barberName = barber['full_name']?.toString() ?? 'Barber';

          return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10, width: 1),
              ),
                child: Row(
                children: [
                  // profile_image already comes back on the list action; it
                  // was simply never read here.
                  BarberAvatar(
                    profileImage: BarberAvatar.imageFieldOf(barber),
                    barberName: barberName,
                    size: 80,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                barberName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          barber['specialty']?.toString() ?? 'General',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action buttons: View stats and Go to calendar
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(builder: (_) {
                        final barberId = barber['barber_id'] is int
                            ? barber['barber_id'] as int
                            : int.tryParse('${barber['barber_id']}') ?? 0;
                        final loadingDetails = _detailsLoadingBarberId == barberId;
                        final openingCalendar = _openingCalendarBarberId == barberId;

                        // An icon on its own is invisible to a screen reader,
                        // so it keeps the label the text button used to give.
                        return IconButton(
                          onPressed: (loadingDetails || openingCalendar || barberId <= 0)
                              ? null
                              : () => _showBarberDetails(barberId),
                          tooltip: 'About $barberName',
                          color: Colors.white,
                          iconSize: 22,
                          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                          padding: EdgeInsets.zero,
                          icon: loadingDetails
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.info_outline),
                        );
                      }),
                      const SizedBox(height: 6),
                      Builder(builder: (_) {
                        final barberId = barber['barber_id'] is int
                            ? barber['barber_id'] as int
                            : int.tryParse('${barber['barber_id']}') ?? 0;
                        final openingCalendar = _openingCalendarBarberId == barberId;
                        final loadingDetails = _detailsLoadingBarberId == barberId;

                        return GestureDetector(
                          onTap: (openingCalendar || loadingDetails || barberId <= 0)
                              ? null
                              : () => _openCalendar(barberId, barberName),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: openingCalendar
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                  )
                                : const Icon(Icons.chevron_right, color: Colors.black, size: 24),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            );
        },
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DashboardPage()));
          } else if (index == 1) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AppointmentsPage()));
          } else if (index == 2) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AiFaceScanPage()));
          } else if (index == 3) {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedHaircutsPage()));
          } else if (index == 4) {
            showAppMenuSheet(context);
          }
        },
      ),
    );
  }

  Widget _buildBarberSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Colors.white12,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 90,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarberDetailDialog extends StatelessWidget {
  final String barberName;
  final String profileImage;
  final String specialty;
  final int yearsExperience;
  final double rating;
  final int ratingCount;
  final List<Map<String, dynamic>> recentFeedback;
  final String bio;
  final int todayAppointments;

  const BarberDetailDialog({
    super.key,
    required this.barberName,
    required this.specialty,
    required this.yearsExperience,
    required this.rating,
    required this.bio,
    required this.todayAppointments,
    this.profileImage = '',
    this.ratingCount = 0,
    this.recentFeedback = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          BarberAvatar(
            profileImage: profileImage,
            barberName: barberName,
            size: 44,
            background: AppBrand.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              barberName,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      // Scrollable now that a bio and up to three comments can follow the
      // fixed rows -- an AlertDialog's content does not scroll on its own.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Specialty', specialty),
            _detailRow('Experience', '$yearsExperience yrs'),
            // A lone score says nothing about how much it is worth trusting, so
            // the number of ratings behind it goes on the same line.
            _detailRow(
              'Rating',
              ratingCount > 0
                  ? '${rating.toStringAsFixed(1)} ($ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'})'
                  : 'No ratings yet',
            ),
            _detailRow('Appointments today', '$todayAppointments'),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(bio, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
            if (recentFeedback.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Recent feedback',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              // Capped so the dialog cannot grow past the screen on a barber
              // with a long history; the API already returns at most 20.
              ...recentFeedback.take(3).map(_feedbackRow),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _feedbackRow(Map<String, dynamic> entry) {
    final stars = int.tryParse('${entry['rating']}') ?? 0;
    final comment = entry['comment']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                i < stars ? Icons.star : Icons.star_border,
                size: 13,
                color: AppBrand.accent,
              ),
            ),
          ),
          if (comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                comment,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}