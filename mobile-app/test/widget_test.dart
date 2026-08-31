// This test verifies that your Tatis Barbershop Dashboard loads correctly.


import 'package:flutter_test/flutter_test.dart';

// The import must point to your main file
import 'package:tatis_barbershop/main.dart'; 

void main() {
  testWidgets('Dashboard loads and displays key titles', (WidgetTester tester) async {
    
    // Build our app (which is TatisBarbershopApp now)
    await tester.pumpWidget(const TatisBarbershopApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('BARBERYA NI TATIS'), findsWidgets);
    expect(find.text('0'), findsNothing); 
  });
}