import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';

class ReceptionistApi {
  static Future<Map<String, dynamic>> loadDashboard() async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/receptionist.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'dashboard'}),
    );

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to load receptionist dashboard.');
    }

    return data;
  }

  static List<Map<String, dynamic>> mapAppointments(List<dynamic> raw) {
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((row) {
          final name = row['name']?.toString() ?? 'Customer';
          final parts = name.trim().split(RegExp(r'\s+'));
          final initials = parts.length >= 2
              ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
              : (parts.isNotEmpty ? parts.first[0].toUpperCase() : 'C');

          return {
            'appointment_id': row['appointment_id'],
            'barber_id': row['barber_id'],
            'initials': initials,
            'name': name,
            'service': row['service']?.toString() ?? 'Haircut',
            'appointment_date': row['appointment_date']?.toString() ?? '',
            'time': row['time']?.toString() ?? '',
            'end_time': row['end_time']?.toString() ?? '',
            'duration': row['duration']?.toString() ?? '60 min',
            'estimated_minutes': row['estimated_minutes'],
            'checkin_time': row['checkin_time'],
            'price': row['price'] != null ? '₱${row['price']}' : '₱0',
            'status': row['status']?.toString() ?? 'Scheduled',
            'barber': row['barber']?.toString() ?? '',
          };
        })
        .toList();
  }

  static Future<void> updateAppointmentStatus({
    required int appointmentId,
    required String status,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/receptionist.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'updateAppointmentStatus',
        'appointmentID': appointmentId,
        'status': status,
      }),
    );

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to update appointment.');
    }
  }

  static Future<void> updateWalkinStatus({
    required int queueId,
    required String status,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/receptionist.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'updateWalkinStatus',
        'queueID': queueId,
        'status': status,
      }),
    );

    final data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception(data['error']?.toString() ?? 'Failed to update walk-in.');
    }
  }

  static List<Map<String, dynamic>> buildTrackingData(
    List<Map<String, dynamic>> appointments,
    List<Map<String, dynamic>> walkIns,
  ) {
    final now = DateTime.now();
    final items = <Map<String, dynamic>>[];

    for (final appt in appointments) {
      final status = appt['status']?.toString() ?? 'Scheduled';
      if (['Cancelled', 'NoShow', 'Completed'].contains(status)) {
        continue;
      }

      if (status == 'PendingPayment') {
        final dateLabel = appt['appointment_date']?.toString() ?? '';
        final timeLabel = appt['time']?.toString() ?? '';
        items.add({
          'kind': 'appointment',
          'appointment_id': appt['appointment_id'],
          'initials': appt['initials'],
          'name': appt['name'],
          'service': appt['service'],
          'barber': appt['barber']?.toString() ?? '',
          'schedule': '${_formatDateLabel(dateLabel)} • ${_formatTimeLabel(timeLabel)}',
          'status': 'PENDING PAYMENT',
          'rawStatus': status,
          'progress': 0.12,
          'timeRemaining': 'Awaiting payment',
          'color': const Color(0xFFFF9800),
        });
        continue;
      }

      var displayStatus = 'WAITING';
      var progress = 0.0;
      var timeRemaining = status == 'CheckedIn' ? 'Checked in' : 'Upcoming';
      var color = const Color(0xFF2196F3);
      final checkinRaw = appt['checkin_time']?.toString() ?? '';
      final estimatedMinutes = _estimatedMinutesOf(appt, 60);

      if (status == 'InProgress') {
        displayStatus = 'IN PROGRESS';
        color = const Color(0xFF4CAF50);
        final timed = computeServiceProgress(
          now: now,
          start: _parseTimestamp(checkinRaw),
          estimatedMinutes: estimatedMinutes,
        );
        progress = timed['progress'] as double;
        timeRemaining = timed['timeRemaining'] as String;
        if (timed['overtime'] == true) {
          displayStatus = 'COMPLETING';
          color = const Color(0xFFFF9800);
        }
      }

      final dateLabel = appt['appointment_date']?.toString() ?? '';
      final timeLabel = appt['time']?.toString() ?? '';

      items.add({
        'kind': 'appointment',
        'appointment_id': appt['appointment_id'],
        'initials': appt['initials'],
        'name': appt['name'],
        'service': appt['service'],
        'barber': appt['barber']?.toString() ?? '',
        'schedule': '${_formatDateLabel(dateLabel)} • ${_formatTimeLabel(timeLabel)}',
        'status': displayStatus,
        'rawStatus': status,
        'checkin_time': checkinRaw,
        'estimated_minutes': estimatedMinutes,
        'progress': progress,
        'timeRemaining': timeRemaining,
        'color': color,
      });
    }

    for (final walkIn in walkIns) {
      final status = walkIn['status']?.toString() ?? 'Waiting';
      if (status == 'Cancelled' || status == 'Completed') {
        continue;
      }

      var displayStatus = 'WAITING';
      var progress = 0.0;
      var timeRemaining = walkIn['waitTime']?.toString() ?? 'Waiting';
      var color = const Color(0xFF2196F3);
      final actualStartRaw = walkIn['actual_start']?.toString() ?? '';
      final estimatedMinutes = _estimatedMinutesOf(walkIn, 35);

      if (status == 'InProgress') {
        displayStatus = 'IN PROGRESS';
        color = const Color(0xFF4CAF50);
        final timed = computeServiceProgress(
          now: now,
          start: _parseTimestamp(actualStartRaw),
          estimatedMinutes: estimatedMinutes,
        );
        progress = timed['progress'] as double;
        timeRemaining = timed['timeRemaining'] as String;
        if (timed['overtime'] == true) {
          displayStatus = 'COMPLETING';
          color = const Color(0xFFFF9800);
        }
      } else if (status == 'Assigned') {
        displayStatus = 'READY';
        timeRemaining = 'Ready — starts automatically';
      }

      final queueNumber = walkIn['queue_number']?.toString() ?? '';
      final schedule = queueNumber.isNotEmpty
          ? 'Queue $queueNumber • ${walkIn['waitTime']?.toString() ?? 'Today'}'
          : 'Walk-in • ${walkIn['waitTime']?.toString() ?? 'Today'}';

      items.add({
        'kind': 'walkin',
        'queue_id': walkIn['queue_id'],
        'initials': walkIn['initials'],
        'name': walkIn['name'],
        'service': walkIn['service'],
        'barber': walkIn['barber']?.toString() ?? '',
        'schedule': schedule,
        'status': displayStatus,
        'rawStatus': status,
        'actual_start': actualStartRaw,
        'estimated_minutes': estimatedMinutes,
        'progress': progress,
        'timeRemaining': timeRemaining,
        'color': color,
      });
    }

    return items;
  }

  static Map<String, dynamic> computeServiceProgress({
    required DateTime now,
    DateTime? start,
    required int estimatedMinutes,
  }) {
    if (start == null) {
      return {
        'progress': 0.0,
        'overtime': false,
        'timeRemaining': 'In service',
      };
    }

    final totalSeconds = (estimatedMinutes < 1 ? 1 : estimatedMinutes) * 60;
    final elapsedSeconds = now.difference(start).inMilliseconds / 1000.0;
    final ratio = elapsedSeconds / totalSeconds;
    final overtime = ratio >= 1;
    final remainingMins = ((totalSeconds - elapsedSeconds) / 60).ceil();
    final timeRemaining = overtime
        ? 'Auto-completing'
        : '${remainingMins < 0 ? 0 : remainingMins} min remaining';

    return {
      'progress': ratio.clamp(0.0, 1.0),
      'overtime': overtime,
      'timeRemaining': timeRemaining,
    };
  }

  static int _estimatedMinutesOf(Map<String, dynamic> item, int fallback) {
    final raw = item['estimated_minutes'];
    if (raw is num && raw > 0) {
      return raw.round();
    }
    final parsed = int.tryParse(raw?.toString() ?? '');
    if (parsed != null && parsed > 0) {
      return parsed;
    }
    final fromDuration = int.tryParse(
      (item['duration']?.toString() ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (fromDuration != null && fromDuration > 0) {
      return fromDuration;
    }
    return fallback;
  }

  static DateTime? _parseTimestamp(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  }

  static String _formatDateLabel(String isoDate) {
    if (isoDate.isEmpty) {
      return 'Date TBD';
    }
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) {
      return isoDate;
    }
    return '${parsed.month}/${parsed.day}/${parsed.year}';
  }

  static String _formatTimeLabel(String time) {
    if (time.isEmpty) {
      return 'Time TBD';
    }
    final parts = time.split(':');
    if (parts.length < 2) {
      return time;
    }
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }

  static DateTime? _parseEndDateTime(String date, String time) {
    return _parseDateTime(date, time);
  }

  static DateTime? _parseDateTime(String date, String time) {
    if (date.isEmpty || time.isEmpty) {
      return null;
    }
    final normalized = time.length >= 8 ? time.substring(0, 8) : '${time.padRight(5, '0')}:00';
    return DateTime.tryParse('${date}T$normalized');
  }
}
