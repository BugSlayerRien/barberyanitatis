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

/// What the customer chose when told a style needs more hair than they have.
enum LengthChoice {
  /// Backed out. Nothing is generated and nothing is spent.
  cancel,

  /// The scan was wrong. Treat their hair as long enough and generate normally.
  correctLength,

  /// Generate the full style and label it as the goal, not as today's cut.
  growOutGoal,

  /// Show something their barber could cut this afternoon instead.
  showAlternatives,
}

/// Explains that a style needs more hair, and offers the three honest ways out.
///
/// There used to be a "show me anyway" that promised the preview would be
/// adapted to the customer's real length. Five rounds of prompt work could not
/// make the generator honour that -- xAI's edit endpoint takes no mask, so no
/// region can be protected, and the model draws the haircut it knows. The
/// promise was removed rather than repeated.
///
/// Deliberately a choice and never a filter. Hair length is the weakest signal
/// in the scan -- the lowest hair pixel measured against the chin, maxed across
/// three photos, defaulting to "short" whenever the measurement fails -- so the
/// first option exists to let the customer overrule a bad reading.
Future<LengthChoice> confirmLongerHairStyle(
  BuildContext context,
  String styleName, {
  bool canShowAlternatives = true,
}) async {
  // Full-width rows rather than dialog actions. Four choices in an
  // AlertDialog's footer wrap into an unreadable stack on a phone, and these
  // need a line of explanation each -- the difference between "grow-out look"
  // and "my hair is longer" is not obvious from a button label alone.
  Widget option({
    required IconData icon,
    required String title,
    required String detail,
    required LengthChoice value,
    bool primary = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primary ? Colors.white10 : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primary ? Colors.white54 : Colors.white24,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: primary ? Colors.white : Colors.white60),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: primary ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  final choice = await showDialog<LengthChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      title: Text(
        '"$styleName" needs longer hair',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: Text(
                'This cut is done on longer hair than your scan measured, so '
                'your barber cannot give you this look today.',
                style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 13),
              ),
            ),
            if (canShowAlternatives)
              option(
                icon: Icons.content_cut,
                title: 'Show what suits me now',
                detail: 'A cut your barber can give you today.',
                value: LengthChoice.showAlternatives,
              ),
            option(
              icon: Icons.straighten_rounded,
              title: 'My hair is longer than that',
              detail: 'The scan got it wrong. Generate the real thing.',
              value: LengthChoice.correctLength,
            ),
            option(
              icon: Icons.schedule_rounded,
              title: 'Show the grow-out look',
              detail: 'Uses one preview. The picture will have hair you do '
                  'not have yet — it is the goal, not today.',
              value: LengthChoice.growOutGoal,
              primary: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(LengthChoice.cancel),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
      ],
    ),
  );

  return choice ?? LengthChoice.cancel;
}

/// The same warning, worded for the chair rather than the preview.
///
/// Kept separate because the consequence differs: an unexpected preview costs
/// a generation, an unexpected haircut costs the appointment. The customer is
/// still allowed to proceed -- the length measurement is the weakest signal in
/// the scan, and the barber can talk it through on the day.
Future<bool> confirmLongerHairBooking(
  BuildContext context,
  String styleName,
) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text(
        'This cut usually needs longer hair',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Text(
        'Your scan measured less length than "$styleName" normally needs, so '
        'this is a cut to grow towards rather than one for today.\n\n'
        'You can still book it. Your barber will cut the closest version they '
        'can on the day, and can tell you how long it would take to grow out '
        'for the full look.',
        style: const TextStyle(color: Colors.white70, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Pick another',
              style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
          ),
          child: const Text('Book it anyway'),
        ),
      ],
    ),
  );

  return proceed == true;
}

/// The amber badge that marks a preview as a goal rather than today's cut.
///
/// On the image itself, not only in a caption underneath, so the label travels
/// with a screenshot. The app previously printed "the back is left as it is"
/// beneath a picture with a long back; the picture was fine, the caption was
/// the lie.
class GrowOutGoalBadge extends StatelessWidget {
  const GrowOutGoalBadge({super.key});

  static const Color color = Color(0xFFE0B35A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: color),
          SizedBox(width: 4),
          Text(
            'Grow-out goal',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The sentence that goes under a grow-out preview.
String growOutCaption(String styleName) =>
    'This is $styleName once your hair has grown out. Your barber cannot cut '
    'it at your current length — ask them how long it would take.';
