import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:tatis_barbershop/user/auth_page.dart';

void main() {
  testWidgets('Auth page loads and displays sign-in controls', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: AuthPage()));
    await tester.pumpAndSettle();

    expect(find.text('BARBERYA NI TATIS'), findsOneWidget);
    expect(find.text('SIGN IN'), findsWidgets);
    expect(find.text('SIGN UP'), findsWidgets);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Facebook'), findsOneWidget);
  });
}