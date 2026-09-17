import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/payment_return_guard.dart';

/// Pins the counter semantics that let the deep-link listener in main.dart
/// know whether a page (PaymentPage / AiCreditPurchasePage) is already
/// polling for the same PayMongo return, so it can skip pushing a redundant
/// (and, for ai_credits, non-functional) PaymentResultPage on top of it.
void main() {
  group('PaymentReturnGuard', () {
    test('inactive with no pollers entered', () {
      expect(PaymentReturnGuard.isPollerActive, isFalse);
    });

    test('active while a poller has entered', () {
      PaymentReturnGuard.enter();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
    });

    test('stays active until every entrant has exited', () {
      // Guards the case this was written for: a second payment flow starting
      // before the first has fully unwound should not let the deep-link
      // listener fire early.
      PaymentReturnGuard.enter();
      PaymentReturnGuard.enter();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
    });

    test('an extra exit() does not go negative or throw', () {
      PaymentReturnGuard.exit();
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
      // Confirms the count floored at 0 rather than going negative, which
      // would otherwise require two exits to cancel out one real enter().
      PaymentReturnGuard.enter();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
    });
  });
}
