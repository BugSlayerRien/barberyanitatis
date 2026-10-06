import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/widgets/app_bottom_nav.dart';

/// The barber bar gained a fifth destination (Insights) and the bar has a fixed
/// height with labels under the icons -- exactly the combination that overflowed
/// the last time a destination was added. A narrow phone is the case that
/// breaks, so that is the width under test.
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required List<AppNavDestination> destinations,
    required double width,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNavBar(
            destinations: destinations,
            currentIndex: 0,
            onTap: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('barber nav fits a 320pt phone without overflowing', (tester) async {
    await pumpBar(
      tester,
      destinations: AppBottomNavBar.barberDestinations,
      width: 320,
    );

    expect(tester.takeException(), isNull);
    for (final destination in AppBottomNavBar.barberDestinations) {
      expect(find.text(destination.label), findsOneWidget);
    }
  });

  testWidgets('barber nav offers Insights beside the day view', (tester) async {
    await pumpBar(
      tester,
      destinations: AppBottomNavBar.barberDestinations,
      width: 390,
    );

    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    // Five destinations, so the dashboard's tab indices must still line up with
    // the bar's: an off-by-one here sends Insights to the profile page.
    expect(AppBottomNavBar.barberDestinations.length, 5);
    expect(AppBottomNavBar.barberDestinations[2].label, 'Insights');
  });

  testWidgets('customer nav still fits the same narrow phone', (tester) async {
    await pumpBar(
      tester,
      destinations: AppBottomNavBar.customerDestinations,
      width: 320,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('AI Scan'), findsOneWidget);
  });
}
