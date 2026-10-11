import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/style_length_warning.dart';

/// Mirrors the ordering in FaceScanResultsPage._alternativeFor.
///
/// The page method reads widget state, so the rule itself is restated here
/// against fixed rows. If the two drift this test stops meaning anything --
/// which is why the comparison steps are written in the same order and with
/// the same reasoning as the page.
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
}) =>
    {
      'variant_id': id,
      'style_name': name,
      'min_length_level': minLength,
      'style_category': category,
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
}
