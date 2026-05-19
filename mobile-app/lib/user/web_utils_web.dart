// Web implementation using dart:html
import 'dart:html' as html;

void clearUrlFragment() {
  try {
    final loc = html.window.location;
    // Strip OAuth query (?code=) and hash (#access_token=) after session is stored.
    html.window.history.replaceState(null, '', '${loc.origin}${loc.pathname}');
  } catch (_) {
    // ignore errors
  }
}
