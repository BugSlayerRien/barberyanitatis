import 'dart:convert';

import 'package:flutter/material.dart';
import 'app_brand.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'payment_page.dart';
import 'customer_api.dart';
import 'time_format_utils.dart';
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
                        ...List.generate(_options.length, (index) {
                          final option = _options[index];
                          final selected = _selectedOptionIndex == index;
                          final slots = (option['slots'] as List<dynamic>? ?? []);
                          final times = slots
                              .map((s) => formatTo12Hour(Map<String, dynamic>.from(s as Map)['slotTime']?.toString() ?? ''))
                              .join(' → ');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              onTap: () => setState(() => _selectedOptionIndex = index),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.white : const Color(0xFF121212),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      option['description']?.toString() ?? 'Option ${index + 1}',
                                      style: TextStyle(
                                        color: selected ? Colors.black : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${option['slotDate']} · $times',
                                      style: TextStyle(
                                        color: selected ? Colors.black87 : Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
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
