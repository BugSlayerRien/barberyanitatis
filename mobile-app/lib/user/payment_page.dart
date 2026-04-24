import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'appointments_page.dart';
import 'api_config.dart';
import 'time_format_utils.dart';

class PaymentPage extends StatefulWidget {
  final int appointmentID;
  final String barberName;
  final String date;
  final String time;
  final int amount;
  final String haircutName;

  const PaymentPage({
    super.key,
    required this.appointmentID,
    required this.barberName,
    required this.date,
    required this.time,
    required this.amount,
    required this.haircutName,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  int _selectedMethod = 0; // 0=Card,1=Gcash/Qrph
  bool _processing = false;
  String? _intentStatusLabel;
  String? _receiptRef;

  Future<void> _startPaymentIntent(double total) async {
    if (_processing) {
      return;
    }

    setState(() => _processing = true);
    try {
      final method = _selectedMethod == 0 ? 'Card' : 'GCash/QRPh';
      final createIntentResponse = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/payments.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'createIntent',
          'appointmentID': widget.appointmentID,
          'amount': double.parse(total.toStringAsFixed(2)),
          'method': method,
          'provider': 'mock',
          'expiresMinutes': 10,
        }),
      );

      if (!mounted) {
        return;
      }

      final data = createIntentResponse.body.isNotEmpty
          ? jsonDecode(createIntentResponse.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (createIntentResponse.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Payment failed.')),
        );
        return;
      }

      if ((data['paymentState']?.toString() ?? '') == 'Paid') {
        setState(() {
          _intentStatusLabel = 'Payment already completed';
          _receiptRef = data['receiptRef']?.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment already confirmed for this appointment.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppointmentsPage()),
          (route) => false,
        );
        return;
      }

      final intent = data['intent'] is Map ? Map<String, dynamic>.from(data['intent'] as Map) : <String, dynamic>{};
      final intentID = int.tryParse('${intent['intentID'] ?? ''}') ?? 0;
      final intentToken = intent['intentToken']?.toString() ?? '';

      if (intentID <= 0 || intentToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to initialize payment intent.')),
        );
        return;
      }

      setState(() => _intentStatusLabel = 'Waiting for gateway confirmation...');

      await _showMockCheckout(intentID: intentID, intentToken: intentToken, amount: total);

      if (!mounted) {
        return;
      }

      final statusData = await _pollIntentUntilFinal(intentID);
      if (!mounted || statusData == null) {
        return;
      }

      final paymentState = statusData['paymentState']?.toString() ?? 'Unpaid';
      final receipt = statusData['receiptRef']?.toString();

      setState(() {
        _receiptRef = receipt;
        _intentStatusLabel = paymentState == 'Paid' ? 'Payment verified' : 'Payment not completed';
      });

      if (paymentState == 'Paid') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(receipt != null && receipt.isNotEmpty ? 'Payment successful ($receipt)' : 'Payment successful.')),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AppointmentsPage()),
          (route) => false,
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment not completed. You can retry.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _showMockCheckout({
    required int intentID,
    required String intentToken,
    required double amount,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool submitting = false;

        Future<void> submitOutcome(String outcome) async {
          if (submitting) {
            return;
          }
          submitting = true;
          try {
            await http.post(
              Uri.parse('${ApiConfig.baseUrl}/payments.php'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'action': 'mockProviderWebhook',
                'intentID': intentID,
                'intentToken': intentToken,
                'outcome': outcome,
              }),
            );
          } finally {
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
            }
          }
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mock Checkout',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Amount: ₱${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 4),
              const Text(
                'Fallback mode is active while payment gateway integration is in progress.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => submitOutcome('failed'),
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE74C3C)),
                      child: const Text('Simulate Failed'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => submitOutcome('paid'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                      child: const Text('Simulate Success'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _pollIntentUntilFinal(int intentID) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/payments.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getIntentStatus',
          'intentID': intentID,
        }),
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        return data;
      }

      final paymentState = data['paymentState']?.toString() ?? 'Unpaid';
      if (paymentState == 'Paid' || paymentState == 'Failed') {
        return data;
      }

      await Future.delayed(const Duration(milliseconds: 700));
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final servicePrice = widget.amount.toDouble();
    const tax = 0.0;
    final total = servicePrice + tax;
    final displayTime = formatTo12Hour(widget.time);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            Text('${widget.date} • $displayTime', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 20),

            if (_intentStatusLabel != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  _receiptRef != null && _receiptRef!.isNotEmpty
                      ? '$_intentStatusLabel • $_receiptRef'
                      : _intentStatusLabel!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Payment Methods
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose Payment Method', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  // Card (uses single credit card icon)
                  _paymentMethodTile(
                    0,
                    title: 'Credit/Debit Card',
                    trailing: Row(children: [
                      _paymentIcon('assets/images/creditcard.png'),
                    ]),
                  ),

                  const SizedBox(height: 8),

                  // GCash / QRPh
                  _paymentMethodTile(1, title: 'Gcash, Paymaya, QRPh', trailing: _paymentIcon('assets/images/gcash.png')),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Mock card inputs (only visible for card method)
            if (_selectedMethod == 0) ...[
              const TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  hintText: 'John Doe',
                ),
              ),
              const SizedBox(height: 8),
              const TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  hintText: '1234 5678 9012 3456',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(filled: true, fillColor: Colors.black, hintText: 'MM/YY'),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(filled: true, fillColor: Colors.black, hintText: 'CVV'),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Summary Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.haircutName, style: const TextStyle(color: Colors.white70)),
                      Text('₱${servicePrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax', style: TextStyle(color: Colors.white70)),
                      Text('₱${tax.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _processing ? null : () => _startPaymentIntent(total),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _processing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text('Confirm & Continue', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodTile(int id, {required String title, Widget? trailing}) {
    final selected = _selectedMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111111) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.white : Colors.white10),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: id,
              groupValue: _selectedMethod,
              onChanged: (v) => setState(() => _selectedMethod = v ?? 0),
              fillColor: MaterialStateProperty.all(Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _paymentIcon(String asset) {
    return Image.asset(
      asset,
      height: 20,
      width: 40,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        height: 20,
        width: 40,
        alignment: Alignment.center,
        child: const Icon(Icons.payment, color: Colors.white24, size: 18),
      ),
    );
  }
}
