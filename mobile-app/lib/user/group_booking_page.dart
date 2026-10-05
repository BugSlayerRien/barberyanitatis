import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'payment_page.dart';
import 'customer_api.dart';
import 'time_format_utils.dart';
import 'booking_guard.dart';
import 'user_session.dart';
import 'services/booking_draft_service.dart';

class GroupBookingPage extends StatefulWidget {
  final int barberId;
  final String barberName;
  final int peopleCount;

  const GroupBookingPage({
    super.key,
    required this.barberId,
    required this.barberName,
    required this.peopleCount,
  });

  @override
  State<GroupBookingPage> createState() => _GroupBookingPageState();
}

class _GroupBookingPageState extends State<GroupBookingPage> {
  bool _loading = true;
  String? _error;
  String? _statusReason;
  List<Map<String, dynamic>> _options = [];
  int _selectedOptionIndex = 0;
  // Null means "whatever is soonest" -- the server then spreads its answers
  // over the next few days instead of pinning to one.
  DateTime? _preferredDate;
  bool _confirmPartial = false;
  bool _bookingInFlight = false;
  double _pricePerPerson = 0;

  String get _customerName {
    final name = UserSession.fullName?.trim() ?? '';
    return name.isNotEmpty ? name : 'You';
  }

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _loadServicePrice();
  }

  Future<void> _loadServicePrice() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/services.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'list', 'channel': 'appointment'}),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final services = (data['services'] as List<dynamic>? ?? []);
      for (final row in services) {
        final service = Map<String, dynamic>.from(row as Map);
        if ((service['category']?.toString() ?? '') == 'Haircut') {
          final price = double.tryParse('${service['base_price']}') ?? 0;
          if (mounted) setState(() => _pricePerPerson = price);
          return;
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadOptions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/time_slots.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'findGroupSlots',
          'barberID': widget.barberId,
          'peopleCount': widget.peopleCount,
          if (_preferredDate != null) 'slotDate': _ymd(_preferredDate!),
        }),
      );
      final data = response.body.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(response.body) as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _error = data['error']?.toString() ?? 'Could not find group slots.';
          _loading = false;
        });
        return;
      }

      final options = (data['options'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _options = options;
        _statusReason = data['reason']?.toString();
        _selectedOptionIndex = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load options: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedOption {
    if (_options.isEmpty || _selectedOptionIndex < 0 || _selectedOptionIndex >= _options.length) {
      return null;
    }
    return _options[_selectedOptionIndex];
  }

  int get _effectivePeopleCount {
    final option = _selectedOption;
    if (option == null) return widget.peopleCount;
    final slots = (option['slots'] as List<dynamic>? ?? []);
    return slots.length;
  }

  int get _additionalGuests => (_effectivePeopleCount - 1).clamp(0, 4);

  double get _totalAmount => _pricePerPerson * _effectivePeopleCount;

  Future<void> _confirmBooking() async {
    final option = _selectedOption;
    if (option == null) return;
    if (UserSession.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in first.')),
      );
      return;
    }

    final type = option['type']?.toString() ?? '';
    if (type == 'partial' && !_confirmPartial) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirm partial group booking below before continuing.'),
        ),
      );
      return;
    }

    final slots = (option['slots'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (slots.isEmpty) return;

    if (!mounted) return;
    setState(() => _bookingInFlight = true);
    try {
      final data = await CustomerApi.postDecoded('booking.php', {
        'action': 'createGroup',
        'userID': UserSession.userId,
        'barberID': option['barberID'] ?? widget.barberId,
        'appointmentDate': option['slotDate'],
        'slots': slots,
        'memberNames': [_customerName],
        'peopleCount': widget.peopleCount,
        'requestedCount': widget.peopleCount,
        'allowPartial': type == 'partial' && _confirmPartial,
        'confirmPartial': type == 'partial' && _confirmPartial,
        'variantID': UserSession.selectedVariantId,
      });

      final groupIds = (data['group']?['appointmentIDs'] as List<dynamic>? ?? []);
      final firstGroupId = groupIds.isNotEmpty ? (groupIds.first as num).toInt() : null;
      final appointmentId = (data['appointmentID'] as num?)?.toInt() ?? firstGroupId;

      if (appointmentId == null || !mounted) {
        throw Exception('Missing appointment reference');
      }

      await BookingDraftService.clear();

      final firstSlot = slots.first['slotTime']?.toString() ?? '';
      final total = (data['totalAmount'] as num?)?.toDouble() ?? _totalAmount;
      final guestLabel = _additionalGuests > 0
          ? ' ($_customerName + $_additionalGuests guest${_additionalGuests == 1 ? '' : 's'})'
          : '';

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentPage(
            appointmentID: appointmentId,
            barberName: option['barberName']?.toString() ?? widget.barberName,
            date: option['slotDate']?.toString() ?? '',
            time: formatTo12Hour(firstSlot),
            amount: total.round(),
            haircutName: 'Group (${_effectivePeopleCount} people)$guestLabel',
          ),
        ),
      );

      // Backing out of payment used to strand the whole group as
      // PendingPayment, so picking a different time was refused with "You
      // already have an active appointment or group booking".
      await BookingGuard.releaseIfUnpaid(
        userId: UserSession.userId,
        appointmentId: appointmentId,
      );
      if (mounted) {
        setState(() => _selectedOptionIndex = -1);
        await _loadOptions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _bookingInFlight = false);
    }
  }

  /// Groups the server's options by day so the same sentence is not repeated
  /// ten times over.
  ///
  /// Every option used to render as "5 consecutive hour(s) with Francis Vasallo
  /// on 2026-10-06 starting 09:00" plus the whole arrow chain beneath it, which
  /// is a wall of text to read one number out of. The barber and the date are
  /// said once per group; the times become chips; the slot sequence appears
  /// only for the chip actually chosen.
  List<Widget> _buildOptionGroups() {
    final groups = <String, List<int>>{};
    final splitIndexes = <int>[];

    for (var i = 0; i < _options.length; i++) {
      final option = _options[i];
      // Splitting the party across barbers is a different shape of choice, so
      // it keeps its own labelled row rather than becoming a time chip.
      if (option['type']?.toString() == 'split_barbers') {
        splitIndexes.add(i);
        continue;
      }
      final key = '${option['slotDate']}|${option['barberName'] ?? ''}';
      groups.putIfAbsent(key, () => <int>[]).add(i);
    }

    final widgets = <Widget>[];
    groups.forEach((key, indexes) {
      final parts = key.split('|');
      widgets
        ..add(_buildDayHeading(parts.first, parts.length > 1 ? parts[1] : ''))
        ..add(const SizedBox(height: 8))
        ..add(Wrap(
          spacing: 8,
          runSpacing: 8,
          children: indexes.map(_buildTimeChip).toList(),
        ))
        ..add(const SizedBox(height: 18));
    });

    for (final index in splitIndexes) {
      widgets
        ..add(_buildSplitOption(index))
        ..add(const SizedBox(height: 12));
    }

    return widgets;
  }

  Widget _buildDayHeading(String slotDate, String barberName) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            _friendlyDate(slotDate),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (barberName.isNotEmpty)
          Text(
            barberName,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
      ],
    );
  }

  Widget _buildTimeChip(int index) {
    final option = _options[index];
    final selected = _selectedOptionIndex == index;
    final slots = (option['slots'] as List<dynamic>? ?? []);
    final first = slots.isNotEmpty
        ? Map<String, dynamic>.from(slots.first as Map)['slotTime']?.toString() ?? ''
        : '';

    return InkWell(
      onTap: () => setState(() => _selectedOptionIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppBrand.accent : const Color(0xFF121212),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? AppBrand.accent : Colors.white24),
        ),
        child: Text(
          formatTo12Hour(first),
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSplitOption(int index) {
    final option = _options[index];
    final selected = _selectedOptionIndex == index;
    final slots = (option['slots'] as List<dynamic>? ?? []);
    final first = slots.isNotEmpty
        ? Map<String, dynamic>.from(slots.first as Map)['slotTime']?.toString() ?? ''
        : '';

    return InkWell(
      onTap: () => setState(() => _selectedOptionIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppBrand.accent : const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppBrand.accent : Colors.white24),
        ),
        child: Row(
          children: [
            Icon(
              Icons.groups_outlined,
              size: 20,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All at ${formatTo12Hour(first)}, different barbers',
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_friendlyDate(option['slotDate']?.toString() ?? '')} · nobody waits for one barber',
                    style: TextStyle(
                      color: selected ? Colors.black87 : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The chosen option's slot-by-slot sequence, shown once rather than on
  /// every row.
  Widget _buildSelectionSummary() {
    final option = _selectedOption;
    if (option == null) {
      return const Text(
        'Pick a start time above.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      );
    }

    final slots = (option['slots'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final times = slots
        .map((slot) => formatTo12Hour(slot['slotTime']?.toString() ?? ''))
        .toList();
    final sameTime = times.isNotEmpty && times.every((t) => t == times.first);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppBrand.accentLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _friendlyDate(option['slotDate']?.toString() ?? ''),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sameTime
                ? '${times.first} · ${times.length} barbers at the same time'
                : times.join('  →  '),
            style: const TextStyle(color: AppBrand.accent, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _friendlyDate(String slotDate) {
    final parsed = DateTime.tryParse(slotDate);
    if (parsed == null) return slotDate;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    final today = DateTime.now();
    final isToday = parsed.year == today.year &&
        parsed.month == today.month &&
        parsed.day == today.day;
    final label = '${weekdays[parsed.weekday - 1]} ${parsed.day} ${months[parsed.month - 1]}';

    return isToday ? 'Today · $label' : label;
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Lets the group aim at a specific day.
  ///
  /// Without this the list only ever covered the next few days, because one
  /// free day fills the option cap on its own. Picking a date tells the server
  /// to search that day instead of the soonest ones.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? first,
      firstDate: first,
      // Matches the shop's 30-day booking window.
      lastDate: first.add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppBrand.accent,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() => _preferredDate = picked);
    await _loadOptions();
  }

  Widget _buildDateControl() {
    final pinned = _preferredDate != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: pinned ? Colors.black : Colors.white,
                backgroundColor: pinned ? AppBrand.accent : Colors.transparent,
                side: BorderSide(color: pinned ? AppBrand.accent : Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              label: Text(
                pinned ? _friendlyDate(_ymd(_preferredDate!)) : 'Pick a date',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (pinned) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: _loading
                  ? null
                  : () async {
                      setState(() => _preferredDate = null);
                      await _loadOptions();
                    },
              child: const Text('Soonest', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: Text(
          'Group of ${widget.peopleCount}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  ),
                )
              : _options.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _statusReason ?? 'No group slots available.',
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (_statusReason != null && _statusReason!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              _statusReason!,
                              style: const TextStyle(color: Colors.amber, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _buildDateControl(),
                        ..._buildOptionGroups(),
                        _buildSelectionSummary(),
                        const SizedBox(height: 16),
                        const Text(
                          'Booking for',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _customerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_additionalGuests > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '+ $_additionalGuests additional guest${_additionalGuests == 1 ? '' : 's'} (no extra names needed)',
                                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_selectedOption?['type']?.toString() == 'partial') ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _confirmPartial,
                            onChanged: (v) => setState(() => _confirmPartial = v == true),
                            title: const Text(
                              'I understand this books fewer people than requested',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.amber,
                          ),
                        ],
                        if (_pricePerPerson > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            'Estimated total: ₱${_totalAmount.toStringAsFixed(2)} (${_effectivePeopleCount} × ₱${_pricePerPerson.toStringAsFixed(2)})',
                            style: const TextStyle(color: AppBrand.accent, fontWeight: FontWeight.bold),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _bookingInFlight ? null : _confirmBooking,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _bookingInFlight
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Confirm group booking', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
