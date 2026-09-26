import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/payment_return_guard.dart';

/// Pins the rules that stop main.dart's deep-link listener from pushing a
/// second, independent PaymentResultPage on top of a payment a page has
/// already resolved -- the bug where a customer saw "+5 previews added" and
/// was then stranded on "Verifying your payment..." forever.
void main() {
  setUp(PaymentReturnGuard.resetForTest);

  group('while a poll is running', () {
    test('inactive with no pollers entered', () {
      expect(PaymentReturnGuard.isPollerActive, isFalse);
      expect(PaymentReturnGuard.shouldSkipDeepLink({}), isFalse);
    });

    test('a deep link is skipped while a poller is active', () {
      PaymentReturnGuard.enter();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      expect(PaymentReturnGuard.shouldSkipDeepLink({}), isTrue);
    });

    test('stays active until every entrant has exited', () {
      PaymentReturnGuard.enter();
      PaymentReturnGuard.enter();
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
    });

    test('an extra exit() does not go negative or throw', () {
      PaymentReturnGuard.exit();
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.isPollerActive, isFalse);
      PaymentReturnGuard.enter();
      expect(PaymentReturnGuard.isPollerActive, isTrue);
    });
  });

  group('after the poll has already resolved', () {
    // The actual defect: the in-app poll talks to the server directly and
    // usually finishes BEFORE the OS delivers the deep link, so a guard that
    // only covered the poll's lifetime was already open by the time the link
    // arrived.
    test('a late deep link for the same payment is still skipped', () {
      PaymentReturnGuard.enter();
      PaymentReturnGuard.markHandled('src_abc123');
      PaymentReturnGuard.exit();

      expect(PaymentReturnGuard.isPollerActive, isFalse);
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_abc123'}),
        isTrue,
      );
    });

    test('matches the id under any of the parameter names PayMongo uses', () {
      PaymentReturnGuard.markHandled('src_abc123');
      for (final key in ['source', 'source_id', 'id', 'resource_id']) {
        expect(
          PaymentReturnGuard.shouldSkipDeepLink({key: 'src_abc123'}),
          isTrue,
          reason: 'should match on "$key"',
        );
      }
    });

    test('a link carrying no id is skipped on timing alone', () {
      // payment-success.php forwards params, but a return with none at all
      // must still not strand the customer behind a second verifier.
      PaymentReturnGuard.enter();
      PaymentReturnGuard.exit();
      expect(PaymentReturnGuard.shouldSkipDeepLink({}), isTrue);
    });

    test('markHandled ignores empty and whitespace ids', () {
      PaymentReturnGuard.markHandled('');
      PaymentReturnGuard.markHandled('   ');
      PaymentReturnGuard.markHandled(null);
      // Nothing was recorded, and no poll ran, so an unrelated return is not
      // suppressed.
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_other'}),
        isFalse,
      );
    });
  });

  group('poll gave up before the gateway answered', () {
    test('a late deep link is NOT suppressed after a timed-out poll', () {
      // Customer stayed in GCash longer than the in-app poll lasted. Nothing
      // was handled, so PaymentResultPage must take the return.
      PaymentReturnGuard.enter();
      PaymentReturnGuard.exit(resolved: false);
      expect(PaymentReturnGuard.shouldSkipDeepLink({}), isFalse);
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_slow'}),
        isFalse,
      );
    });
  });

  group('a link suppressed mid-poll is not lost', () {
    test('the link is kept while a poll is running', () {
      PaymentReturnGuard.enter();
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_held'}),
        isTrue,
      );
      // The poll gives up: whoever was waiting can replay the return instead
      // of the customer being told the payment did not complete.
      PaymentReturnGuard.exit(resolved: false);
      final held = PaymentReturnGuard.takeSuppressedLink();
      expect(held, isNotNull);
      expect(held!['source'], 'src_held');
    });

    test('taking it twice yields nothing the second time', () {
      PaymentReturnGuard.enter();
      PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_once'});
      PaymentReturnGuard.exit(resolved: false);
      expect(PaymentReturnGuard.takeSuppressedLink(), isNotNull);
      expect(PaymentReturnGuard.takeSuppressedLink(), isNull);
    });

    test('nothing is held when no link arrived', () {
      PaymentReturnGuard.enter();
      PaymentReturnGuard.exit(resolved: false);
      expect(PaymentReturnGuard.takeSuppressedLink(), isNull);
    });
  });

  group('cold start', () {
    test('a deep-link-only return is NOT suppressed', () {
      // App killed mid-payment and relaunched: no poll ran in this process, so
      // PaymentResultPage is the only thing that can resolve the payment and
      // must be allowed through.
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_zzz999'}),
        isFalse,
      );
    });

    test('a different payment than the one handled is not suppressed', () {
      PaymentReturnGuard.markHandled('src_abc123');
      // No poll ran for this one, and the grace window is not open, so it has
      // to be handled by PaymentResultPage.
      expect(
        PaymentReturnGuard.shouldSkipDeepLink({'source': 'src_different'}),
        isFalse,
      );
    });
  });
}
