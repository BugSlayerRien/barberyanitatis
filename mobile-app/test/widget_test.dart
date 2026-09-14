// Verifies that the Brilliante Barbershop app shell boots and lands on the
// branded splash screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/main.dart';
import 'package:tatis_barbershop/user/app_brand.dart';

void main() {
  testWidgets('App boots to the branded splash screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TatisBarbershopApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Assert on the lockup widget rather than its text: BrandWordmark renders
    // the badge artwork when `assets/images/brilliante.png` is present and a
    // typographic fallback when it is not, so the visible strings differ
    // between those two states while the widget does not.
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.text('AI Hairstyle Recommender'), findsOneWidget);

    // The splash never renders a bare counter — guards against the Flutter
    // scaffold app leaking back in.
    expect(find.text('0'), findsNothing);
  });

  test('Brand identity strings are the Brilliante ones', () {
    expect(AppBrand.name, 'Brilliante Barbershop');
    expect(AppBrand.shortName, 'Brilliante');
  });
}
