import 'dart:async';

import 'package:flutter/material.dart';

import '../user/app_brand.dart';
import 'kiosk_api.dart';
import 'kiosk_consent_page.dart';
import 'kiosk_queue_lookup_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

class KioskHomePage extends StatefulWidget {
  const KioskHomePage({super.key});

  @override
  State<KioskHomePage> createState() => _KioskHomePageState();
}

class _KioskHomePageState extends State<KioskHomePage> {
  bool _loadingQueue = true;
  String? _queueError;
  List<Map<String, dynamic>> _queue = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadQueue());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    try {
      final rows = await KioskApi.loadTodayQueue();
      if (!mounted) return;
      setState(() {
        _queue = rows;
        _queueError = null;
        _loadingQueue = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _queueError = '$e';
        _loadingQueue = false;
      });
    }
  }

  void _checkQueue() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskQueueLookupPage()),
    );
  }

  void _startWalkIn() {
    KioskSession.reset();
    // Terms first: the next screens capture a name and photos, so consent has
    // to come before anything is collected, not after.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KioskConsentPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      showBack: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final queuePanel = _WalkInQueuePanel(
            loading: _loadingQueue,
            error: _queueError,
            queue: _queue,
            onRetry: _loadQueue,
          );
          final startPanel = _StartWalkInPanel(
            onStart: _startWalkIn,
            onCheckQueue: _checkQueue,
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: queuePanel),
                const VerticalDivider(width: 1, color: KioskColors.border),
                Expanded(flex: 2, child: startPanel),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: constraints.maxHeight * 0.42, child: queuePanel),
                const Divider(height: 1, color: KioskColors.border),
                SizedBox(height: constraints.maxHeight * 0.42, child: startPanel),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WalkInQueuePanel extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> queue;
  final VoidCallback onRetry;

  const _WalkInQueuePanel({
    required this.loading,
    required this.error,
    required this.queue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Walk-in queue',
            style: TextStyle(
              color: KioskColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Updates automatically every few seconds',
            style: TextStyle(color: KioskColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: KioskColors.accent))
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!, style: const TextStyle(color: KioskColors.textMuted)),
                            TextButton(onPressed: onRetry, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : queue.isEmpty
                        ? const Center(
                            child: Text(
                              'No one in the queue yet.\nBe the first!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: KioskColors.textMuted, height: 1.4),
                            ),
                          )
                        : ListView.separated(
                            itemCount: queue.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = queue[index];
                              final number = row['queue_number']?.toString() ?? '';
                              final name = row['guest_name']?.toString() ?? 'Guest';
                              final status = row['status']?.toString() ?? '';
                              final barber = row['barber_name']?.toString();
                              final waitMinutes = int.tryParse('${row['wait_time_minutes']}');
                              final showWait = waitMinutes != null &&
                                  waitMinutes > 0 &&
                                  (status == 'Waiting' || status == 'Assigned');
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: KioskColors.panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: KioskColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: KioskColors.accent,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        number,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              color: KioskColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (barber != null && barber.isNotEmpty)
                                            Text(
                                              'Barber: $barber',
                                              style: const TextStyle(color: KioskColors.textDim, fontSize: 11),
                                            ),
                                          if (showWait)
                                            Text(
                                              'Est. wait: $waitMinutes min',
                                              style: const TextStyle(
                                                color: KioskColors.accent,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          status,
                                          style: const TextStyle(color: KioskColors.textMuted, fontSize: 11),
                                        ),
                                        if (status == 'InProgress')
                                          const Text(
                                            'In service',
                                            style: TextStyle(color: KioskColors.accent, fontSize: 10),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _StartWalkInPanel extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onCheckQueue;

  const _StartWalkInPanel({required this.onStart, required this.onCheckQueue});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandWordmark(logoHeight: 90, tagline: 'Walk-In Kiosk'),
              const SizedBox(height: 16),
              const Text(
                'Get a haircut recommendation, pick your barber, and join the queue — no account needed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: KioskColors.textMuted, fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 32),
              KioskPrimaryButton(label: 'Start walk-in', onPressed: onStart),
              const SizedBox(height: 12),
              // A walk-in who forgot their number may have no phone to have
              // photographed it with, so the kiosk is the way back to it.
              TextButton(
                onPressed: onCheckQueue,
                child: const Text(
                  'Already in the queue? Check my number',
                  style: TextStyle(color: KioskColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
