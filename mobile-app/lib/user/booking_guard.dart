import 'dart:convert';

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
      final response = await CustomerApi.postJson('booking.php', {
        'action': 'listByCustomer',
        'userID': userId,
      });

      if (response.statusCode != 200 || response.body.isEmpty) {
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
}
