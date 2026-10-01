import 'package:flutter/material.dart';

import 'kiosk_api.dart';
import 'kiosk_theme.dart';
import 'widgets/kiosk_scaffold.dart';

/// Lets a walk-in find their own queue number again.
///
/// The queue number is called out loud, so it is easy to overhear and claim.
/// The guard against that is a claim code — but a code is only useful if the
/// customer can get it back, and a walk-in may have no phone to photograph the
/// screen with. The kiosk is already standing in the shop, so it is the
/// recovery path: type your name, see your number, position and code again.
///
/// Same-name customers are told apart by the style each of them picked, which
/// they chose minutes ago and will always recognise.
class KioskQueueLookupPage extends StatefulWidget {
  const KioskQueueLookupPage({super.key});

  @override
  State<KioskQueueLookupPage> createState() => _KioskQueueLookupPageState();
}

class _KioskQueueLookupPageState extends State<KioskQueueLookupPage> {
  final _nameController = TextEditingController();

  bool _searching = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _matches = [];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter at least 2 letters of your name.');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final matches = await KioskApi.lookupQueue(name);
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not reach the queue. Ask the front desk.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: 'Check my queue',
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Forgot your number?',
              style: TextStyle(
                color: KioskColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Type the name you joined with and we will show it again.',
              style: TextStyle(color: KioskColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              style: const TextStyle(color: KioskColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Your name'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Color(0xFFE74C3C))),
            ],
            const SizedBox(height: 16),
            KioskPrimaryButton(
              label: 'Find my number',
              loading: _searching,
              onPressed: _search,
            ),
            const SizedBox(height: 24),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (!_searched) {
      return const SizedBox.shrink();
    }
    if (_matches.isEmpty) {
      return const Text(
        'Nothing in today\'s queue under that name. Check the spelling, or ask '
        'the front desk — they can see the whole queue.',
        style: TextStyle(color: KioskColors.textMuted, height: 1.4),
      );
    }

    return ListView.separated(
      itemCount: _matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _matchCard(_matches[index]),
    );
  }

  Widget _matchCard(Map<String, dynamic> match) {
    final style = match['style']?.toString() ?? '';
    final barber = match['barber']?.toString() ?? '';
    final waitMinutes = (match['waitMinutes'] as num?)?.toInt() ?? 0;
    final inService = match['status']?.toString() == 'InProgress';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KioskColors.accentTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: KioskColors.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                match['queueNumber']?.toString() ?? '',
                style: const TextStyle(
                  color: KioskColors.accent,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                inService ? 'In the chair' : 'About $waitMinutes min',
                style: const TextStyle(color: KioskColors.textMuted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            match['guestName']?.toString() ?? '',
            style: const TextStyle(
              color: KioskColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          // What they picked is how two people with the same name tell their
          // own row apart — they chose it minutes ago.
          const SizedBox(height: 4),
          Text(
            [
              match['service']?.toString() ?? '',
              if (style.isNotEmpty) style,
              if (barber.isNotEmpty) 'with $barber',
            ].where((part) => part.isNotEmpty).join(' · '),
            style: const TextStyle(color: KioskColors.textMuted, fontSize: 13, height: 1.4),
          ),
          if ((match['claimCode']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Code ',
                  style: TextStyle(color: KioskColors.textDim, fontSize: 13),
                ),
                Text(
                  match['claimCode'].toString(),
                  style: const TextStyle(
                    color: KioskColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
