import 'dart:async';

import 'package:flutter/material.dart';

import 'receptionist_api.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kCardShadow = Color(0x22000000);

class ReceptionistTrackingPage extends StatefulWidget {
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> walkIns;
  final VoidCallback onChanged;

  const ReceptionistTrackingPage({
    super.key,
    required this.appointments,
    required this.walkIns,
    required this.onChanged,
  });

  @override
  State<ReceptionistTrackingPage> createState() => _ReceptionistTrackingPageState();
}

class _ReceptionistTrackingPageState extends State<ReceptionistTrackingPage> {
  Timer? _progressTimer;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _progressTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> get _trackingData =>
      ReceptionistApi.buildTrackingData(widget.appointments, widget.walkIns);

  @override
  Widget build(BuildContext context) {
    final trackingData = _trackingData;
    if (trackingData.isEmpty) {
      return const Center(
        child: Text(
          'No active clients to track right now.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Track live progress of all clients',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          ...trackingData.map(_buildTrackingCard),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(Map<String, dynamic> data) {
    final live = _liveProgressFor(data);
    final statusColor = _getStatusColor(live['status'] as String);
    final canComplete = live['status'] != 'COMPLETED';
    final canCancel = live['status'] != 'COMPLETED';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white, width: 1),
        boxShadow: const [
          BoxShadow(color: kCardShadow, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: Text(
                  data['initials']?.toString() ?? 'C',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name']?.toString() ?? 'Client',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['service']?.toString() ?? 'Service',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['schedule']?.toString() ?? '',
                      style: const TextStyle(color: kGoldColor, fontSize: 11),
                    ),
                    if ((data['barber']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Barber: ${data['barber']}',
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  live['status'] as String,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Progress', style: TextStyle(color: Colors.white70, fontSize: 11)),
              Text(
                live['timeRemaining'] as String,
                style: const TextStyle(color: kGoldColor, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: live['progress'] as double,
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          if ((live['status'] == 'IN PROGRESS') && (live['progress'] as double) > 0) ...[
            const SizedBox(height: 4),
            Text(
              '${((live['progress'] as double) * 100).round()}% complete',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (canComplete)
                IconButton(
                  tooltip: 'Mark completed',
                  onPressed: _processing ? null : () => _confirmComplete(data),
                  icon: const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50)),
                ),
              if (canCancel)
                IconButton(
                  tooltip: 'Cancel / remove',
                  onPressed: _processing ? null : () => _confirmCancel(data),
                  icon: const Icon(Icons.cancel_outlined, color: Color(0xFFFF5252)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _liveProgressFor(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'WAITING';
    if (status != 'IN PROGRESS') {
      return {
        'status': status,
        'progress': (data['progress'] as num?)?.toDouble() ?? 0.0,
        'timeRemaining': data['timeRemaining']?.toString() ?? '',
      };
    }

    final schedule = data['schedule']?.toString() ?? '';
    if (!schedule.contains('•')) {
      return {
        'status': status,
        'progress': (data['progress'] as num?)?.toDouble() ?? 0.0,
        'timeRemaining': data['timeRemaining']?.toString() ?? 'In service',
      };
    }

    return {
      'status': status,
      'progress': (data['progress'] as num?)?.toDouble() ?? 0.0,
      'timeRemaining': data['timeRemaining']?.toString() ?? 'In service',
    };
  }

  Future<void> _confirmComplete(Map<String, dynamic> data) async {
    final name = data['name']?.toString() ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Complete appointment?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Mark $name as completed?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, complete')),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _applyStatus(data, 'Completed');
  }

  Future<void> _confirmCancel(Map<String, dynamic> data) async {
    final name = data['name']?.toString() ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Cancel appointment?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove $name from tracking and cancel this booking?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, cancel', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _applyStatus(data, 'Cancelled');
  }

  Future<void> _applyStatus(Map<String, dynamic> data, String status) async {
    setState(() => _processing = true);
    try {
      final kind = data['kind']?.toString() ?? 'appointment';
      if (kind == 'walkin') {
        final queueId = int.tryParse('${data['queue_id']}') ?? 0;
        if (queueId <= 0) {
          throw Exception('Invalid walk-in record.');
        }
        await ReceptionistApi.updateWalkinStatus(queueId: queueId, status: status);
      } else {
        final appointmentId = int.tryParse('${data['appointment_id']}') ?? 0;
        if (appointmentId <= 0) {
          throw Exception('Invalid appointment record.');
        }
        await ReceptionistApi.updateAppointmentStatus(
          appointmentId: appointmentId,
          status: status,
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Updated to $status.')),
      );
      widget.onChanged();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'IN PROGRESS':
        return const Color(0xFFFFA500);
      case 'COMPLETED':
        return const Color(0xFF4CAF50);
      case 'WAITING':
        return const Color(0xFF2196F3);
      case 'COMPLETING':
        return const Color(0xFFAB47BC);
      default:
        return kGoldColor;
    }
  }
}
