import 'package:flutter/material.dart';

/// The length check that guards a generation, shared by every screen that can
/// start one: the recommendations, the library's try-on page, and the haircut
/// details.
///
/// It lives here rather than on one page because the three paths must agree.
/// A customer who is warned in the recommendations and not in the library has
/// simply found the bug by another door.

/// True when this style normally needs more hair than the scan measured.
///
/// The server attaches `min_length_level` to every ranked row, so this costs
/// no extra call -- the warning can be shown before a generation is spent
/// rather than after the customer sees a result they did not expect.
bool styleNeedsMoreLength(Map<String, dynamic> style, int measuredLevel) {
  final min = (style['min_length_level'] as num?)?.toInt() ??
      (style['minLengthLevel'] as num?)?.toInt();
  if (min == null) return false;

  return min > measuredLevel;
}

/// Warns that a style wants longer hair, and offers to show it anyway.
///
/// Deliberately a choice, never a filter. Hair length is the weakest signal
/// in the scan -- the lowest hair pixel measured against the chin, maxed
/// across three photos, defaulting to "short" whenever the measurement fails
/// -- so hiding styles on that basis would hide them wrongly and silently.
Future<bool> confirmLongerHairStyle(
  BuildContext context,
  String styleName,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text(
        'This style usually needs longer hair',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Text(
        '"$styleName" is normally cut on longer hair than we measured today.\n\n'
        'We can still show it — the preview will be the closest version your '
        'barber could actually cut at your current length, not a picture of '
        'longer hair.',
        style: const TextStyle(color: Colors.white70, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Pick another', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          child: const Text('Show me anyway'),
        ),
      ],
    ),
  );

  return proceed == true;
}
