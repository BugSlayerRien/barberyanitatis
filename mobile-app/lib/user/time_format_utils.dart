String formatTo12Hour(String input) {
  final value = input.trim();
  if (value.isEmpty) {
    return value;
  }

  final amPmPattern = RegExp(r'^\d{1,2}:\d{2}\s?(AM|PM)$', caseSensitive: false);
  if (amPmPattern.hasMatch(value)) {
    return value.replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  }

  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (match == null) {
    return value;
  }

  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return value;
  }

  final suffix = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  final minuteText = minute.toString().padLeft(2, '0');
  return '$hour12:$minuteText $suffix';
}

const int kShopSlotStartHour = 9;
const int kShopSlotEndHour = 19;
const List<int> kShopBreakHours = [12];
const int kShopMinimumBookingLeadMinutes = 60;

/// On-the-hour starts from 9:00 AM through 7:00 PM (service ends by 8:00 PM).
bool isShopHourlySlotTime(String time) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(time.trim());
  if (match == null) {
    return false;
  }

  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  if (hour == null || minute == null) {
    return false;
  }

  return minute == 0 && hour >= kShopSlotStartHour && hour <= kShopSlotEndHour;
}

List<String> shopHourlySlotTimesCanonical() {
  final times = <String>[];
  for (var hour = kShopSlotStartHour; hour <= kShopSlotEndHour; hour++) {
    if (kShopBreakHours.contains(hour)) {
      continue;
    }
    times.add('${hour.toString().padLeft(2, '0')}:00:00');
  }
  return times;
}

/// Earliest bookable slot start: now + 1 hour, rounded up to the next full hour.
/// Example: booking at 1:40 PM → earliest slot 3:00 PM (not 2:00 PM).
DateTime shopEarliestBookableSlotStart() {
  var minimum = DateTime.now().add(const Duration(minutes: kShopMinimumBookingLeadMinutes));
  if (minimum.minute > 0 || minimum.second > 0 || minimum.millisecond > 0) {
    minimum = DateTime(minimum.year, minimum.month, minimum.day, minimum.hour + 1);
  }
  if (minimum.hour == 12) {
    minimum = DateTime(minimum.year, minimum.month, minimum.day, 13);
  }
  return minimum;
}

bool isSlotBookableAt(DateTime slotDateTime) {
  final earliest = shopEarliestBookableSlotStart();
  return !slotDateTime.isBefore(earliest);
}

const int kReservationHoldMinutes = 10;

/// Converts "15:00 – 19:00" or single times to 12-hour labels.
String formatTimeRangeTo12h(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  final parts = trimmed.split(RegExp(r'\s*[–-]\s*'));
  if (parts.length == 2) {
    return '${formatTo12Hour(parts[0].trim())} – ${formatTo12Hour(parts[1].trim())}';
  }

  return formatTo12Hour(trimmed);
}

/// Human-readable countdown for the 10-minute reservation hold.
String formatReservationHoldLabel(Duration remaining) {
  if (remaining.inSeconds <= 0) {
    return 'Reservation hold expired';
  }

  final capped = remaining > const Duration(minutes: kReservationHoldMinutes)
      ? const Duration(minutes: kReservationHoldMinutes)
      : remaining;

  final hours = capped.inHours;
  final minutes = capped.inMinutes % 60;
  final seconds = capped.inSeconds % 60;

  if (hours > 0) {
    return 'Reservation hold: ${hours}h ${minutes}m left';
  }
  if (minutes > 0) {
    return 'Reservation hold: ${minutes} min ${seconds}s left';
  }

  return 'Reservation hold: ${seconds}s left';
}

DateTime? reservationHoldEndsAt({
  String? holdExpiresAt,
  String? intentCreatedAt,
}) {
  if (holdExpiresAt != null && holdExpiresAt.isNotEmpty) {
    return DateTime.tryParse(holdExpiresAt)?.toLocal();
  }
  if (intentCreatedAt != null && intentCreatedAt.isNotEmpty) {
    final created = DateTime.tryParse(intentCreatedAt)?.toLocal();
    if (created != null) {
      return created.add(const Duration(minutes: kReservationHoldMinutes));
    }
  }
  return null;
}

/// Rewrites HH:MM segments inside API suggestion text to 12-hour form.
String formatSuggestionReasonTo12h(String reason) {
  return reason.replaceAllMapped(RegExp(r'\b(\d{1,2}):(\d{2})\b'), (match) {
    return formatTo12Hour('${match.group(1)}:${match.group(2)}');
  });
}

DateTime? tryParseSlotDateTime({
  required DateTime date,
  required String time,
}) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(time.trim());
  if (match == null) {
    return null;
  }

  final hour = int.tryParse(match.group(1) ?? '');
  final minute = int.tryParse(match.group(2) ?? '');
  final second = int.tryParse(match.group(3) ?? '0');
  if (hour == null || minute == null || second == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
    return null;
  }

  return DateTime(date.year, date.month, date.day, hour, minute, second);
}

String normalizeSqlDate(String raw) {
  final value = raw.trim();
  return value.length >= 10 ? value.substring(0, 10) : value;
}

/// Suggestion slots must be strictly in the future with the 2-hour Smart Appointment lead.
bool isSuggestableSlotDateTime(DateTime slotDateTime) {
  return slotDateTime.isAfter(DateTime.now().add(const Duration(hours: 2)));
}

bool isPastOrInvalidSuggestion({required String date, required String time}) {
  final ymd = normalizeSqlDate(date);
  final parts = ymd.split('-');
  if (parts.length != 3) {
    return true;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return true;
  }

  final slotDateTime = tryParseSlotDateTime(
    date: DateTime(year, month, day),
    time: time,
  );
  if (slotDateTime == null) {
    return true;
  }

  return !isSuggestableSlotDateTime(slotDateTime);
}
