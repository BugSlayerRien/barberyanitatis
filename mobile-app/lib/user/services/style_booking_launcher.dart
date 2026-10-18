import 'package:flutter/material.dart';

import '../ai_funnel_service.dart';
import '../barber_selection_page.dart';
import '../booking_guard.dart';
import '../customer_navigation.dart';
import '../hair_compatibility.dart';
import '../suggested_appointment_page.dart';
import '../user_session.dart';
import '../widgets/style_length_warning.dart';
import 'booking_draft_service.dart';
import 'booking_slots_service.dart';

/// Takes a chosen haircut all the way to slot selection.
///
/// Extracted from HaircutsListPage, where it was private, because the library's
/// try-on page needs exactly the same journey: confirm the texture, refuse a
/// second active appointment, record the selection against the scan session,
/// then either accept the suggested slot or fall back to picking a barber by
/// hand. Duplicating it would have meant two slightly different booking paths
/// from the same screen.
///
/// [previewImages] overrides the images stored with the selection, so a
/// customer who has just generated an AI preview books with that preview
/// attached rather than the catalog photo the barber would otherwise see.
Future<void> launchBookingForStyle(
  BuildContext context,
  Map<String, dynamic> style, {
  Map<String, String>? previewImages,
}) async {
  final variantId = int.tryParse(style['variantId']?.toString() ?? '') ??
      int.tryParse(style['variantID']?.toString() ?? '') ??
      int.tryParse(style['variant_id']?.toString() ?? '');
  if (variantId == null || variantId <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This haircut cannot be booked yet.')),
    );
    return;
  }

  final compat = HairCompatibility.evaluateStyleMap(style);
  final mayProceed =
      await HairCompatibility.confirmBookingIfNeeded(context, compat);
  if (!mayProceed || !context.mounted) {
    return;
  }

  // The length warning belongs on the booking path too, not only on the
  // generate path. A customer could be told a cut needs longer hair, decline
  // the preview, and book it anyway without ever being asked again -- and
  // turn up at the chair expecting something the barber cannot cut today.
  //
  // Warned, not blocked: the measurement is the weakest signal in the scan,
  // and a customer who knows their own hair may simply be right. The barber
  // also sees the booking and can talk it through.
  final measuredLevel =
      (UserSession.lastScan?['hairLengthLevel'] as num?)?.toInt() ?? 1;
  if (styleNeedsMoreLength(style, measuredLevel)) {
    final styleName = style['name']?.toString() ??
        style['style_name']?.toString() ??
        'This haircut';
    final acceptLength = await confirmLongerHairBooking(context, styleName);
    if (!acceptLength || !context.mounted) {
      return;
    }
    // The barber is told, rather than left to discover it at the chair.
    UserSession.growOutBookingNote = growOutBookingNote(styleName);
  } else {
    UserSession.growOutBookingNote = null;
  }

  final userId = UserSession.userId;
  if (userId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please log in again.')),
    );
    return;
  }

  if (await BookingGuard.hasActiveAppointment(userId: userId)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You already have an active appointment.')),
    );
    openCustomerTab(context, CustomerTab.appointments);
    return;
  }

  if (!context.mounted) return;

  UserSession.selectedVariantId = variantId;
  UserSession.selectedStyleName =
      style['name']?.toString() ?? style['style_name']?.toString();
  UserSession.selectedEstimatedMinutes =
      int.tryParse(style['estimatedMinutes']?.toString() ?? '') ??
          int.tryParse(style['estimated_minutes']?.toString() ?? '');
  UserSession.selectedPreviewImages = previewImages ??
      {
        'frontViewUrl': style['frontViewUrl']?.toString() ??
            style['front_view_url']?.toString() ??
            '',
        'sideViewUrl': style['sideViewUrl']?.toString() ??
            style['side_view_url']?.toString() ??
            '',
        'backViewUrl': style['backViewUrl']?.toString() ??
            style['back_view_url']?.toString() ??
            '',
      };

  await AiFunnelService.saveSelection(
    scanSessionId: UserSession.ensureScanSessionId(),
    userId: userId,
    variantId: variantId,
    styleName: UserSession.selectedStyleName ?? 'Style',
    faceShape: UserSession.lastScan?['faceShape']?.toString(),
    hairTexture: UserSession.lastScan?['hairTexture']?.toString(),
    hairDensity: UserSession.lastScan?['hairDensity']?.toString(),
    hairLength: UserSession.lastScan?['hairLength']?.toString(),
    estimatedMinutes: UserSession.selectedEstimatedMinutes,
    frontViewUrl: UserSession.selectedPreviewImages?['frontViewUrl'],
    sideViewUrl: UserSession.selectedPreviewImages?['sideViewUrl'],
    backViewUrl: UserSession.selectedPreviewImages?['backViewUrl'],
  );

  final result = await BookingSlotsService.fetchBestSuggestion();
  if (!context.mounted) {
    return;
  }
  if (!result.isSuccess || result.suggestion == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No available slots found. Please choose manually.')),
    );
    await BookingDraftService.saveFromSession(step: 'barber');
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BarberSelectionPage()),
    );
    return;
  }

  await BookingDraftService.saveFromSession(step: 'barber');
  if (!context.mounted) {
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SuggestedAppointmentPage(
        suggestion: result.suggestion!,
        alternatives: result.alternatives,
      ),
    ),
  );
}
