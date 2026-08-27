import 'dart:convert';

import 'package:flutter/material.dart';

import 'customer_api.dart';
import '../shared/pagination_controls.dart';
import 'time_format_utils.dart';
import 'user_session.dart';
import 'widgets/app_top_bar.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  int _currentPage = 1;

  static const int _groupsPerPage = 4;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final userId = UserSession.userId;
    if (userId == null || userId <= 0) {
      setState(() {
        _loading = false;
        _error = 'Please sign in again.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await CustomerApi.postJson('payments.php', {
        'action': 'listWallet',
        'userID': userId,
      });

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        setState(() {
          _error =
              data['error']?.toString() ?? 'Failed to load payment history.';
          _loading = false;
        });
        return;
      }

      final rows = (data['history'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      setState(() {
        _history = rows;
        _currentPage = 1;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load payment history: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedHistory = _groupHistoryByDate(_history);
    final totalPages = _totalPages(groupedHistory.length);
    final safePage = _currentPage.clamp(1, totalPages);
    final pagedGroups = _paginateGroups(groupedHistory, safePage);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppTopBar(
        showBack: true,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: RefreshIndicator(
        color: Colors.white,
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'History',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.white70))
            else if (_history.isEmpty)
              const Text('No payment history yet.',
                  style: TextStyle(color: Colors.white70))
            else
              ...pagedGroups.map(_historyGroupSection),
            if (!_loading && _error == null && groupedHistory.isNotEmpty)
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
      ),
    );
  }

  int _totalPages(int totalItems) {
    if (totalItems <= 0) {
      return 1;
    }
    return ((totalItems - 1) ~/ _groupsPerPage) + 1;
  }

  List<_HistoryGroup> _paginateGroups(List<_HistoryGroup> groups, int page) {
    final start = (page - 1) * _groupsPerPage;
    if (start >= groups.length) {
      return const <_HistoryGroup>[];
    }
    final end = (start + _groupsPerPage).clamp(0, groups.length);
    return groups.sublist(start, end);
  }

  List<_HistoryGroup> _groupHistoryByDate(List<Map<String, dynamic>> rows) {
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => _historyDateTime(b).compareTo(_historyDateTime(a)));

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in sorted) {
      final dateLabel =
          _formatDateHeader(item['appointmentDate']?.toString() ?? '');
      grouped.putIfAbsent(dateLabel, () => <Map<String, dynamic>>[]).add(item);
    }

    return grouped.entries
        .map((entry) => _HistoryGroup(dateLabel: entry.key, items: entry.value))
        .toList();
  }

  DateTime _historyDateTime(Map<String, dynamic> item) {
    final rawDate = item['appointmentDate']?.toString() ?? '';
    final rawTime = item['appointmentTime']?.toString() ?? '00:00:00';

    final parsedDate = DateTime.tryParse(rawDate);
    if (parsedDate == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final normalizedTime = rawTime.length == 5 ? '$rawTime:00' : rawTime;
    final composed = DateTime.tryParse(
      '${parsedDate.toIso8601String().split('T').first}T$normalizedTime',
    );
    return composed ?? parsedDate;
  }

  String _formatDateHeader(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) {
      return rawDate.isEmpty ? 'Unknown Date' : rawDate;
    }
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  Widget _historyGroupSection(_HistoryGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            group.dateLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...group.items.map(_historyItem),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _historyItem(Map<String, dynamic> item) {
    final bookingCode = item['bookingCode']?.toString() ?? 'Booking';
    final state = item['paymentState']?.toString() ?? 'Unpaid';
    final receipt = item['receiptRef']?.toString() ?? 'No receipt';
    final date = item['appointmentDate']?.toString() ?? '-';
    final time = formatTo12Hour(item['appointmentTime']?.toString() ?? '');
    final amount = item['amount'];
    final amountText = amount is num ? '₱${amount.toStringAsFixed(2)}' : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bookingCode,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('$date ${time.isEmpty ? '' : '• $time'}',
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 6),
          Text('Status: $state',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Receipt: $receipt',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Amount: $amountText',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}

class _HistoryGroup {
  final String dateLabel;
  final List<Map<String, dynamic>> items;

  const _HistoryGroup({required this.dateLabel, required this.items});
}
