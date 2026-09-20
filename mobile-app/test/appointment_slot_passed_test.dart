import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/appointments_page.dart';

/// Pins the client-side guard that keeps a past appointment out of the Upcoming
/// tab. The server sweep (expire_unpaid_past_appointments) is what actually
/// resolves these rows, but it is throttled and runs on request traffic, so the
/// app must not depend on it having run.
void main() {
  final now = DateTime(2026, 9, 20, 12, 0);

  group('appointmentSlotHasPassed', () {
    test('yesterday is past', () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-19', endTime: '10:00:00', now: now),
        isTrue,
      );
    });

    test('later today is not past', () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-20', endTime: '18:00:00', now: now),
        isFalse,
      );
    });

    test('earlier today is past', () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-20', endTime: '09:00:00', now: now),
        isTrue,
      );
    });

    test('future date is not past', () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-21', endTime: '09:00:00', now: now),
        isFalse,
      );
    });

    test("the screenshot's case: 2026-09-18 9:00 AM seen on 2026-09-20", () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-18', endTime: '10:00:00', now: now),
        isTrue,
      );
    });

    test('blank end_time falls back to end of day, not start of day', () {
      // Same day, no end time: must NOT be treated as past at midday, or a
      // valid appointment would vanish from Upcoming while it is still due.
      expect(
        appointmentSlotHasPassed(date: '2026-09-20', endTime: '', now: now),
        isFalse,
      );
      expect(
        appointmentSlotHasPassed(date: '2026-09-19', endTime: '', now: now),
        isTrue,
      );
    });

    test("'00:00:00' is the unset marker, not midnight", () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-20', endTime: '00:00:00', now: now),
        isFalse,
      );
    });

    test('missing or unparseable date keeps the appointment visible', () {
      expect(appointmentSlotHasPassed(date: null, endTime: '10:00', now: now), isFalse);
      expect(appointmentSlotHasPassed(date: '', endTime: '10:00', now: now), isFalse);
      expect(
        appointmentSlotHasPassed(date: 'not-a-date', endTime: '10:00', now: now),
        isFalse,
      );
    });

    test('end time without seconds parses', () {
      expect(
        appointmentSlotHasPassed(date: '2026-09-20', endTime: '09:30', now: now),
        isTrue,
      );
    });
  });
}
