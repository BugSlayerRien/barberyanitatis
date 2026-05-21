import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';
import '../user/time_format_utils.dart';
import '../user/user_session.dart';

class BarberCalendarPage extends StatefulWidget {
  const BarberCalendarPage({super.key});

  @override
  State<BarberCalendarPage> createState() => _BarberCalendarPageState();
}

class _BarberCalendarPageState extends State<BarberCalendarPage> {
  late DateTime _month;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _requests = [];
  Map<String, int> _bookedByDate = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    final barberId = UserSession.userId;
    if (barberId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barber_schedule.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'listMonth',
          'barberID': barberId,
          'year': _month.year,
          'month': _month.month,
        }),
      );
      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Failed to load schedule';
          _loading = false;
        });
        return;
      }

      final appointments = (data['appointments'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final requests = (data['requests'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final booked = <String, int>{};
      for (final appt in appointments) {
        final key = appt['appointment_date']?.toString() ?? '';
        if (key.isEmpty) continue;
        booked[key] = (booked[key] ?? 0) + 1;
      }

      setState(() {
        _appointments = appointments;
        _requests = requests;
        _bookedByDate = booked;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _requestDayOff(DateTime day) async {
    final barberId = UserSession.userId;
    if (barberId == null) return;

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Request day off', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: noteController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Optional note for receptionist',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) return;

    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/barber_schedule.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'submitUnavailability',
        'barberID': barberId,
        'requestDate': dateStr,
        'note': noteController.text.trim(),
      }),
    );

    noteController.dispose();
    if (!mounted) return;

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent to receptionist for approval.')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not submit request.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('My schedule', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month - 1));
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month + 1));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '${_month.month}/${_month.year}',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ..._appointments.map((appt) {
                      final isGroup = appt['is_group'] == true;
                      final label = appt['display_title']?.toString() ??
                          appt['group_member_name']?.toString() ??
                          'Customer';
                      final timeLabel = (appt['time_range']?.toString().isNotEmpty ?? false)
                          ? appt['time_range']!.toString()
                          : formatTo12Hour(appt['start_time']?.toString() ?? '');
                      final peopleCount = (appt['people_count'] as num?)?.toInt() ?? 1;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$label · ${appt['appointment_date']} · $timeLabel · ${appt['status']}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            if (isGroup)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA99941).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFA99941)),
                                ),
                                child: Text(
                                  'Group · $peopleCount',
                                  style: const TextStyle(
                                    color: Color(0xFFA99941),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    if (_appointments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No appointments this month.', style: TextStyle(color: Colors.white54)),
                      ),
                    const SizedBox(height: 16),
                    const Text('Request unavailability', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(7, (index) {
                        final day = DateTime(_month.year, _month.month, index + 1);
                        if (day.month != _month.month) return const SizedBox.shrink();
                        final key =
                            '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                        final pending = _requests.any(
                          (r) =>
                              r['request_date']?.toString() == key &&
                              (r['status']?.toString() ?? '') == 'Pending',
                        );
                        return OutlinedButton(
                          onPressed: () => _requestDayOff(day),
                          child: Text('${day.day}${pending ? '*' : ''}'),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap a day to request time off. Receptionist must approve before slots are blocked.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
    );
  }
}
