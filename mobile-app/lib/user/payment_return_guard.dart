/// Coordinates the PayMongo return deep link (`tatisapp://payment-return`)
/// with whichever page actually started the payment.
///
/// Both [PaymentPage] (booking) and [AiCreditPurchasePage] (AI-generation
/// top-up) poll `paymongo/payment-status.php` themselves while the customer is
/// away paying -- that poll is what resolves the payment and navigates onward
/// (it is what produces "Payment successful" / "+5 previews added"). The deep
/// link fires independently for the same return, and `main.dart`'s global
/// listener would otherwise push PaymentResultPage on top of a page that has
/// already finished.
///
/// PaymentResultPage runs its own, *separate* poll, so that second verification
/// sits on "Verifying your payment..." indefinitely even though the payment
/// succeeded.
///
/// Timing is the whole problem. An earlier version of this guard was active
/// only for the duration of the poll, which is not enough: the poll talks to
/// the server directly and frequently resolves *before* the OS gets around to
/// delivering the deep link, so the link arrived after the guard had already
/// been released. The guard therefore also remembers which payments were
/// resolved in-app, and stays closed briefly after a poll ends.
class PaymentReturnGuard {
  PaymentReturnGuard._();

  /// How long after an in-app poll finishes a deep link is still treated as
  /// belonging to that same return. Covers the gap between the poll resolving
  /// and the OS delivering the link (which happens on app resume, and can lag
  /// by seconds).
  ///
  /// Safe against swallowing a legitimate return: within this window a poll
  /// has just resolved a payment, so the link is a duplicate of it. A genuine
  /// deep-link-only return (app killed mid-payment, relaunched cold) starts
  /// with these statics freshly zeroed, so nothing is suppressed.
  static const Duration _graceAfterResolve = Duration(seconds: 90);

  // A counter, not a bool: guards against one poller's `exit()` racing past
  // another's `enter()` if a customer somehow opens a second payment flow
  // before the first one's poll loop has returned.
  static int _activePollers = 0;

  /// Gateway resource ids (`src_...` / `pi_...`) already resolved in-app.
  static final Set<String> _handledResourceIds = <String>{};

  static DateTime? _lastResolvedAt;

  static bool get isPollerActive => _activePollers > 0;

  static bool get _withinGrace {
    final resolvedAt = _lastResolvedAt;
    if (resolvedAt == null) return false;
    return DateTime.now().difference(resolvedAt) < _graceAfterResolve;
  }

  static void enter() {
    _activePollers++;
  }

  static void exit() {
    if (_activePollers > 0) {
      _activePollers--;
    }
    // Stamped on the way out, so a deep link that lands moments later is still
    // recognised as this return rather than a new one.
    _lastResolvedAt = DateTime.now();
  }

  /// Records that this specific payment was resolved by an in-app poll, so the
  /// matching deep link can be identified exactly rather than by timing alone.
  static void markHandled(String? resourceId) {
    final id = resourceId?.trim() ?? '';
    if (id.isEmpty) return;
    _handledResourceIds.add(id);
  }

  /// Whether `main.dart` should ignore this return because a page already
  /// handled it.
  ///
  /// [params] are the deep link's query parameters;
  /// `api/paymongo/payment-success.php` forwards the gateway's own fields
  /// through, so a resource id is usually present.
  static bool shouldSkipDeepLink(Map<String, String> params) {
    if (isPollerActive) return true;

    final id = (params['source'] ??
            params['source_id'] ??
            params['id'] ??
            params['resource_id'] ??
            '')
        .trim();
    if (id.isNotEmpty && _handledResourceIds.contains(id)) return true;

    // No id to match on (or an id this app never saw): fall back to timing.
    return _withinGrace;
  }

  /// Test seam. Production code never needs this -- the statics reset with the
  /// process, which is what makes a cold-start return work.
  static void resetForTest() {
    _activePollers = 0;
    _handledResourceIds.clear();
    _lastResolvedAt = null;
  }
}
