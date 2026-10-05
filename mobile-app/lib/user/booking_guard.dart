import 'customer_api.dart';

class BookingGuard {
  static const Set<String> _activeStatuses = {
    'pendingpayment',
    'scheduled',
    'checkedin',
    'inprogress',
  };

  static bool isActiveStatus(String status) {
    final normalized = status.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
    return _activeStatuses.contains(normalized);
  }

  static Future<bool> hasActiveAppointment({required int? userId}) async {
    if (userId == null || userId <= 0) {
      return false;
    }

    try {
      final data = await CustomerApi.postDecoded('booking.php', {
        'action': 'listByCustomer',
        'userID': userId,
      });

      final appointments = (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      for (final appt in appointments) {
        if (isActiveStatus(appt['status']?.toString() ?? '')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Releases a booking the customer created and then backed out of.
  ///
  /// A booking is written as PendingPayment before the payment page opens, and
  /// [hasActiveAppointment] counts that as active -- so leaving payment without
  /// paying used to refuse every later attempt with "You already have an active
  /// appointment". The server also sweeps these up once the reservation hold
  /// passes, which covers a killed app; this is the immediate, ordinary case.
  ///
  /// Silent by design: the customer chose to go back, and a notice about
  /// cancelling something they never knowingly created is noise. A booking that
  /// has been paid, or whose payment is still being verified, is never touched.
  static Future<void> releaseIfUnpaid({
    required int? userId,
    required int? appointmentId,
  }) async {
    if (userId == null || userId <= 0 || appointmentId == null || appointmentId <= 0) {
      return;
    }

    try {
      final data = await CustomerApi.postDecoded('booking.php', {
        'action': 'listByCustomer',
        'userID': userId,
      });

      final appointments = (data['appointments'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      Map<String, dynamic>? target;
      for (final appt in appointments) {
        if ((appt['appointmentID'] as num?)?.toInt() == appointmentId) {
          target = appt;
          break;
        }
      }
      if (target == null) return;

      final status = target['status']?.toString() ?? '';
      final paymentState = target['paymentState']?.toString() ?? 'Unpaid';
      final normalized = status.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();

      // Verifying means a gateway result is still in flight -- cancelling then
      // would throw away a booking the customer has already paid for.
      if (normalized != 'pendingpayment' ||
          paymentState == 'Paid' ||
          paymentState == 'Verifying') {
        return;
      }

      await CustomerApi.postDecoded('booking.php', {
        'action': 'cancel',
        'appointmentID': appointmentId,
        'reason': 'Payment was not started',
      });
    } catch (_) {
      // The server sweep is the backstop, so a failure here is not worth
      // interrupting the customer over.
    }
  }
}
