import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/style_length_warning.dart';

/// Mirrors the ordering in FaceScanResultsPage._alternativeFor.
///
/// The page method reads widget state, so the rule itself is restated here
/// against fixed rows. If the two drift this test stops meaning anything --
/// which is why the comparison steps are written in the same order and with
/// the same reasoning as the page.
/// Mirrors FaceScanResultsPage._curatedTransitionFor.
///
/// Walks the pairing rather than taking the first hop, because a counterpart
/// can itself need more hair than the customer has -- Curly Modern Mullet
/// pairs with Curly Top Fade, which still needs medium.
Map<String, dynamic>? followChain(
  List<Map<String, dynamic>> ranked,
  Map<String, dynamic> wanted,
  int measuredLevel,
) {
  final byCode = <String, Map<String, dynamic>>{};
  for (final row in ranked) {
    final code = row['style_code']?.toString().toUpperCase() ?? '';
    if (code.isNotEmpty) byCode.putIfAbsent(code, () => row);
  }

  final seen = <String>{wanted['style_code']?.toString().toUpperCase() ?? ''};
  var cursor = wanted;

  for (var hop = 0; hop < 6; hop++) {
    final next =
        cursor['transition_style_code']?.toString().toUpperCase() ?? '';
    if (next.isEmpty || !seen.add(next)) return null;

    final candidate = byCode[next];
    if (candidate == null) return null;
    if (!styleNeedsMoreLength(candidate, measuredLevel)) return candidate;
    cursor = candidate;
  }

  return null;
}

Map<String, dynamic>? pickAlternative(
  List<Map<String, dynamic>> ranked,
  Map<String, dynamic> wanted,
  int measuredLevel,
) {
  final wantedKey = wanted['variant_id']?.toString() ?? '';
  final wantedCategory =
      wanted['style_category']?.toString().trim().toLowerCase() ?? '';

  final seen = <String>{};
  final candidates = <({Map<String, dynamic> row, int rank})>[];
  var rank = 0;

  for (final row in ranked) {
    final key = row['variant_id']?.toString() ?? '';
    if (key.isEmpty || key == wantedKey || !seen.add(key)) continue;
    if (styleNeedsMoreLength(row, measuredLevel)) continue;
    candidates.add((row: row, rank: rank++));
  }
  if (candidates.isEmpty) return null;

  int minLengthOf(Map<String, dynamic> row) =>
      (row['min_length_level'] as num?)?.toInt() ?? 0;

  bool sameCategory(Map<String, dynamic> row) =>
      wantedCategory.isNotEmpty &&
      row['style_category']?.toString().trim().toLowerCase() == wantedCategory;

  candidates.sort((a, b) {
    final byLength = minLengthOf(b.row).compareTo(minLengthOf(a.row));
    if (byLength != 0) return byLength;
    final byCategory =
        (sameCategory(b.row) ? 1 : 0).compareTo(sameCategory(a.row) ? 1 : 0);
    if (byCategory != 0) return byCategory;
    return a.rank.compareTo(b.rank);
  });

  return candidates.first.row;
}

Map<String, dynamic> style(
  String id,
  String name, {
  required int minLength,
  required String category,
  String? code,
  String? growsInto,
}) =>
    {
      'variant_id': id,
      'style_name': name,
      'min_length_level': minLength,
      'style_category': category,
      if (code != null) 'style_code': code,
      if (growsInto != null) 'transition_style_code': growsInto,
    };

