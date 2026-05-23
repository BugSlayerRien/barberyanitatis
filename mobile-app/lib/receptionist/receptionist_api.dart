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

      final start = _parseDateTime(
        appt['appointment_date']?.toString() ?? '',
        appt['time']?.toString() ?? '',
      );

      var displayStatus = 'WAITING';
      var progress = 0.0;
      var timeRemaining = 'Upcoming';

      DateTime? end;
      if (status == 'InProgress' || status == 'CheckedIn') {
        displayStatus = 'IN PROGRESS';
        if (start != null) {
          end = _parseEndDateTime(appt['appointment_date']?.toString() ?? '', appt['end_time']?.toString() ?? '') ??
              start.add(const Duration(hours: 1));
          final totalMinutes = end.difference(start).inMinutes.clamp(1, 180);
          final elapsed = now.difference(start).inMinutes.clamp(0, totalMinutes);
          progress = (elapsed / totalMinutes).clamp(0.0, 1.0);
          final mins = end.difference(now).inMinutes;
          timeRemaining = mins > 0 ? '$mins min remaining' : 'Finishing';
        } else {
          progress = status == 'InProgress' ? 0.75 : 0.35;
          timeRemaining = 'In service';
        }
      } else if (start != null) {
        end = _parseEndDateTime(appt['appointment_date']?.toString() ?? '', appt['end_time']?.toString() ?? '') ??
            start.add(const Duration(hours: 1));
        if (!now.isBefore(start) && now.isBefore(end)) {
          displayStatus = 'IN PROGRESS';
          final totalMinutes = end.difference(start).inMinutes.clamp(1, 180);
          final elapsed = now.difference(start).inMinutes.clamp(0, totalMinutes);
          progress = (elapsed / totalMinutes).clamp(0.0, 1.0);
          final mins = end.difference(now).inMinutes;
          timeRemaining = mins > 0 ? '$mins min remaining' : 'Finishing';
        } else if (!now.isBefore(end)) {
          displayStatus = 'COMPLETING';
          progress = 1.0;
          timeRemaining = 'Auto-completing';
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
        'progress': progress,
        'timeRemaining': timeRemaining,
        'color': displayStatus == 'IN PROGRESS'
            ? const Color(0xFF4CAF50)
            : const Color(0xFF2196F3),
      });
    }

    const walkinDuration = Duration(minutes: 35);

    for (final walkIn in walkIns) {
      final status = walkIn['status']?.toString() ?? 'Waiting';
      var displayStatus = 'WAITING';
      var progress = 0.12;
      var timeRemaining = walkIn['waitTime']?.toString() ?? 'Waiting';

      final actualStartRaw = walkIn['actual_start']?.toString() ?? '';
      DateTime? serviceStart;
      if (actualStartRaw.isNotEmpty) {
        serviceStart = DateTime.tryParse(actualStartRaw.replaceFirst(' ', 'T'));
      }

      if (status == 'InProgress') {
        displayStatus = 'IN PROGRESS';
        if (serviceStart != null) {
          final end = serviceStart.add(walkinDuration);
          if (!now.isBefore(end)) {
            displayStatus = 'COMPLETING';
            progress = 1.0;
            timeRemaining = 'Auto-completing';
          } else {
            final total = walkinDuration.inMinutes;
            final elapsed = now.difference(serviceStart).inMinutes.clamp(0, total);
            progress = (elapsed / total).clamp(0.0, 0.95);
            final mins = end.difference(now).inMinutes;
            timeRemaining = mins > 0 ? '$mins min remaining' : 'Finishing';
          }
        } else {
          progress = 0.35;
          timeRemaining = 'In service';
        }
      } else if (status == 'Assigned') {
        displayStatus = 'READY';
        progress = 0.25;
        timeRemaining = 'Ready — starts automatically';
      } else if (status == 'Completed') {
        displayStatus = 'COMPLETED';
        progress = 1.0;
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
        'progress': progress,
        'timeRemaining': timeRemaining,
        'color': displayStatus == 'IN PROGRESS'
            ? const Color(0xFF4CAF50)
            : const Color(0xFF2196F3),
      });
    }

    return items;
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
