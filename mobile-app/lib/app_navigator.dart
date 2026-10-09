import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// App-wide messenger, for messages that must outlive the page that sends them.
///
/// A SnackBar belongs to the nearest ScaffoldMessenger, so one shown just
/// before the page navigates away dies with that page -- the customer saw
/// nothing. That is exactly what happened after paying for previews: the
/// payment screen showed the confirmation and immediately popped itself.
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Shows a message that survives the navigation happening around it.
void showAppMessage(String message, {Duration? duration}) {
  final messenger = rootMessengerKey.currentState;
  if (messenger == null) return;

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 4),
    ),
  );
}
