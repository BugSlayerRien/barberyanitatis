import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'api_config.dart';
import 'customer_api.dart';
import 'payment_return_guard.dart';
import 'services/face_scan_service.dart';
import 'user_session.dart';

/// One-time "buy more AI hairstyle previews" purchase.
///
/// Deliberately modeled on payment_page.dart's existing GCash flow — same
/// redirect-source creation, external-browser checkout, and in-page polling —
/// rather than a new payment implementation, so this reuses PayMongo mechanics
/// (source-to-payment conversion, status polling) that are already proven
/// there instead of re-deriving them.
///
/// Unlike a booking payment, there is no separate "confirm" step: once
/// payment-status.php reports the purchase as paid, the server has already
/// credited the account (see api/paymongo/payment-status.php's
/// paymongo_sync_payment_row, generalized for purpose='ai_credits'). This page
/// only needs to poll until that happens, then refresh the quota.
class AiCreditPurchasePage extends StatefulWidget {
  const AiCreditPurchasePage({super.key});

  /// The one bundle currently offered. A single named constant, not a
  /// scattered literal, so the price is a one-line change.
  static const int bundleCredits = 5;
  static const double bundleAmountPhp = 49.00;

  @override
  State<AiCreditPurchasePage> createState() => _AiCreditPurchasePageState();
}

class _AiCreditPurchasePageState extends State<AiCreditPurchasePage> {
  bool _processing = false;
  String? _statusLabel;

  String _paymongoBase() => ApiConfig.baseUrl.replaceAll(RegExp(r'/$'), '');

  String _returnUrl(bool success) {
    final base = _paymongoBase();
    // purpose=ai_credits rides through payment-success.php/failed.php's query
    // forwarding into the deep link, so PaymentResultPage can tell a credit
    // purchase apart from a booking payment in the rare case it does end up
    // handling this return (see PaymentReturnGuard for the normal case).
    return success
        ? '$base/paymongo/payment-success.php?purpose=ai_credits'
        : '$base/paymongo/payment-failed.php?purpose=ai_credits';
  }

  String? _extractCheckoutUrl(Map<String, dynamic> body) {
    return body['checkout_url']?.toString() ??
        body['data']?['attributes']?['redirect']?['checkout_url']?.toString() ??
        body['raw']?['data']?['attributes']?['redirect']?['checkout_url']?.toString();
  }

  Future<void> _buy() async {
    if (_processing) return;
    final userId = UserSession.userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in again to buy more previews.')),
      );
      return;
    }

    setState(() {
      _processing = true;
      _statusLabel = null;
    });
    try {
      final cents = (AiCreditPurchasePage.bundleAmountPhp * 100).round();
      final createResponse = await http
          .post(
            Uri.parse('${_paymongoBase()}/paymongo/create-payment.php'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'amount': cents,
              'currency': 'PHP',
              'method': 'gcash',
              'purpose': 'ai_credits',
              'user_id': userId,
              'credits': AiCreditPurchasePage.bundleCredits,
              'description': '${AiCreditPurchasePage.bundleCredits} extra AI hairstyle previews',
              'success_url': _returnUrl(true),
              'failed_url': _returnUrl(false),
            }),
          )
          .timeout(CustomerApi.defaultTimeout);
      if (!mounted) return;

      final data = CustomerApi.decodeJsonObject(createResponse);
      final resourceId = data['resource_id']?.toString() ?? '';
      final resourceType = data['resource_type']?.toString() ?? 'source';
      final checkoutUrl = _extractCheckoutUrl(data);

      if (resourceId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start the purchase. Please try again.')),
        );
        return;
      }

      setState(() => _statusLabel = 'Waiting for GCash confirmation...');

      // Active for the whole trip out to GCash and back: this page's own poll
      // below is what actually credits the account (via payment-status.php),
      // so the app-wide deep-link listener in main.dart should not also push
      // a second, independent verifier for the same return. See
      // PaymentReturnGuard.
      PaymentReturnGuard.enter();
      bool paid;
      try {
        if (checkoutUrl != null && checkoutUrl.isNotEmpty) {
          final uri = Uri.tryParse(checkoutUrl);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
          if (!mounted) return;
          setState(() => _statusLabel = 'Complete payment in the opened app, then return here.');
        }

        paid = await _pollUntilFinal(resourceId, resourceType: resourceType);
      } finally {
        PaymentReturnGuard.exit();
      }
      if (!mounted) return;

      if (!paid) {
        setState(() => _statusLabel = 'Payment not completed. You can try again.');
        return;
      }

      setState(() => _statusLabel = 'Payment received — crediting your account...');
      final quota = await FaceScanService.fetchQuotaStatus(userId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('+${AiCreditPurchasePage.bundleCredits} previews added to your account.'),
        ),
      );
      Navigator.of(context).pop(quota);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  /// True once the gateway reports the payment as paid/succeeded. Matches
  /// payment_page.dart's own status field and polling cadence exactly — same
  /// endpoint, same response shape for both 'source' and 'payment_intent'.
  Future<bool> _pollUntilFinal(String id, {required String resourceType}) async {
    final normalizedType = resourceType.toLowerCase();
    final base = _paymongoBase();
    for (var attempt = 0; attempt < 24; attempt++) {
      try {
        final uri = Uri.parse(
          '$base/paymongo/payment-status.php?intent_id=$id&resource_type=$normalizedType',
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) {
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        final data = CustomerApi.decodeJsonObject(response);
        final status =
            data['data']?['attributes']?['status']?.toString().toLowerCase() ?? '';

        if (status == 'paid' || status == 'succeeded') {
          return true;
        }
        if (status == 'failed' || status == 'canceled' || status == 'expired') {
          return false;
        }
        if (normalizedType == 'source' &&
            (status == 'chargeable' || status == 'pending') &&
            mounted) {
          setState(() => _statusLabel = 'Payment authorized. Finalizing...');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Get more previews', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '+${AiCreditPurchasePage.bundleCredits} AI hairstyle previews',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Try more hairstyles beyond your free previews. These never expire.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '₱${AiCreditPurchasePage.bundleAmountPhp.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (_statusLabel != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(_statusLabel!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.qr_code_2, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text('Pay with GCash', style: TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _processing ? null : _buy,
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
                    : Text(
                        'Buy for ₱${AiCreditPurchasePage.bundleAmountPhp.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
