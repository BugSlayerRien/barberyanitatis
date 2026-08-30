String authFriendlyError(Object error) {
  final raw = error.toString().replaceFirst('Exception:', '').trim();
  final lower = raw.toLowerCase();

  if (lower.contains('over_email_send_rate_limit') ||
      lower.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('email rate')) {
    return 'Too many emails were sent from this app. Please wait a few minutes and try again.';
  }

  if (lower.contains('user already registered') ||
      lower.contains('already registered') ||
      lower.contains('already been registered') ||
      lower.contains('email_exists') ||
      lower.contains('user_already_exists')) {
    return 'This email is already registered. Try signing in instead. If you used Google or Facebook, sign in with that provider, or use Forgot password to set an email password.';
  }

  return raw;
}

bool authLooksLikeInvalidCredentials(Object error) {
  final lower = error.toString().toLowerCase();
  return lower.contains('invalid_grant') ||
      lower.contains('invalid login credentials') ||
      (lower.contains('invalid') && lower.contains('credentials'));
}

String authOauthOnlySignInMessage(List<String> providers) {
  final labels = <String>[];
  for (final provider in providers) {
    final p = provider.toLowerCase();
    if (p == 'google') {
      labels.add('Google');
    } else if (p == 'facebook') {
      labels.add('Facebook');
    }
  }
  if (labels.isEmpty) {
    return 'This email is already used with Google or Facebook. Sign in with that provider, or use Forgot password to set an email password.';
  }
  final joined = labels.join(' or ');
  return 'This email is already used with $joined. Sign in with $joined, or use Forgot password to set an email password.';
}
