// Web implementation using dart:html
import 'dart:html' as html;

void clearUrlFragment() {
  try {
    final loc = html.window.location;
    final newUrl = '${loc.origin}${loc.pathname}${loc.search}';
    html.window.history.replaceState(null, '', newUrl);
  } catch (_) {
    // ignore errors
  }
}
