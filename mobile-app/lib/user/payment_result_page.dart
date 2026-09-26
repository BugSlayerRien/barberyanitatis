import 'package:flutter/material.dart';
import 'ai_credit_purchase_page.dart';
import 'appointments_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'api_config.dart';
import 'dashboard_page.dart';
import 'services/face_scan_service.dart';
import 'user_session.dart';

class PaymentResultPage extends StatefulWidget {
  const PaymentResultPage({super.key});

  @override
  State<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends State<PaymentResultPage> {
  bool _isLoading = true;
  String? _paymentStatus;
  String? _errorMessage;
  Map<String, String> _params = {};

  @override
  void initState() {
    super.initState();
    _initializeAndVerify();
  }

  Future<void> _initializeAndVerify() async {
    // Parse route arguments
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _params = args.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } else if (args is Map<String, String>) {
      _params = args;
    }

    // If no resource_id, show helpful error
    final resourceId = _params['source'] ?? _params['id'] ?? _params['resource_id'] ?? '';
    if (resourceId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No payment reference received. This can happen if you manually returned to the app without completing the payment flow. Please return to the payment page and try again.';
        });
      }
      return;
    }

    // Verify payment status
    await _verifyPaymentStatus(resourceId);
  }

  Future<void> _verifyPaymentStatus(String resourceId) async {
    try {
      final paymentRoot = _buildPaymentRoot();
      final resourceType = resourceId.startsWith('src_') ? 'source' : 'payment_intent';

      // Poll payment status up to 20 times (20 seconds total)
      for (var i = 0; i < 20; i++) {
        try {
          final uri = Uri.parse(
            '$paymentRoot/paymongo/payment-status.php?intent_id=$resourceId&resource_type=$resourceType',
          );
          final response = await http.get(uri).timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final status = data['data']?['attributes']?['status']?.toString().toLowerCase() ?? 'unknown';

            debugPrint('Payment status poll $i: $status');

            if (status == 'paid' || status == 'succeeded') {
              // Payment successful
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _paymentStatus = 'Paid';
                });
              }
              // Wait longer to ensure backend has processed payment and updated database
              await Future.delayed(const Duration(milliseconds: 1500));
              if (!mounted) return;

              // An AI-credit top-up is not a booking -- api/paymongo/payment-status.php
              // has already credited the account by the time `status` reads
              // paid/succeeded here (see ai_tryon_provider.php's
              // ai_tryon_purchased_credits()), so there is no appointment to
              // show. This branch is reached only if this page ends up
              // handling the return itself -- normally AiCreditPurchasePage's
              // own poll resolves it first; see PaymentReturnGuard.
              if (_params['purpose'] == 'ai_credits') {
                final quota =
                    await FaceScanService.fetchQuotaStatus(userId: UserSession.userId);
                if (quota != null) UserSession.lastQuota = quota;
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Previews added to your account.')),
                );
                // Warm return: the purchase page (and the scan results page
                // under it) are still on the stack -- pop past the purchase
                // page so the customer lands back on their results.
                if (AiCreditPurchasePage.isOpen) {
                  var poppedPurchase = false;
                  Navigator.of(context).popUntil((route) {
                    if (poppedPurchase) return true;
                    if (route.settings.name == AiCreditPurchasePage.routeName) {
                      poppedPurchase = true;
                      return false;
                    }
                    return route.isFirst;
                  });
                  return;
                }
                // Cold start: the scan lives only in memory, so there is no
                // results page to go back to.
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const DashboardPage()),
                  (route) => false,
                );
                return;
              }

              final appointmentId = int.tryParse(
                    _params['appointment_id'] ??
                        _params['appointmentId'] ??
                        '',
                  ) ??
                  0;
              final receiptRef = _params['source'] ??
                  _params['id'] ??
                  _params['resource_id'] ??
                  '';
              // The in-page path says "Payment successful"; this one said
              // nothing at all, so a return handled here looked like nothing
              // had happened.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    receiptRef.isNotEmpty
                        ? 'Payment successful ($receiptRef)'
                        : 'Payment successful.',
                  ),
                ),
              );
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => AppointmentsPage(
                    highlightAppointmentId:
                        appointmentId > 0 ? appointmentId : null,
                    forcedPaymentState: 'Paid',
                    forcedReceiptRef:
                        receiptRef.isNotEmpty ? receiptRef : null,
                  ),
                ),
                (route) => false,
              );
              return;
            } else if (status == 'failed' || status == 'canceled' || status == 'expired') {
              // Payment failed
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Payment was declined, canceled, or expired. Status: $status';
                });
              }
              return;
            }
            // For 'chargeable' or 'pending', continue polling
          } else {
            debugPrint('Payment status check failed: ${response.statusCode} - ${response.body}');
          }
        } catch (pollError) {
          debugPrint('Poll error: $pollError');
          // Continue polling on transient errors
        }

        // Wait before next poll (1 second)
        if (i < 19) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }

      // Timeout after polling
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Payment verification timed out after 20 seconds. The payment may still be processing. Please check your appointment status or try refreshing.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error verifying payment: $e';
        });
      }
    }
  }

  String _buildPaymentRoot() {
    return ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verifying Payment')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Verifying your payment...'),
              const SizedBox(height: 20),
              if (_params.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Reference: ${_params['source'] ?? 'Loading...'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_paymentStatus == 'Paid') {
      return Scaffold(
        appBar: AppBar(title: const Text('Payment Successful')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 72, color: Colors.green),
              const SizedBox(height: 12),
              const Text('Payment Verified', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Reference: ${_params['source'] ?? _params['id'] ?? ''}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    // Error or payment not settled
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Result')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 72, color: Colors.red),
              const SizedBox(height: 12),
              Text(_errorMessage ?? 'Payment could not be verified.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
