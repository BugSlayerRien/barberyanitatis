import 'dart:async';

import 'package:flutter/material.dart';

import 'kiosk_api.dart';
import 'kiosk_done_page.dart';
import 'kiosk_payment_mode_page.dart';
import 'kiosk_session.dart';
import 'kiosk_theme.dart';
import '../user/user_session.dart';
import '../user/widgets/barber_avatar.dart';
import 'widgets/kiosk_scaffold.dart';

class KioskBarberPage extends StatefulWidget {
  const KioskBarberPage({super.key});

  @override
  State<KioskBarberPage> createState() => _KioskBarberPageState();
}

class _KioskBarberPageState extends State<KioskBarberPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _barbers = [];
  Map<String, dynamic>? _firstAvailable;
  int? _selectedBarberId;
  int? _serviceId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading && !_submitting) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final services = await KioskApi.loadServices();
      if (services.isNotEmpty) {
        Map<String, dynamic>? walkInService;
        for (final row in services) {
          final map = Map<String, dynamic>.from(row as Map);
          final channel = (map['service_channel']?.toString().toLowerCase() ?? '');
          if (channel == 'walk_in') {
            walkInService = map;
            break;
          }
        }
        walkInService ??= Map<String, dynamic>.from(services.first as Map);
        _serviceId = int.tryParse('${walkInService['service_id']}');
        if (_serviceId != null && _serviceId! > 0) {
          KioskSession.selectedServiceId = _serviceId;
        }
      }

      final data = await KioskApi.loadBarberQueue();
      setState(() {
        _barbers = (data['barbers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _firstAvailable = data['firstAvailable'] as Map<String, dynamic>?;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!silent) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _joinQueue() async {
    if (_selectedBarberId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a barber or first available')),
      );
      return;
    }

    final guestName = KioskSession.guestName ?? '';
    if (guestName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing guest name. Start over.')),
      );
      return;
    }

    final variantId = KioskSession.selectedVariantId ?? 0;

    final serviceId = KioskSession.selectedServiceId ?? _serviceId;
    if (serviceId == null || serviceId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walk-in service is not configured. Contact staff.')),
      );
      return;
    }

    // Ask how they will pay before the queue row is created, so the choice is
    // stored with it rather than having to be corrected at the till.
    final mode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => KioskPaymentModePage(
          onConfirm: (selected) async => Navigator.of(context).pop(selected),
        ),
      ),
    );
    if (!mounted || mode == null) return;

    setState(() => _submitting = true);
    try {
      final result = await KioskApi.createWalkin(
        guestName: guestName,
        serviceIds: [serviceId],
        barberId: _selectedBarberId!,
        variantId: variantId > 0 ? variantId : 0,
        styleName: KioskSession.selectedStyleName ??
            (KioskSession.entryPath == KioskEntryPath.knownStyle ? 'Walk-in' : 'Style'),
        scanMode: KioskSession.scanModeLabel,
        entryPath: KioskSession.entryPathLabel,
        // Carries the AI previews this guest generated through to the
        // barber: a walk-in has no account, so the scan session is the
        // only handle on that work.
        scanSessionId: UserSession.completedScanSessionId ??
            UserSession.activeScanSessionId ??
            '',
        consentAccepted: KioskSession.consentAccepted,
        paymentMode: mode,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => KioskDonePage(queueResult: result),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KioskScaffold(
      title: 'Choose your barber',
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KioskColors.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: KioskColors.textMuted)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    const Text(
                      'Estimated wait uses 35 minutes per regular haircut. Updates every few seconds.',
                      style: TextStyle(color: KioskColors.textDim, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (KioskSession.selectedStyleName != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: KioskColors.panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: KioskColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.content_cut, color: KioskColors.accent, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Style: ${KioskSession.selectedStyleName}',
                                style: const TextStyle(color: KioskColors.textPrimary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _BarberTile(
                      name: 'First available',
                      subtitle: _firstAvailable?['waitLabel']?.toString() ?? 'Shortest wait',
                      specialty: 'Any barber',
                      // Not a person, so no face and no initials -- "FA" in a
                      // circle beside three real photos reads as a fourth
                      // barber whose picture failed to load.
                      icon: Icons.shuffle_rounded,
                      selected: _selectedBarberId == 0,
                      onTap: () => setState(() => _selectedBarberId = 0),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Or pick a barber',
                      style: TextStyle(color: KioskColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ..._barbers.map((barber) {
                      final id = int.tryParse('${barber['barber_id']}') ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BarberTile(
                          name: barber['full_name']?.toString() ?? 'Barber',
                          subtitle: barber['waitLabel']?.toString() ?? '',
                          specialty: barber['specialty']?.toString() ?? '',
                          profileImage: BarberAvatar.imageFieldOf(barber),
                          queueCount: int.tryParse('${barber['queueCount']}') ?? 0,
                          selected: _selectedBarberId == id,
                          onTap: () => setState(() => _selectedBarberId = id),
                        ),
                      );
                    }),
                  ],
                ),
      bottomBar: KioskPrimaryButton(
        label: 'Join walk-in queue',
        loading: _submitting,
        onPressed: _loading ? null : _joinQueue,
      ),
    );
  }
}

class _BarberTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final String specialty;
  final String profileImage;
  final IconData? icon;
  final int queueCount;
  final bool selected;
  final VoidCallback onTap;

  const _BarberTile({
    required this.name,
    required this.subtitle,
    required this.specialty,
    this.profileImage = '',
    this.icon,
    this.queueCount = 0,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? KioskColors.accentTint : KioskColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: kioskCardDecoration(selected: selected),
          child: Row(
            children: [
              // Bigger than a list avatar on purpose: at a kiosk the guest is
              // standing, at arm's length, choosing a stranger by face.
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? KioskColors.accent : KioskColors.border,
                    width: 2,
                  ),
                ),
                child: icon != null
                    ? Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          color: KioskColors.panelAlt,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          icon,
                          color: selected ? KioskColors.accent : KioskColors.textMuted,
                          size: 24,
                        ),
                      )
                    : BarberAvatar(
                        profileImage: profileImage,
                        barberName: name,
                        size: 54,
                        background: KioskColors.panelAlt,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: KioskColors.textPrimary, fontWeight: FontWeight.w700)),
                    if (specialty.isNotEmpty)
                      Text(specialty, style: const TextStyle(color: KioskColors.textDim, fontSize: 11)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: KioskColors.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (queueCount > 0)
                      Text(
                        '$queueCount in queue',
                        style: const TextStyle(color: KioskColors.textDim, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? KioskColors.accent : KioskColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
