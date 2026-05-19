import 'dart:html' as html;

/// `window.location.origin` — always matches the tab’s host **and port** (any Flutter web port).
String currentBrowserOrigin() {
  try {
    return html.window.location.origin;
  } catch (_) {
    return '';
  }
}
