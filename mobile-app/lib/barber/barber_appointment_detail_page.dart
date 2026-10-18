import 'package:flutter/material.dart';
import '../user/app_brand.dart';

import '../user/time_format_utils.dart';
import '../user/widgets/appointment_preview_carousel.dart';

/// What the barber reads before the customer sits down.
///
/// It used to be eleven stacked cards, one per field, each a full-width box
/// holding a label and two words. On a phone that is three screens of scrolling
/// for an appointment with six short values in it, and the one thing the
/// barber actually needs -- which haircut, and anything the customer asked for
/// -- was buried in the middle of a list that gave "Status" and "End Time"
/// exactly the same weight.
///
/// Now: who and when at the top, the cut itself next, then the detail. Short
/// values pair up two to a row, because a date takes half a line and a card of
/// its own was most of the wasted space.
class BarberAppointmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const BarberAppointmentDetailPage({
    super.key,
    required this.appointment,
  });

  @override
  Widget build(BuildContext context) {
    // A group arrives as one tile on the schedule and must open as one
    // appointment here: the list already titles it "Rien + 2 others" and
    // chips it "Group of 3", and this page showed only the lead's name, so
    // tapping through lost the fact that three people were coming.
    final isGroup = appointment['isGroup'] == true;
    final peopleCount = (appointment['peopleCount'] as num?)?.toInt() ?? 1;
    final groupMembers = (appointment['groupMembers'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final customerName = isGroup
        ? (appointment['displayTitle']?.toString() ??
            appointment['customerName']?.toString() ??
            'Group booking')
        : (appointment['customerName']?.toString() ?? 'Customer');

    // The haircut first, the service second.
    //
    // This read serviceName before hairstyleName, so the page announced
    // "Exclusive Haircut" -- the price tier the booking was filed under -- as
    // the haircut, and the style the customer actually chose never appeared
    // anywhere. The barber was being told the invoice line, not the job.
    final hairstyleName = appointment['hairstyleName']?.toString().trim() ?? '';
    final serviceName = appointment['serviceName']?.toString().trim() ?? '';
    final headlineCut = hairstyleName.isNotEmpty
        ? hairstyleName
        : (serviceName.isNotEmpty ? serviceName : 'Haircut');
    // Only worth repeating when it is not already the headline.
    final serviceLine =
        (serviceName.isNotEmpty && serviceName != headlineCut) ? serviceName : '';

    final date = appointment['appointmentDate']?.toString() ?? '-';
    final startTime = formatTo12Hour(appointment['startTime']?.toString() ?? '-');
    final endTime = formatTo12Hour(appointment['endTime']?.toString() ?? '-');
    final status = appointment['status']?.toString() ?? 'Unknown';
    final bookingCode = appointment['bookingCode']?.toString() ?? '-';
    final specialInstructions =
        appointment['specialInstructions']?.toString().trim() ?? '';
    final clipperSizes = appointment['clipperSizes']?.toString().trim() ?? '';
    final barberInstructions =
        appointment['barberInstructions']?.toString().trim() ?? '';
    final stylingProducts =
        appointment['stylingProducts']?.toString().trim() ?? '';
    final estimatedMinutes = appointment['estimatedMinutes'];
    final previewImages = previewImagesFromAppointment(appointment);

    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppBar(
        backgroundColor: AppBrand.panel,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Appointment Details',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _panel(
            children: [
              _header(
                customerName: customerName,
                status: status,
                bookingCode: bookingCode,
                peopleCount: isGroup ? peopleCount : null,
              ),
              if (groupMembers.length > 1) ...[
                const _Rule(),
                _members(groupMembers),
              ],
              const _Rule(),
              _cut(
                headline: headlineCut,
                service: serviceLine,
                minutes: estimatedMinutes,
              ),
              const _Rule(),
              // Date and time on one line: between them they are shorter than
              // the label above them.
              _pairRow(
                left: _Field(label: 'Date', value: date),
                right: _Field(label: 'Time', value: '$startTime – $endTime'),
              ),
              if (clipperSizes.isNotEmpty || stylingProducts.isNotEmpty) ...[
                const _Rule(),
                _pairRow(
                  left: clipperSizes.isEmpty
                      ? null
                      : _Field(label: 'Clipper sizes', value: clipperSizes),
                  right: stylingProducts.isEmpty
                      ? null
                      : _Field(label: 'Products', value: stylingProducts),
                ),
              ],
              if (barberInstructions.isNotEmpty) ...[
                const _Rule(),
                _Field(label: 'How to cut it', value: barberInstructions),
              ],
            ],
          ),

          // Kept out of the panel and given its own colour. It carries the
          // customer's own words and the grow-out note, which are the two
          // things on this screen that change what the barber does.
          if (specialInstructions.isNotEmpty) ...[
            const SizedBox(height: 14),
            _note(specialInstructions),
          ],

          if (previewImages.isNotEmpty) ...[
            const SizedBox(height: 18),
            AppointmentPreviewCarousel(images: previewImages),
          ],
        ],
      ),
    );
  }

  Widget _panel({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _header({
    required String customerName,
    required String status,
    required String bookingCode,
    int? peopleCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                customerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _StatusChip(status: status),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              bookingCode,
              style: const TextStyle(
                color: AppBrand.textSubtle,
                fontSize: 12.5,
                letterSpacing: 0.4,
              ),
            ),
            if (peopleCount != null && peopleCount > 1) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppBrand.accentTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppBrand.accentLine),
                ),
                child: Text(
                  'Group of $peopleCount',
                  style: const TextStyle(
                    color: AppBrand.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _cut({
    required String headline,
    required String service,
    required Object? minutes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HAIRCUT',
          style: TextStyle(
            color: AppBrand.textSubtle,
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            if (minutes != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppBrand.accentTint,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppBrand.accentLine),
                ),
                child: Text(
                  '$minutes min',
                  style: const TextStyle(
                    color: AppBrand.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (service.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Booked as $service',
            style: const TextStyle(color: AppBrand.textMuted, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  /// Who sits down and when, for a group.
  ///
  /// The times are the useful part: the members run back to back in one slot
  /// block, so the barber needs the order, not just the count.
  Widget _members(List<Map<String, dynamic>> members) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'IN THIS GROUP',
          style: TextStyle(
            color: AppBrand.textSubtle,
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < members.length; i++) ...[
          if (i > 0) const SizedBox(height: 7),
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppBrand.surfaceLift,
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: AppBrand.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  members[i]['name']?.toString() ?? 'Guest',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _memberTime(members[i]),
                style: const TextStyle(
                  color: AppBrand.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _memberTime(Map<String, dynamic> member) {
    final start = member['startTime']?.toString() ?? '';
    final end = member['endTime']?.toString() ?? '';
    if (start.isEmpty) return '';

    return end.isEmpty
        ? formatTo12Hour(start)
        : '${formatTo12Hour(start)} – ${formatTo12Hour(end)}';
  }

  /// Two fields side by side, or one full width when only one is present.
  Widget _pairRow({_Field? left, _Field? right}) {
    final fields = [left, right].whereType<_Field>().toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    if (fields.length == 1) return fields.first;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: fields[0]),
        const SizedBox(width: 14),
        Expanded(child: fields[1]),
      ],
    );
  }

  Widget _note(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.warningTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.warning),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sticky_note_2_outlined,
                  size: 15, color: AppBrand.warning),
              SizedBox(width: 6),
              Text(
                'From the customer',
                style: TextStyle(
                  color: AppBrand.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// A label above its value, the only shape this screen needs.
class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppBrand.textSubtle,
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, thickness: 1, color: Colors.white10),
    );
  }
}

/// Scheduled, done, or gone -- at a glance, without reading the word.
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status.toLowerCase()) {
      'completed' => AppBrand.success,
      'cancelled' || 'noshow' || 'no-show' => AppBrand.danger,
      'inprogress' || 'checkedin' => AppBrand.accent,
      _ => AppBrand.textMuted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
