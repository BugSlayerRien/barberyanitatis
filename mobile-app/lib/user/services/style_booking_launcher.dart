import 'package:flutter/material.dart';

import '../ai_funnel_service.dart';
import '../barber_selection_page.dart';
import '../booking_guard.dart';
import '../customer_navigation.dart';
import '../hair_compatibility.dart';
import '../suggested_appointment_page.dart';
import '../user_session.dart';
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
