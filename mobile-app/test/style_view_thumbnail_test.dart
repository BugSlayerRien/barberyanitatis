import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/style_view_thumbnail.dart';

/// The recommendation rows arrive under three different spellings depending on
/// which layer produced them -- the API's snake_case, the library page's
/// camelCase remap, and a bare `image` for the front. Reading only one spelling
/// is why the side and back photos were on every row and never drawn.
void main() {
  group('styleViewUrl', () {
    test('reads the API spelling', () {
      const row = {
        'front_view_url': 'uploads/hairstyles/f.jpg',
        'side_view_url': 'uploads/hairstyles/s.jpg',
        'back_view_url': 'uploads/hairstyles/b.jpg',
      };

      expect(styleViewUrl(row, StyleView.front), 'uploads/hairstyles/f.jpg');
      expect(styleViewUrl(row, StyleView.side), 'uploads/hairstyles/s.jpg');
      expect(styleViewUrl(row, StyleView.back), 'uploads/hairstyles/b.jpg');
    });

    test('reads the remapped camelCase spelling', () {
      const row = {
        'frontViewUrl': 'assets/images/overlays/two_block/two_block_front.png',
        'sideViewUrl': 'assets/images/overlays/two_block/two_block_left.png',
      };

      expect(styleViewUrl(row, StyleView.front), endsWith('two_block_front.png'));
      expect(styleViewUrl(row, StyleView.side), endsWith('two_block_left.png'));
      expect(styleViewUrl(row, StyleView.back), '');
    });

    test('falls back to a bare image key for the front only', () {
      const row = {'image': 'uploads/hairstyles/f.jpg'};

      expect(styleViewUrl(row, StyleView.front), 'uploads/hairstyles/f.jpg');
      expect(styleViewUrl(row, StyleView.side), '');
    });

    test('a style with no artwork reports no views', () {
      // Pineapple's shape: saved with a prompt and three empty image columns.
      // It must report nothing rather than something, so the UI draws a
      // placeholder instead of another style's hair.
      const row = {
        'style_name': 'Pineapple',
        'front_view_url': '',
        'side_view_url': '',
        'back_view_url': '',
        'previewable': true,
      };

      for (final view in StyleView.values) {
        expect(styleViewUrl(row, view), '', reason: '${view.label} should be empty');
      }
    });

    test('whitespace is not an image', () {
      expect(styleViewUrl(const {'front_view_url': '   '}, StyleView.front), '');
    });
  });

  test('view labels are the ones shown under each thumbnail', () {
    expect(StyleView.front.label, 'Front');
    expect(StyleView.side.label, 'Side');
    expect(StyleView.back.label, 'Back');
  });

  group('StyleViewSelector', () {
    // The enum means two things. For a haircut's reference photographs the
    // three views really are front, side and back. For the customer's own
    // scan they are front, left profile and right profile -- the try-on page
    // showed the right profile under a tab reading "Back", promising a view of
    // the back of their head that was never photographed.
    test('the customer scan labels name the photos that were actually taken',
        () {
      expect(StyleViewSelector.customerScanLabels[StyleView.front], 'Front');
      expect(StyleViewSelector.customerScanLabels[StyleView.side], 'Left');
      expect(StyleViewSelector.customerScanLabels[StyleView.back], 'Right');
    });

    test('an unset label falls back to the enum', () {
      const selector = StyleViewSelector(
        selected: StyleView.front,
        onChanged: _ignore,
        labels: {StyleView.back: 'Right'},
      );

      expect(selector.labelFor(StyleView.back), 'Right');
      expect(selector.labelFor(StyleView.side), 'Side');
    });

    testWidgets('reports the view that was tapped', (tester) async {
      StyleView? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StyleViewSelector(
            selected: StyleView.front,
            labels: StyleViewSelector.customerScanLabels,
            onChanged: (view) => picked = view,
          ),
        ),
      ));

      expect(find.text('Right'), findsOneWidget);
      expect(find.text('Back'), findsNothing);

      await tester.tap(find.text('Right'));
      await tester.pumpAndSettle();
      expect(picked, StyleView.back);
    });

    testWidgets('tapping the view already shown does not clear the selection',
        (tester) async {
      // SegmentedButton hands back an empty set when the selected segment is
      // tapped again. Passing set.first on that throws.
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StyleViewSelector(
            selected: StyleView.front,
            onChanged: (_) => calls++,
          ),
        ),
      ));

      await tester.tap(find.text('Front'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  });
}

void _ignore(StyleView _) {}
