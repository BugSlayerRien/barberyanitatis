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