void main() {
  // The real Oval/Straight ranking, in the order the server returns it.
  final ranked = [
    style('1', 'Blowout Taper', minLength: 1, category: 'formal'),
    style('2', 'Buzz Cut', minLength: 0, category: 'formal'),
    style('3', 'Caesar Cut', minLength: 0, category: 'formal'),
    style('4', 'Edgar Cut', minLength: 0, category: 'alternative'),
    style('5', 'Pompadour', minLength: 2, category: 'alternative'),
    style('6', 'Modern Mullet', minLength: 2, category: 'alternative'),
  ];
  final mullet = ranked.last;

  group('the alternative offered when a style needs more length', () {
    test('is the longest cut they can actually wear', () {
      // The point the panel would press on: someone turned away from a mullet
      // wants the longest thing in that direction, not a buzz cut offered as
      // consolation. Blowout Taper needs level 1 and they have level 1.
      final pick = pickAlternative(ranked, mullet, 1);

      expect(pick?['style_name'], 'Blowout Taper');
    });

    test('never suggests something they cannot wear either', () {
      final pick = pickAlternative(ranked, mullet, 1);

      expect(styleNeedsMoreLength(pick!, 1), isFalse);
    });

    test('never suggests the style they were already looking at', () {
      final pick = pickAlternative(ranked, mullet, 1);

      expect(pick?['variant_id'], isNot('6'));
    });

    test('falls back to the best ranked when nothing is longer', () {
      // Level 0 hair: Blowout Taper is out of reach too, so the tie between
      // the remaining level-0 cuts is broken by the server's ranking, except
      // that a matching category wins first.
      final pick = pickAlternative(ranked, mullet, 0);

      // Edgar Cut is the only level-0 'alternative', matching the mullet's
      // category, so it beats the formal cuts ranked above it.
      expect(pick?['style_name'], 'Edgar Cut');
    });

    test('prefers length over category when they disagree', () {
      // Blowout Taper is formal and the mullet is alternative, yet it is
      // still the right answer at level 1: the conversation is about length.
      final pick = pickAlternative(ranked, mullet, 1);

      expect(pick?['style_category'], 'formal');
    });

    test('returns nothing when every style needs more hair', () {
      final allLong = [
        style('7', 'Wolf Cut', minLength: 3, category: 'alternative'),
        style('8', 'Two Block', minLength: 2, category: 'formal'),
      ];

      expect(pickAlternative(allLong, mullet, 1), isNull);
    });
  });

  group('the curated pairing', () {
    // The real shape: a mullet pairs with a textured crop, and the curly
    // mullet needs two hops because its counterpart is itself too long.
    final catalogue = [
      style('10', 'Textured Crop',
          minLength: 1, category: 'formal', code: 'HC-TEXTURED-CROP'),
      style('11', 'Curly Taper Fade',
          minLength: 1, category: 'formal', code: 'HC-CURLY-TAPER'),
      style('12', 'Curly Top Fade',
          minLength: 2,
          category: 'alternative',
          code: 'STYLE-CURLY-TOP-FADE',
          growsInto: 'HC-CURLY-TAPER'),
      style('13', 'Modern Mullet',
          minLength: 2,
          category: 'alternative',
          code: 'HC-MODERN-MULLET',
          growsInto: 'HC-TEXTURED-CROP'),
      style('14', 'Curly Modern Mullet',
          minLength: 3,
          category: 'alternative',
          code: 'HC-CURLY-MULLET',
          growsInto: 'STYLE-CURLY-TOP-FADE'),
    ];
    final modernMullet = catalogue[3];
    final curlyMullet = catalogue[4];

    test('offers the cut the style actually grows from', () {
      final pick = followChain(catalogue, modernMullet, 1);

      expect(pick?['style_name'], 'Textured Crop');
    });

    test('walks past a counterpart that is itself too long', () {
      // One hop lands on Curly Top Fade, which needs level 2. Stopping there
      // would offer a cut they also cannot have.
      final pick = followChain(catalogue, curlyMullet, 1);

      expect(pick?['style_name'], 'Curly Taper Fade');
    });

    test('stops at the first hop when that one already fits', () {
      final pick = followChain(catalogue, curlyMullet, 2);

      expect(pick?['style_name'], 'Curly Top Fade');
    });

    test('gives up when the pairing names a style that is not loaded', () {
      // The texture filter can legitimately exclude the target; the caller
      // then falls back to the heuristic rather than showing nothing.
      final orphan = style('15', 'Wolf Cut',
          minLength: 3,
          category: 'alternative',
          code: 'HC-WOLF-CUT',
          growsInto: 'HC-NOT-LOADED');

      expect(followChain([orphan], orphan, 1), isNull);
    });

    test('does not hang on a pairing that loops', () {
      final a = style('16', 'A',
          minLength: 2, category: 'formal', code: 'HC-A', growsInto: 'HC-B');
      final b = style('17', 'B',
          minLength: 2, category: 'formal', code: 'HC-B', growsInto: 'HC-A');

      expect(followChain([a, b], a, 1), isNull);
    });

    test('ignores a style that points at itself', () {
      final selfRef = style('18', 'Loop',
          minLength: 2, category: 'formal', code: 'HC-LOOP', growsInto: 'HC-LOOP');

      expect(followChain([selfRef], selfRef, 1), isNull);
    });

    test('a style with no pairing leaves it to the heuristic', () {
      final unpaired = style('19', 'Pineapple',
          minLength: 2, category: 'alternative', code: 'HC-PINEAPPLE');

      expect(followChain(catalogue, unpaired, 1), isNull);
    });
  });
}
