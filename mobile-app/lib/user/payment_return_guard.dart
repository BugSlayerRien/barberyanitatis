/// Coordinates the PayMongo return deep link (`tatisapp://payment-return`)
/// with whichever page actually started the payment.
///
/// Both [PaymentPage] (booking) and [AiCreditPurchasePage] (AI-generation
/// top-up) already poll `paymongo/payment-status.php` themselves the moment
/// the customer returns to the app foreground -- that poll is what reliably
/// resolves and navigates onward (it is what produced "Payment successful" /
/// "+5 previews added" in practice). The deep link fires independently of
/// that, for the same return, and `main.dart`'s global listener used to push
/// PaymentResultPage unconditionally on top of it.
///
/// PaymentResultPage runs its own, *separate* poll — and
/// `api/paymongo/payment-success.php` / `payment-failed.php` do not forward
/// any query parameters into the deep link, so that second poll never had a
/// resource id to check and sat on "Verifying your payment..." forever, even
/// though the page underneath had already finished successfully. This guard
/// lets the deep-link listener skip the redundant push whenever a page is
/// already handling the same return itself.
class PaymentReturnGuard {
  PaymentReturnGuard._();

  // A counter, not a bool: guards against one poller's `exit()` racing past
  // another's `enter()` if a customer somehow opens a second payment flow
  // before the first one's poll loop has returned.
  static int _activePollers = 0;

  static bool get isPollerActive => _activePollers > 0;

  static void enter() {
    _activePollers++;
  }

  static void exit() {
    if (_activePollers > 0) {
      _activePollers--;
    }
  }
}
