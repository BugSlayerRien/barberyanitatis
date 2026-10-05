import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'appointments_page.dart';
import 'api_config.dart';
import 'customer_api.dart';
import 'payment_return_guard.dart';
import 'time_format_utils.dart';
import 'user_session.dart';

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

  String _paymongoBase() {
    return ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
  }

  String _paymentReturnUrl(bool success) {
    final base = _paymongoBase();
    // purpose + appointment_id ride through payment-success.php's query
    // forwarding, so a return handled by PaymentResultPage knows which
    // booking it is about instead of parsing 0 and highlighting nothing.
    final query = '?purpose=booking&appointment_id=${widget.appointmentID}';

    return success
        ? '$base/paymongo/payment-success.php$query'
        : '$base/paymongo/payment-failed.php$query';
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
      final paymentRoot = _paymongoBase();
      final createIntentResponse = await http
          .post(
            Uri.parse('$paymentRoot/paymongo/create-payment.php'),
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
          )
          .timeout(CustomerApi.defaultTimeout);

      if (!mounted) return;

      final data = CustomerApi.decodeJsonObject(createIntentResponse);

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

      // Active for the whole trip out to the gateway and back: this page's own
      // poll below is what reliably resolves the payment, so the app-wide
      // deep-link listener in main.dart should not also push a second,
      // independent verifier for the same return. See PaymentReturnGuard.
      PaymentReturnGuard.enter();
      Map<String, dynamic>? statusData;
      try {
        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          await _openCheckoutUrlIfPresent(checkoutUrl);
          if (!mounted) return;
          setState(() => _intentStatusLabel = 'Complete payment in the opened browser/app...');
        }

        statusData = await _pollPaymentUntilFinal(resourceId, resourceType: resourceType);
      } finally {
        // _pollPaymentUntilFinal returns null only when it gave up waiting.
        // Then this return is unhandled, and the late deep link must reach
        // PaymentResultPage instead of being suppressed.
        final resolved = statusData != null;
        if (resolved) PaymentReturnGuard.markHandled(resourceId);
        PaymentReturnGuard.exit(resolved: resolved);
      }
      if (!mounted) return;
      if (statusData == null) {
        // The OS delivered the return while this poll was running, so the
        // guard held it back. The poll has now given up, so hand it over
        // rather than losing the only confirmation we were given.
        final suppressed = PaymentReturnGuard.takeSuppressedLink();
        if (suppressed != null) {
          Navigator.of(context).pushNamed('/payment-result', arguments: suppressed);

          return;
        }
        // The gateway never answered in time -- usually a dropped connection on
        // the way back from GCash, not a failed payment. Leaving the customer
        // on this screen made them think nothing happened; the server
        // reconciles a real payment on the next Bookings load
        // (sync_paid_appointments_from_payments), so send them there.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Still confirming your payment. If it went through, your booking "
              "updates here shortly -- don't pay again.",
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => AppointmentsPage(
              highlightAppointmentId: widget.appointmentID,
            ),
          ),
          (route) => false,
        );
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
    final paymentRoot = _paymongoBase();
    for (var attempt = 0; attempt < 24; attempt++) {
      try {
        final uri = Uri.parse(
          '$paymentRoot/paymongo/payment-status.php?intent_id=$id&resource_type=$normalizedType',
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 5));

        final data = CustomerApi.decodeJsonObject(response);

        if (response.statusCode != 200) {
          // A hiccup from the status endpoint is not an answer about the
          // payment. Returning here ended the poll, marked the return
          // "handled", and told a customer who had paid that the payment did
          // not complete -- inviting a second payment. Keep waiting instead.
          debugPrint('Payment status check failed (attempt $attempt): ${response.statusCode}');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }

        final status = data['data']?['attributes']?['status']?.toString().toLowerCase() ?? '';
        debugPrint('Payment status poll attempt $attempt: status=$status');
        
        if (status == 'paid' || status == 'succeeded') {
          final dbState = await _confirmPaymentInDatabase(
            providerRef: id,
            resourceType: resourceType,
          );
          return {
            'paymentState': dbState['paymentState']?.toString() ?? 'Paid',
            'receiptRef': dbState['receiptRef']?.toString() ??
                data['data']?['attributes']?['receipt']?.toString(),
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

  Future<Map<String, dynamic>> _confirmPaymentInDatabase({
    required String providerRef,
    required String resourceType,
  }) async {
    try {
      final data = await CustomerApi.postDecoded('payments.php', {
        'action': 'confirmGatewayPayment',
        'appointmentID': widget.appointmentID,
        'providerRef': providerRef,
        'resourceType': resourceType,
        'userID': UserSession.userId,
      });
      return {
        'paymentState': data['paymentState']?.toString() ?? 'Paid',
        'receiptRef': data['receiptRef']?.toString(),
      };
    } catch (e) {
      debugPrint('confirmGatewayPayment failed: $e');
    }
    return {'paymentState': 'Paid'};
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
                      // Group bookings pass a long label here ("Group (5
                      // people) (Mike Toledo + 4 guests)"), and so do styles
                      // with long names; without the flex it runs off the edge.
                      Expanded(
                        child: Text(
                          widget.haircutName,
                          style: const TextStyle(color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
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
