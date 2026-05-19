import 'dart:html' as html;

/// Persists the running app origin so [oauth-callback.html] can return on any port.
void saveOAuthReturnTo(String returnTo) {
  try {
    html.window.sessionStorage['tatis_oauth_return_to'] = returnTo;
  } catch (_) {}
}
