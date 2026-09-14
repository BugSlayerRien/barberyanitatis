import 'package:flutter/material.dart';
import 'app_brand.dart';

import 'appointments_page.dart';
import 'customer_navigation.dart';
import 'profile_page.dart';
import 'saved_haircuts_page.dart';
import 'ai_face_scan_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/appointment_preview_carousel.dart';
import 'widgets/menu_sheet.dart';
import 'time_format_utils.dart';

class CompletedAppointmentDetailPage extends StatefulWidget {
  final Map<String, dynamic> appointment;
  final bool isUpcoming;

  const CompletedAppointmentDetailPage({
    super.key,
    required this.appointment,
    this.isUpcoming = false,
  });

  @override
  State<CompletedAppointmentDetailPage> createState() => _CompletedAppointmentDetailPageState();
}

class _CompletedAppointmentDetailPageState extends State<CompletedAppointmentDetailPage> {
  int _navIndex = 1;

  @override
  Widget build(BuildContext context) {
    final previewImages = previewImagesFromAppointment(widget.appointment);
    final isGroup = widget.appointment['isGroup'] == true;
    final serviceName = isGroup
        ? (widget.appointment['displayTitle']?.toString() ?? widget.appointment['service']?.toString() ?? 'Group')
        : (widget.appointment['service']?.toString() ?? 'Haircut');
    final barberName = widget.appointment['barber']?.toString() ?? '';
    final date = widget.appointment['date']?.toString() ?? '';
    final timeRaw = widget.appointment['time']?.toString() ?? '';
    final time = timeRaw.contains(':') && !timeRaw.contains('M')
        ? formatTimeRangeTo12h(timeRaw)
        : timeRaw;
    final duration = widget.appointment['duration']?.toString() ?? '—';
    final price = widget.appointment['price']?.toString() ?? '₱0';
    final groupMembers = (widget.appointment['groupMembers'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final status = widget.appointment['status']?.toString() ?? '';
    final paymentState = widget.appointment['paymentState']?.toString() ?? '';
    final receiptRef = widget.appointment['receiptRef']?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
        onProfileTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProfilePage()),
          );
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              if (isGroup) ...[
                const Icon(Icons.groups_rounded, color: AppBrand.accent, size: 28),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  serviceName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(barberName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
          if (isGroup && groupMembers.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Group members',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...groupMembers.map((member) {
              final name = member['name']?.toString() ?? 'Guest';
              final slotTime = member['startTime']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: AppBrand.accent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$name · ${formatTimeRangeTo12h(slotTime)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (widget.isUpcoming) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status.isNotEmpty)
                  _chip(
                    status == 'PendingPayment' ? 'Pending payment' : status,
                    status == 'PendingPayment'
                        ? const Color(0xFFE67E22)
                        : const Color(0xFF4CAF50),
                  ),
                if (paymentState.isNotEmpty)
                  _chip(
                    paymentState,
                    paymentState == 'Paid'
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFE67E22),
                  ),
              ],
            ),
            if (receiptRef.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Receipt: $receiptRef',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: AppBrand.accent, size: 18),
              const SizedBox(width: 8),
              Text(date, style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 20),
              const Icon(Icons.access_time, color: AppBrand.accent, size: 18),
              const SizedBox(width: 8),
              Text(time, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Duration: $duration', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Text(
            'Price: $price',
            style: const TextStyle(
              color: AppBrand.accent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (previewImages.isNotEmpty) ...[
            const SizedBox(height: 24),
            AppointmentPreviewCarousel(images: previewImages),
          ],
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _navIndex,
        onTap: (index) {
          if (index == _navIndex) {
            return;
          }
          setState(() => _navIndex = index);
          switch (index) {
            case 0:
              navigateToCustomerHome(context);
              break;
            case 1:
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AppointmentsPage()),
              );
              break;
            case 2:
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiFaceScanPage()),
              );
              break;
            case 3:
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SavedHaircutsPage()),
              );
              break;
            case 4:
              showAppMenuSheet(context);
              break;
          }
        },
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}
