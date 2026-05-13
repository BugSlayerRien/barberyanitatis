import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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
  bool _processing = false;
  String? _intentStatusLabel;
  String? _receiptRef;
  String _selectedMethod = 'gcash';

  String _paymentApiRoot() {
    final root = ApiConfig.rootUrl.replaceAll(RegExp(r'/$'), '');
    return '$root/mobile-app';
  }

  String _paymentReturnUrl(bool success) {
    final base = _paymentApiRoot();
    return success ? '$base/payment-success' : '$base/payment-failed';
  }

  String? _extractCheckoutUrl(Map<String, dynamic> body) {
    return body['checkout_url']?.toString() ??
        body['data']?['attributes']?['redirect']?['checkout_url']?.toString() ??
        body['data']?['attributes']?['next_action']?['redirect']?['url']?.toString() ??
        body['raw']?['data']?['attributes']?['redirect']?['checkout_url']?.toString();
  }

  Future<void> _openCheckoutUrlIfPresent(String? checkoutUrl) async {
    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null) {
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startPaymentIntent(double total) async {
    if (_processing) {
      return;
    }

    setState(() => _processing = true);
    try {
      // Create payment intent via backend PayMongo endpoint
      final cents = (total * 100).round();
      final paymentRoot = _paymentApiRoot();
      final createIntentResponse = await http.post(
        Uri.parse('$paymentRoot/backend/paymongo/create-payment.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': cents,
          'currency': 'PHP',
          'method': _selectedMethod,
          'description': 'Appointment ${widget.appointmentID}',
          'appointment_id': widget.appointmentID.toString(),
          'success_url': _paymentReturnUrl(true),
          'failed_url': _paymentReturnUrl(false),
        }),
      );

      if (!mounted) return;

      final data = createIntentResponse.body.isNotEmpty
          ? jsonDecode(createIntentResponse.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (createIntentResponse.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['error']?.toString() ?? 'Payment failed.')),
        );
        return;
      }

      final resourceId = data['resource_id']?.toString() ?? data['data']?['id']?.toString() ?? '';
      final resourceType = data['resource_type']?.toString() ??
          (resourceId.startsWith('src_') ? 'source' : 'payment_intent');
      final checkoutUrl = _extractCheckoutUrl(data);

      if (resourceId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to initialize payment intent.')),
        );
        return;
      }

      setState(() => _intentStatusLabel = 'Waiting for gateway confirmation...');

      if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
        await _openCheckoutUrlIfPresent(checkoutUrl);
        if (!mounted) return;
        setState(() => _intentStatusLabel = 'Complete payment in the opened browser/app...');
      }

      final statusData = await _pollPaymentUntilFinal(resourceId, resourceType: resourceType);
      if (!mounted || statusData == null) return;

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
          MaterialPageRoute(
            builder: (_) => AppointmentsPage(
              highlightAppointmentId: widget.appointmentID,
              forcedPaymentState: 'Paid',
              forcedReceiptRef: receipt,
            ),
          ),
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

  // Mock checkout removed. Real gateway flow handled via server endpoints and hosted pages.

  Future<Map<String, dynamic>?> _pollPaymentUntilFinal(
    String id, {
    required String resourceType,
  }) async {
    final normalizedType = resourceType.toLowerCase();
    final paymentRoot = _paymentApiRoot();
    for (var attempt = 0; attempt < 24; attempt++) {
      try {
        final uri = Uri.parse(
          '$paymentRoot/backend/paymongo/payment-status.php?intent_id=$id&resource_type=$normalizedType',
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 5));

        final data = response.body.isNotEmpty
            ? jsonDecode(response.body) as Map<String, dynamic>
            : <String, dynamic>{};

        if (response.statusCode != 200) {
          debugPrint('Payment status check failed (attempt $attempt): ${response.statusCode}');
          debugPrint('Response: ${response.body}');
          return {'paymentState': 'Unknown', 'raw': data};
        }

        final status = data['data']?['attributes']?['status']?.toString().toLowerCase() ?? '';
        debugPrint('Payment status poll attempt $attempt: status=$status');
        
        if (status == 'paid' || status == 'succeeded') {
          return {
            'paymentState': 'Paid',
            'receiptRef': data['data']?['attributes']?['receipt']?.toString(),
          };
        }
        if (status == 'failed' || status == 'canceled' || status == 'expired') {
          return {'paymentState': 'Failed'};
        }

        if (normalizedType == 'source') {
          if (status == 'chargeable' || status == 'pending') {
            if (mounted) {
              setState(() => _intentStatusLabel = 'Payment authorized. Waiting for gateway finalization...');
            }
          }
        }

        await Future.delayed(const Duration(seconds: 2));
      } catch (e) {
        debugPrint('Payment status poll error (attempt $attempt): $e');
        // Continue polling on transient errors
        await Future.delayed(const Duration(seconds: 2));
      }
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
                  const Text('Payment Method', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _paymentMethodTile(
                    title: 'GCash',
                    trailing: _paymentIcon('assets/images/gcash.png'),
                    selected: _selectedMethod == 'gcash',
                    onTap: () => setState(() => _selectedMethod = 'gcash'),
                  ),
                  const SizedBox(height: 8),
                  _paymentMethodTile(
                    title: 'GrabPay',
                    trailing: const Icon(Icons.account_balance_wallet, color: Colors.white70, size: 18),
                    selected: _selectedMethod == 'grab_pay',
                    onTap: () => setState(() => _selectedMethod = 'grab_pay'),
                  ),
                  const SizedBox(height: 8),
                  _paymentMethodTile(
                    title: 'Card',
                    trailing: const Icon(Icons.credit_card, color: Colors.white70, size: 18),
                    selected: _selectedMethod == 'card',
                    onTap: () => setState(() => _selectedMethod = 'card'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            const SizedBox(height: 4),

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

  Widget _paymentMethodTile({
    required String title,
    Widget? trailing,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF1A1A1A) : const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? Colors.white54 : Colors.white12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_2, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
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
