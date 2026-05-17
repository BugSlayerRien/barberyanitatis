import 'package:flutter/material.dart';
import '../shared/pagination_controls.dart';
import '../user/time_format_utils.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);
const Color kCardShadow = Color(0x22000000);

class ReceptionistAppointmentsPage extends StatefulWidget {
  final List<Map<String, dynamic>> appointments;
  final Function(Map<String, dynamic>) onStatusChanged;
  final Function(Map<String, dynamic>) onAppointmentRemoved;

  const ReceptionistAppointmentsPage({
    super.key,
    required this.appointments,
    required this.onStatusChanged,
    required this.onAppointmentRemoved,
  });

  @override
  State<ReceptionistAppointmentsPage> createState() =>
      _ReceptionistAppointmentsPageState();
}

class _ReceptionistAppointmentsPageState
    extends State<ReceptionistAppointmentsPage> {
  int _currentPage = 1;

  static const int _itemsPerPage = 6;

  @override
  void didUpdateWidget(covariant ReceptionistAppointmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointments.length != widget.appointments.length) {
      final totalPages = _totalPages(widget.appointments.length);
      if (_currentPage > totalPages) {
        _currentPage = totalPages;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalPages(widget.appointments.length);
    final safePage = _currentPage.clamp(1, totalPages);
    final pagedAppointments =
        _paginateAppointments(widget.appointments, safePage);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appointments Tracker',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 12),
          if (widget.appointments.isEmpty)
            const Text('No appointments found.',
                style: TextStyle(color: Colors.white70))
          else
            ...pagedAppointments
                .map((data) => _buildAppointmentCard(data))
                .toList(),
          PaginationControls(
            currentPage: safePage,
            totalPages: totalPages,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
          ),
        ],
      ),
    );
  }

  int _totalPages(int totalItems) {
    if (totalItems <= 0) {
      return 1;
    }
    return ((totalItems - 1) ~/ _itemsPerPage) + 1;
  }

  List<Map<String, dynamic>> _paginateAppointments(
      List<Map<String, dynamic>> appointments, int page) {
    final start = (page - 1) * _itemsPerPage;
    if (start >= appointments.length) {
      return const <Map<String, dynamic>>[];
    }
    final end = (start + _itemsPerPage).clamp(0, appointments.length);
    return appointments.sublist(start, end);
  }

  Widget _buildAppointmentCard(Map<String, dynamic> data) {
    final status = data['status']?.toString() ?? 'Scheduled';
    final statusColor = status == 'Completed'
        ? const Color(0xFF9E9E9E)
        : status == 'Scheduled' || status == 'CheckedIn' || status == 'InProgress'
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFF9800);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    data['initials'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] as String,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['service'] as String,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'with ${data['barber']}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (status == 'PendingPayment') {
                    _showStatusChangeDialog(data);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTo12Hour(data['time']?.toString() ?? ''),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${data['duration']} • ${data['price']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ],
      ),
    );
  }

  void _showStatusChangeDialog(Map<String, dynamic> appointment) {
    var isProcessing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Change Appointment Status',
                style: TextStyle(color: Colors.white)),
            content: const Text('Select action for this appointment',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: isProcessing
                    ? null
                    : () {
                        setDialogState(() => isProcessing = true);
                        Navigator.pop(ctx);
                        setState(() {
                          appointment['status'] = 'CONFIRMED';
                        });
                        widget.onStatusChanged(appointment);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Appointment confirmed')),
                        );
                      },
                child: isProcessing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kGoldColor),
                      )
                    : const Text('CONFIRM',
                        style: TextStyle(color: kGoldColor)),
              ),
              TextButton(
                onPressed: isProcessing
                    ? null
                    : () {
                        setDialogState(() => isProcessing = true);
                        Navigator.pop(ctx);
                        widget.onAppointmentRemoved(appointment);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Appointment cancelled')),
                        );
                      },
                child: const Text('CANCEL',
                    style: TextStyle(color: Color(0xFFE74C3C))),
              ),
            ],
          );
        },
      ),
    );
  }
}
