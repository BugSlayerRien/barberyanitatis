// This test verifies that your Tatis Barbershop Dashboard loads correctly.


import 'package:flutter_test/flutter_test.dart';

// The import must point to your main file
import 'package:tatis_barbershop/main.dart'; 

void main() {
  testWidgets('Dashboard loads and displays key titles', (WidgetTester tester) async {
    
    // Build our app (which is TatisBarbershopApp now)
    await tester.pumpWidget(const TatisBarbershopApp());

    // Trigger a frame to display the widgets
    await tester.pumpAndSettle();

    // Verify key text elements from the dashboard are present
    expect(find.text('BARBERYA NI TATIS'), findsOneWidget);
    expect(find.text('PREMIUM'), findsOneWidget);
    expect(find.text('POWERED BY AI'), findsOneWidget);
    expect(find.text('BOOK NOW'), findsOneWidget);

    // Verify that the old counter text is NOT present
    expect(find.text('0'), findsNothing); 
  });
}