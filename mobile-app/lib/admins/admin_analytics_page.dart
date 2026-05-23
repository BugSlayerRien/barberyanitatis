import 'package:flutter/material.dart';

import 'admin_api_service.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  String _period = 'week';
  bool _loading = true;
  String? _error;
  String _summary = '';
  Map<String, dynamic> _metrics = {};

  static const _periodOptions = {
    'today': 'Today',
    'week': 'This week',
    'month': 'This month',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AdminApiService.fetchAnalytics(period: _period);
      if (!mounted) return;
      setState(() {
        _metrics = Map<String, dynamic>.from(data['metrics'] as Map? ?? {});
        _summary = data['summary']?.toString() ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kDarkBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Period',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _period,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1A1A1A),
                        style: const TextStyle(color: Colors.white),
                        items: _periodOptions.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: _loading
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _period = value);
                                _load();
                              },
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: Colors.white),
              ))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent))
            else ...[
              _metricGrid(),
              const SizedBox(height: 20),
              if (_summary.isNotEmpty) ...[
                const Text(
                  'AI summary',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    _summary,
                    style: const TextStyle(color: Colors.white70, height: 1.45, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              _statusSection(),
              const SizedBox(height: 16),
              _topServicesSection(),
              const SizedBox(height: 16),
              _funnelSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricGrid() {
    final revenue = (_metrics['periodRevenue'] as num?)?.toDouble() ?? 0;
    final appts = (_metrics['appointmentsInPeriod'] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        Expanded(child: _metricTile('Revenue', '₱${revenue.toStringAsFixed(0)}')),
        const SizedBox(width: 10),
        Expanded(child: _metricTile('Appointments', '$appts')),
        const SizedBox(width: 10),
        Expanded(
          child: _metricTile(
            'Users',
            '${_metrics['totalUsers'] ?? 0}',
          ),
        ),
      ],
    );
  }

  Widget _metricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kGoldColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _statusSection() {
    final rows = (_metrics['appointmentStatusCounts'] as List<dynamic>? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appointments by status',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...rows.map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  map['status']?.toString() ?? '—',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  '${map['count'] ?? 0}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _topServicesSection() {
    final rows = (_metrics['topServices'] as List<dynamic>? ?? []);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top services',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...rows.map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    map['service_name']?.toString() ?? '—',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Text(
                  '${map['count'] ?? 0}',
                  style: const TextStyle(color: kGoldColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _funnelSection() {
    final funnel = Map<String, dynamic>.from(_metrics['aiFunnel'] as Map? ?? {});
    if ((funnel['scanCount'] as num? ?? 0) == 0) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI funnel',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _funnelRow('Scans', funnel['scanCount']),
        _funnelRow('Style picks', funnel['selectionCount']),
        _funnelRow('Bookings', funnel['bookingCount']),
        _funnelRow('Scan → pick', '${funnel['scanToSelectionRate']}%'),
        _funnelRow('Pick → book', '${funnel['selectionToBookingRate']}%'),
      ],
    );
  }

  Widget _funnelRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text('$value', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
