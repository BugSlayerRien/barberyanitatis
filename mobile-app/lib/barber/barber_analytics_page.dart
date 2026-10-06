import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../user/api_config.dart';
import '../user/app_brand.dart';
import '../user/user_session.dart';
import '../user/widgets/app_top_bar.dart';
import '../user/widgets/pill_tabs.dart';

/// Insights: the barber's own numbers, drawn rather than listed.
///
/// Everything here already existed in the database and could only be read by
/// the admin web portal -- the barber doing the work could see today's list and
/// nothing else. No new tables: one endpoint aggregates appointments, walk-ins
/// and feedback that were already being written.
///
/// Charts are hand-drawn with CustomPainter and plain boxes on purpose. A chart
/// package would be a new dependency on a build that has to come out of
/// Codemagic unattended, and none of these shapes need one.
class BarberAnalyticsPage extends StatefulWidget {
  const BarberAnalyticsPage({super.key});

  @override
  State<BarberAnalyticsPage> createState() => _BarberAnalyticsPageState();
}

class _BarberAnalyticsPageState extends State<BarberAnalyticsPage> {
  static const List<String> _rangeLabels = ['7 days', '30 days', '90 days'];
  static const List<int> _rangeDays = [7, 30, 90];

  int _rangeIndex = 1;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/barber_analytics.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'summary',
          'barberID': UserSession.userId,
          'email': UserSession.email ?? '',
          'days': _rangeDays[_rangeIndex],
        }),
      );

      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _error = body['error']?.toString() ?? 'Could not load your insights.';
          _loading = false;
        });
        return;
      }

      setState(() {
        _data = body;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your insights: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> get _totals =>
      Map<String, dynamic>.from(_data?['totals'] as Map? ?? {});

  Map<String, dynamic> get _ratings =>
      Map<String, dynamic>.from(_data?['ratings'] as Map? ?? {});

  List<Map<String, dynamic>> _list(String key) =>
      (_data?[key] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      appBar: AppTopBar(
        showBack: true,
        showCustomerActions: false,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: RefreshIndicator(
        color: AppBrand.gold,
        backgroundColor: AppBrand.surface,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Text(
              'Your insights',
              style: TextStyle(
                color: AppBrand.chalk,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _rangeCaption(),
              style: const TextStyle(color: AppBrand.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            PillTabs(
              labels: _rangeLabels,
              selectedIndex: _rangeIndex,
              onSelected: (index) {
                if (index == _rangeIndex) return;
                setState(() => _rangeIndex = index);
                _load();
              },
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else if (_error != null)
              _errorBlock()
            else
              ..._buildCharts(),
          ],
        ),
      ),
    );
  }

  String _rangeCaption() {
    final range = Map<String, dynamic>.from(_data?['range'] as Map? ?? {});
    final from = range['from']?.toString();
    final to = range['to']?.toString();
    if (from == null || to == null) {
      return 'Based on your own appointments, walk-ins and ratings.';
    }

    return '${_shortDate(from)} to ${_shortDate(to)}';
  }

  Widget _errorBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppBrand.textSubtle, size: 32),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppBrand.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _load,
            style: AppBrand.primaryButton,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCharts() {
    final totals = _totals;
    final booked = (totals['booked'] as num?)?.toInt() ?? 0;
    final walkins = (totals['walkinsServed'] as num?)?.toInt() ?? 0;

    if (booked == 0 && walkins == 0) {
      return [_emptyRange()];
    }

    return [
      _statGrid(),
      const SizedBox(height: 14),
      _workPerDayCard(),
      const SizedBox(height: 14),
      _outcomeCard(),
      const SizedBox(height: 14),
      _ratingCard(),
      const SizedBox(height: 14),
      _hoursCard(),
      const SizedBox(height: 14),
      _weekdayCard(),
      const SizedBox(height: 14),
      _servicesCard(),
      if ((_ratings['recent'] as List<dynamic>? ?? []).isNotEmpty) ...[
        const SizedBox(height: 14),
        _commentsCard(),
      ],
    ];
  }

  Widget _emptyRange() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.insights_rounded, color: AppBrand.textSubtle, size: 34),
          const SizedBox(height: 12),
          const Text(
            'Nothing in this range yet',
            style: TextStyle(
              color: AppBrand.chalk,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No appointments or walk-ins from ${_rangeCaption()}. '
            'Try a longer range.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppBrand.textMuted, fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Headline numbers
  // ---------------------------------------------------------------------------

  Widget _statGrid() {
    final totals = _totals;
    final rate = (totals['completionRate'] as num?)?.toInt();
    final average = (_ratings['average'] as num?)?.toDouble();
    final ratingCount = (_ratings['count'] as num?)?.toInt() ?? 0;
    final value = (totals['serviceValue'] as num?)?.toDouble() ?? 0;
    final minutes = (totals['avgServiceMinutes'] as num?)?.toDouble();
    final sample = (totals['avgServiceSample'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Haircuts done',
                '${(totals['completed'] as num?)?.toInt() ?? 0}',
                '+ ${(totals['walkinsServed'] as num?)?.toInt() ?? 0} walk-ins',
                Icons.content_cut_rounded,
                AppBrand.success,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Showed up',
                rate == null ? '--' : '$rate%',
                rate == null ? 'nothing finished yet' : 'of finished bookings',
                Icons.verified_rounded,
                AppBrand.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statCard(
                'Your rating',
                average == null ? '--' : average.toStringAsFixed(2),
                ratingCount == 0
                    ? 'no ratings yet'
                    : '$ratingCount rating${ratingCount == 1 ? '' : 's'}, all time',
                Icons.star_rounded,
                AppBrand.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statCard(
                'Service value',
                _peso(value),
                // Named "value", not "earnings": this is what the services were
                // priced at, which is not the same as what the barber takes.
                'priced work completed',
                Icons.payments_rounded,
                AppBrand.chalk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _factRow([
          _fact('${(totals['uniqueCustomers'] as num?)?.toInt() ?? 0}', 'customers'),
          _fact('${(totals['repeatCustomers'] as num?)?.toInt() ?? 0}', 'came back'),
          _fact(
            minutes == null ? '--' : '${minutes.round()}m',
            sample < 5 ? 'avg cut (few)' : 'avg cut',
          ),
        ]),
      ],
    );
  }

  Widget _statCard(
    String label,
    String value,
    String caption,
    IconData icon,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 13, 13, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppBrand.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppBrand.chalk,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppBrand.textSubtle, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _factRow(List<Widget> facts) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppBrand.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 26, color: AppBrand.border),
            Expanded(child: facts[i]),
          ],
        ],
      ),
    );
  }

  Widget _fact(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppBrand.chalk,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppBrand.textSubtle, fontSize: 10.5),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Work per day
  // ---------------------------------------------------------------------------

  Widget _workPerDayCard() {
    final daily = _list('daily');
    // 90 one-pixel bars tell nobody anything, so a long range is bucketed into
    // weeks. The axis label says which it is rather than leaving the barber to
    // work it out from bar count.
    final weekly = daily.length > 31;
    final buckets = weekly ? _toWeeks(daily) : daily;

    final maxValue = buckets.fold<int>(1, (best, bucket) {
      final total = _bucketTotal(bucket);
      return total > best ? total : best;
    });

    return _chartCard(
      title: weekly ? 'Work per week' : 'Work per day',
      subtitle: 'Stacked: finished, walk-ins, then what fell through.',
      legend: const [
        _LegendItem('Finished', AppBrand.success),
        _LegendItem('Walk-ins', AppBrand.warning),
        _LegendItem('Open', AppBrand.accent),
        _LegendItem('Lost', AppBrand.poleRedText),
      ],
      child: Column(
        children: [
          SizedBox(
            height: 132,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < buckets.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: buckets.length > 20 ? 0.6 : 2,
                      ),
                      child: _stackedBar(buckets[i], maxValue),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(buckets.first['date']?.toString() ?? ''),
                style: const TextStyle(color: AppBrand.textSubtle, fontSize: 10),
              ),
              Text(
                'peak $maxValue',
                style: const TextStyle(
                  color: AppBrand.textSubtle,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _shortDate(buckets.last['date']?.toString() ?? ''),
                style: const TextStyle(color: AppBrand.textSubtle, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _bucketTotal(Map<String, dynamic> bucket) {
    final completed = (bucket['completed'] as num?)?.toInt() ?? 0;
    final cancelled = (bucket['cancelled'] as num?)?.toInt() ?? 0;
    final booked = (bucket['booked'] as num?)?.toInt() ?? 0;
    final walkins = (bucket['walkins'] as num?)?.toInt() ?? 0;
    final open = math.max(0, booked - completed - cancelled);

    return completed + cancelled + walkins + open;
  }

  List<Map<String, dynamic>> _toWeeks(List<Map<String, dynamic>> daily) {
    final weeks = <Map<String, dynamic>>[];
    for (var i = 0; i < daily.length; i += 7) {
      final slice = daily.sublist(i, math.min(i + 7, daily.length));
      weeks.add({
        'date': slice.first['date'],
        'completed': slice.fold<int>(0, (a, d) => a + ((d['completed'] as num?)?.toInt() ?? 0)),
        'cancelled': slice.fold<int>(0, (a, d) => a + ((d['cancelled'] as num?)?.toInt() ?? 0)),
        'booked': slice.fold<int>(0, (a, d) => a + ((d['booked'] as num?)?.toInt() ?? 0)),
        'walkins': slice.fold<int>(0, (a, d) => a + ((d['walkins'] as num?)?.toInt() ?? 0)),
      });
    }

    return weeks;
  }

  Widget _stackedBar(Map<String, dynamic> bucket, int maxValue) {
    final completed = (bucket['completed'] as num?)?.toInt() ?? 0;
    final cancelled = (bucket['cancelled'] as num?)?.toInt() ?? 0;
    final booked = (bucket['booked'] as num?)?.toInt() ?? 0;
    final walkins = (bucket['walkins'] as num?)?.toInt() ?? 0;
    final open = math.max(0, booked - completed - cancelled);
    final total = completed + walkins + open + cancelled;

    if (total == 0) {
      // A visible floor for empty days. Without it a quiet week looks like
      // missing data rather than a quiet week.
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: AppBrand.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    final height = (total / maxValue) * 124;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: math.max(height, 3),
          child: Column(
            children: [
              if (cancelled > 0)
                Expanded(flex: cancelled, child: const ColoredBox(color: AppBrand.poleRedText)),
              if (open > 0)
                Expanded(flex: open, child: const ColoredBox(color: AppBrand.accent)),
              if (walkins > 0)
                Expanded(flex: walkins, child: const ColoredBox(color: AppBrand.warning)),
              if (completed > 0)
                Expanded(flex: completed, child: const ColoredBox(color: AppBrand.success)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Outcome mix
  // ---------------------------------------------------------------------------

  Widget _outcomeCard() {
    final mix = Map<String, dynamic>.from(_data?['statusMix'] as Map? ?? {});
    final completed = (mix['Completed'] as num?)?.toInt() ?? 0;
    final cancelled = (mix['Cancelled'] as num?)?.toInt() ?? 0;
    final noShow = (mix['NoShow'] as num?)?.toInt() ?? 0;
    final open = (mix['Open'] as num?)?.toInt() ?? 0;
    final total = completed + cancelled + noShow + open;
    final rate = (_totals['completionRate'] as num?)?.toInt();

    return _chartCard(
      title: 'How bookings ended',
      subtitle: 'Every appointment in this range, by outcome.',
      child: Row(
        children: [
          SizedBox(
            width: 124,
            height: 124,
            child: CustomPaint(
              painter: _DonutPainter(
                slices: [
                  _DonutSlice(completed, AppBrand.success),
                  _DonutSlice(open, AppBrand.accent),
                  _DonutSlice(cancelled, AppBrand.poleRedText),
                  _DonutSlice(noShow, AppBrand.warning),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rate == null ? '--' : '$rate%',
                      style: const TextStyle(
                        color: AppBrand.chalk,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'completed',
                      style: TextStyle(color: AppBrand.textSubtle, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              children: [
                _mixRow('Completed', completed, total, AppBrand.success),
                _mixRow('Still open', open, total, AppBrand.accent),
                _mixRow('Cancelled', cancelled, total, AppBrand.poleRedText),
                _mixRow('No show', noShow, total, AppBrand.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mixRow(String label, int value, int total, Color color) {
    final share = total == 0 ? 0 : ((value / total) * 100).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppBrand.textMuted, fontSize: 12),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: AppBrand.chalk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 32,
            child: Text(
              '$share%',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppBrand.textSubtle, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ratings
  // ---------------------------------------------------------------------------

  Widget _ratingCard() {
    final distribution = Map<String, dynamic>.from(_ratings['distribution'] as Map? ?? {});
    final count = (_ratings['count'] as num?)?.toInt() ?? 0;
    final average = (_ratings['average'] as num?)?.toDouble();
    final maxCount = distribution.values.fold<int>(
      1,
      (best, v) => (v as num).toInt() > best ? (v).toInt() : best,
    );

    return _chartCard(
      title: 'What customers scored you',
      // Said out loud because the figure is not windowed like everything else
      // on the page, and a barber comparing it against the range would be
      // comparing two different things.
      subtitle: count == 0
          ? 'No ratings yet. Customers rate you after a completed booking.'
          : 'All $count rating${count == 1 ? '' : 's'} ever left, not just this range.',
      child: count == 0
          ? const SizedBox.shrink()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      average?.toStringAsFixed(2) ?? '--',
                      style: const TextStyle(
                        color: AppBrand.chalk,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: List.generate(5, (i) {
                        final filled = (average ?? 0) >= i + 0.5;
                        return Icon(
                          filled ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 13,
                          color: filled ? AppBrand.warning : AppBrand.textSubtle,
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    children: [
                      for (var score = 5; score >= 1; score--)
                        _ratingBar(
                          score,
                          ((distribution['$score'] as num?)?.toInt() ?? 0),
                          maxCount,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _ratingBar(int score, int value, int maxCount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$score',
            style: const TextStyle(
              color: AppBrand.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 10, color: AppBrand.textSubtle),
          const SizedBox(width: 7),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: maxCount == 0 ? 0 : value / maxCount,
                minHeight: 8,
                backgroundColor: AppBrand.surfaceLift,
                valueColor: const AlwaysStoppedAnimation(AppBrand.warning),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 18,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppBrand.textMuted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // When the work lands
  // ---------------------------------------------------------------------------

  Widget _hoursCard() {
    final hours = _list('hours');
    if (hours.isEmpty) {
      return _chartCard(
        title: 'Busiest hours',
        subtitle: 'No booked hours in this range.',
        child: const SizedBox.shrink(),
      );
    }

    final byHour = <int, int>{};
    for (final row in hours) {
      byHour[(row['hour'] as num?)?.toInt() ?? 0] = (row['count'] as num?)?.toInt() ?? 0;
    }

    final first = byHour.keys.reduce(math.min);
    final last = byHour.keys.reduce(math.max);
    final maxCount = byHour.values.reduce(math.max);
    final peak = byHour.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    return _chartCard(
      title: 'Busiest hours',
      subtitle: 'Your queue is heaviest around ${_hourLabel(peak)}.',
      child: SizedBox(
        height: 108,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var hour = first; hour <= last; hour++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        (byHour[hour] ?? 0) == 0 ? '' : '${byHour[hour]}',
                        style: const TextStyle(
                          color: AppBrand.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: math.max(((byHour[hour] ?? 0) / maxCount) * 66, 2),
                        decoration: BoxDecoration(
                          color: hour == peak
                              ? AppBrand.accent
                              : AppBrand.accent.withValues(alpha: 0.4),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _hourTick(hour),
                        maxLines: 1,
                        style: const TextStyle(color: AppBrand.textSubtle, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayCard() {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final rows = _list('weekdays');
    final byDay = <int, int>{for (var i = 1; i <= 7; i++) i: 0};
    for (final row in rows) {
      final day = (row['weekday'] as num?)?.toInt() ?? 0;
      if (day >= 1 && day <= 7) {
        byDay[day] = (row['count'] as num?)?.toInt() ?? 0;
      }
    }

    final maxCount = byDay.values.fold<int>(1, math.max);
    final busiest = byDay.entries.reduce((a, b) => a.value >= b.value ? a : b);

    return _chartCard(
      title: 'Busiest days',
      subtitle: busiest.value == 0
          ? 'Nothing booked in this range.'
          : '${names[busiest.key - 1]} is your heaviest day.',
      child: Column(
        children: [
          for (var day = 1; day <= 7; day++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      names[day - 1],
                      style: TextStyle(
                        color: day == busiest.key && busiest.value > 0
                            ? AppBrand.chalk
                            : AppBrand.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (byDay[day] ?? 0) / maxCount,
                        minHeight: 9,
                        backgroundColor: AppBrand.surfaceLift,
                        valueColor: AlwaysStoppedAnimation(
                          day == busiest.key && busiest.value > 0
                              ? AppBrand.success
                              : AppBrand.success.withValues(alpha: 0.42),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${byDay[day]}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppBrand.textMuted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Services and comments
  // ---------------------------------------------------------------------------

  Widget _servicesCard() {
    final services = _list('topServices');
    if (services.isEmpty) {
      return _chartCard(
        title: 'What you cut most',
        subtitle: 'No completed services in this range yet.',
        child: const SizedBox.shrink(),
      );
    }

    final maxCount = services.fold<int>(
      1,
      (best, s) => math.max(best, (s['count'] as num?)?.toInt() ?? 0),
    );

    return _chartCard(
      title: 'What you cut most',
      subtitle: 'Completed services, with what they were priced at.',
      child: Column(
        children: [
          for (final service in services)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          service['name']?.toString() ?? 'Service',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppBrand.chalk,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${(service['count'] as num?)?.toInt() ?? 0}x',
                        style: const TextStyle(
                          color: AppBrand.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _peso((service['value'] as num?)?.toDouble() ?? 0),
                        style: const TextStyle(color: AppBrand.textSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ((service['count'] as num?)?.toInt() ?? 0) / maxCount,
                      minHeight: 7,
                      backgroundColor: AppBrand.surfaceLift,
                      valueColor: const AlwaysStoppedAnimation(AppBrand.accent),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentsCard() {
    final recent = (_ratings['recent'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return _chartCard(
      title: 'What they said',
      subtitle: 'The most recent comments left with a rating.',
      child: Column(
        children: [
          for (final item in recent)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppBrand.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppBrand.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Row(
                        children: List.generate(5, (i) {
                          final score = (item['rating'] as num?)?.toInt() ?? 0;
                          return Icon(
                            i < score ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 12,
                            color: i < score ? AppBrand.warning : AppBrand.textSubtle,
                          );
                        }),
                      ),
                      const Spacer(),
                      Text(
                        _shortDate(item['createdAt']?.toString() ?? ''),
                        style: const TextStyle(color: AppBrand.textSubtle, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item['comment']?.toString() ?? '',
                    style: const TextStyle(
                      color: AppBrand.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared chrome and formatting
  // ---------------------------------------------------------------------------

  Widget _chartCard({
    required String title,
    required String subtitle,
    required Widget child,
    List<_LegendItem> legend = const [],
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppBrand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppBrand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppBrand.chalk,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppBrand.textSubtle,
              fontSize: 11,
              height: 1.35,
            ),
          ),
          if (legend.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 6, children: legend),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  String _peso(double value) {
    if (value >= 1000000) return '₱${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 10000) return '₱${(value / 1000).toStringAsFixed(1)}k';

    return '₱${value.round()}';
  }

  String _hourLabel(int hour) {
    final suffix = hour >= 12 ? 'PM' : 'AM';
    final display = hour % 12 == 0 ? 12 : hour % 12;

    return '$display $suffix';
  }

  String _hourTick(int hour) {
    final display = hour % 12 == 0 ? 12 : hour % 12;

    return '$display';
  }

  String _shortDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${date.day} ${months[date.month - 1]}';
  }
}

class _LegendItem extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendItem(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(color: AppBrand.textMuted, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _DonutSlice {
  final int value;
  final Color color;

  const _DonutSlice(this.value, this.color);
}

/// A ring, drawn by hand so the page needs no chart dependency.
class _DonutPainter extends CustomPainter {
  final List<_DonutSlice> slices;

  const _DonutPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(0, (sum, slice) => sum + slice.value);
    final stroke = size.shortestSide * 0.17;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (size.shortestSide - stroke) / 2,
    );

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppBrand.surfaceLift;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    if (total == 0) return;

    // A hair of padding between slices, so two adjacent colours do not read as
    // one wedge. Dropped for slivers too small to survive it.
    const gap = 0.035;
    var start = -math.pi / 2;

    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = (slice.value / total) * math.pi * 2;
      final padded = sweep > gap * 2 ? sweep - gap : sweep;

      canvas.drawArc(
        rect,
        start,
        padded,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = slice.color,
      );

      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) return true;
    for (var i = 0; i < slices.length; i++) {
      if (oldDelegate.slices[i].value != slices[i].value) return true;
    }

    return false;
  }
}
