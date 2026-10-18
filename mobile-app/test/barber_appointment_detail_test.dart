import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/barber/barber_appointment_detail_page.dart';

/// The barber was being shown the invoice line instead of the job.
///
/// The page read `serviceName` before `hairstyleName`, so an appointment filed
/// under the "Exclusive Haircut" price tier announced that as the haircut, and
/// the style the customer actually picked appeared nowhere on the screen.
Future<void> _pump(WidgetTester tester, Map<String, dynamic> appointment) async {
  await tester.pumpWidget(MaterialApp(
    home: BarberAppointmentDetailPage(appointment: appointment),
  ));
  await tester.pump();
}

Map<String, dynamic> _appointment({
  String? hairstyleName = 'Modern Mullet',
  String? serviceName = 'Exclusive Haircut',
  String? note,
}) {
  return {
    'customerName': 'Rien Gappi',
    if (hairstyleName != null) 'hairstyleName': hairstyleName,
    if (serviceName != null) 'serviceName': serviceName,
    'appointmentDate': '2026-10-21',
    'startTime': '19:00:00',
    'endTime': '20:00:00',
    'status': 'Scheduled',
    'bookingCode': 'APP-20261021-001',
    'estimatedMinutes': 40,
    if (note != null) 'specialInstructions': note,
  };
}

void main() {
  group('which haircut the barber is told to cut', () {
    testWidgets('the style the customer picked is the headline',
        (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('Modern Mullet'), findsOneWidget);
    });

    testWidgets('and the price tier is never mistaken for it', (tester) async {
      await _pump(tester, _appointment());
      // Present, but as the booking line -- not as the haircut.
      expect(find.text('Exclusive Haircut'), findsNothing);
      expect(find.text('Booked as Exclusive Haircut'), findsOneWidget);
    });

    testWidgets('an appointment with no style falls back to the service',
        (tester) async {
      await _pump(tester, _appointment(hairstyleName: null));
      expect(find.text('Exclusive Haircut'), findsOneWidget);
      // Nothing to repeat underneath when it is already the headline.
      expect(find.text('Booked as Exclusive Haircut'), findsNothing);
    });

    testWidgets('an empty style name counts as no style', (tester) async {
      await _pump(tester, _appointment(hairstyleName: '   '));
      expect(find.text('Exclusive Haircut'), findsOneWidget);
    });

    testWidgets('with neither, it still renders', (tester) async {
      await _pump(
        tester,
        _appointment(hairstyleName: null, serviceName: null),
      );
      expect(find.text('Haircut'), findsOneWidget);
    });
  });

  group('the rest of the screen', () {
    testWidgets('date and time read as one range, not two cards',
        (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('7:00 PM – 8:00 PM'), findsOneWidget);
      expect(find.text('2026-10-21'), findsOneWidget);
    });

    testWidgets('the customer and the booking code are the header',
        (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('Rien Gappi'), findsOneWidget);
      expect(find.text('APP-20261021-001'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
    });

    // The grow-out note travels here. If it is not shown, the warning the
    // customer dismissed never reaches the person holding the clippers.
    testWidgets('a customer note is shown and labelled', (tester) async {
      await _pump(
        tester,
        _appointment(note: 'Booked as a grow-out goal: cut the closest version.'),
      );
      expect(find.text('From the customer'), findsOneWidget);
      expect(
        find.text('Booked as a grow-out goal: cut the closest version.'),
        findsOneWidget,
      );
    });

    testWidgets('and no empty note box when there is nothing to say',
        (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('From the customer'), findsNothing);
    });

    testWidgets('optional cutting detail is omitted rather than blank',
        (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('CLIPPER SIZES'), findsNothing);
      expect(find.text('PRODUCTS'), findsNothing);
      expect(find.text('HOW TO CUT IT'), findsNothing);
    });

    testWidgets('and shown when it is there', (tester) async {
      await _pump(tester, {
        ..._appointment(),
        'clipperSizes': '#1, #2',
        'stylingProducts': 'Matte clay',
        'barberInstructions': 'Taper the back to the nape.',
      });
      expect(find.text('CLIPPER SIZES'), findsOneWidget);
      expect(find.text('PRODUCTS'), findsOneWidget);
      expect(find.text('Taper the back to the nape.'), findsOneWidget);
    });
  });

  group('a group booking', () {
    // The schedule collapses a group into one tile titled "Rien + 2 others"
    // and chips it "Group of 3". Tapping through used to show only the lead's
    // name, so the barber lost the fact that three people were coming.
    Map<String, dynamic> groupAppointment() => {
          ..._appointment(),
          'isGroup': true,
          'peopleCount': 3,
          'displayTitle': 'Rien Gappi + 2 others',
          'groupMembers': [
            {
              'name': 'Rien Gappi',
              'startTime': '19:00:00',
              'endTime': '19:40:00',
              'isPrimary': true,
            },
            {
              'name': 'Additional guest',
              'startTime': '19:40:00',
              'endTime': '20:20:00',
            },
            {
              'name': 'Additional guest',
              'startTime': '20:20:00',
              'endTime': '21:00:00',
            },
          ],
        };

    testWidgets('is titled as the group, not just the lead', (tester) async {
      await _pump(tester, groupAppointment());
      expect(find.text('Rien Gappi + 2 others'), findsOneWidget);
    });

    testWidgets('says how many people are coming', (tester) async {
      await _pump(tester, groupAppointment());
      expect(find.text('Group of 3'), findsOneWidget);
    });

    testWidgets('lists every chair in order', (tester) async {
      await _pump(tester, groupAppointment());
      expect(find.text('IN THIS GROUP'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Additional guest'), findsNWidgets(2));
    });

    testWidgets('with each one\'s own slot, since they run back to back',
        (tester) async {
      await _pump(tester, groupAppointment());
      expect(find.text('7:00 PM – 7:40 PM'), findsOneWidget);
      expect(find.text('8:20 PM – 9:00 PM'), findsOneWidget);
    });

    testWidgets('a single booking shows no group furniture', (tester) async {
      await _pump(tester, _appointment());
      expect(find.text('IN THIS GROUP'), findsNothing);
      expect(find.textContaining('Group of'), findsNothing);
    });

    testWidgets('a group of one is not called a group', (tester) async {
      await _pump(tester, {
        ..._appointment(),
        'isGroup': true,
        'peopleCount': 1,
        'groupMembers': [
          {'name': 'Rien Gappi', 'startTime': '19:00:00', 'endTime': '20:00:00'},
        ],
      });
      expect(find.text('IN THIS GROUP'), findsNothing);
      expect(find.textContaining('Group of'), findsNothing);
    });
  });

  testWidgets('it fits a phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, {
      ..._appointment(note: 'Scissors only please, sensitive scalp.'),
      'clipperSizes': '#1, #2, #3 blended up through the middle',
      'stylingProducts': 'Strong hold pomade',
      'barberInstructions':
          'Taper the back to the nape, leave three inches on top.',
    });

    expect(tester.takeException(), isNull);
  });
}
