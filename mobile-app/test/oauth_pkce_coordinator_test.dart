import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/oauth_pkce_coordinator.dart';

void main() {
  tearDown(OAuthPkceCoordinator.clearOnLogout);

  test('attempt id is parsed from path and query', () {
    final withBoth = Uri.parse(
      'io.supabase.flutter://login-callback/oauth/abc123?oauth_attempt=abc123&code=x',
    );
    expect(OAuthPkceCoordinator.attemptIdFromUri(withBoth), 'abc123');

    final queryOnly = Uri.parse(
      'io.supabase.flutter://login-callback?code=x&oauth_attempt=def',
    );
    expect(OAuthPkceCoordinator.attemptIdFromUri(queryOnly), 'def');

    final untagged = Uri.parse(
      'io.supabase.flutter://login-callback?code=x',
    );
    expect(OAuthPkceCoordinator.attemptIdFromUri(untagged), isNull);
  });

  test('stale attempt is ignored while a newer oauth is active', () {
    OAuthPkceCoordinator.beginAttempt(attemptId: 'attempt-2', provider: 'google');
    final stale = Uri.parse(
      'io.supabase.flutter://login-callback/oauth/attempt-1?oauth_attempt=attempt-1&code=old',
    );
    expect(
      OAuthPkceCoordinator.dispositionFor(
        uri: stale,
        recoveryIntent: false,
        expectingOAuth: true,
      ),
      OAuthCallbackDisposition.ignoreStale,
    );

    final current = Uri.parse(
      'io.supabase.flutter://login-callback/oauth/attempt-2?oauth_attempt=attempt-2&code=new',
    );
    expect(
      OAuthPkceCoordinator.dispositionFor(
        uri: current,
        recoveryIntent: false,
        expectingOAuth: true,
      ),
      OAuthCallbackDisposition.process,
    );
  });

  test('untagged callback while oauth is active is not processed as current', () {
    OAuthPkceCoordinator.beginAttempt(attemptId: 'attempt-2', provider: 'google');
    final untagged = Uri.parse(
      'io.supabase.flutter://login-callback?code=stale',
    );
    expect(
      OAuthPkceCoordinator.dispositionFor(
        uri: untagged,
        recoveryIntent: false,
        expectingOAuth: true,
      ),
      OAuthCallbackDisposition.untaggedWhileActive,
    );
  });

  test('recovery is processed even while an oauth attempt id exists', () {
    OAuthPkceCoordinator.beginAttempt(attemptId: 'attempt-2', provider: 'google');
    final recovery = Uri.parse(
      'io.supabase.flutter://login-callback?code=rec&type=recovery',
    );
    expect(
      OAuthPkceCoordinator.dispositionFor(
        uri: recovery,
        recoveryIntent: true,
        expectingOAuth: false,
      ),
      OAuthCallbackDisposition.process,
    );
  });

  test('finished auth codes are not retried', () {
    expect(OAuthPkceCoordinator.alreadyFinishedAuthCode('c1'), isFalse);
    OAuthPkceCoordinator.markAuthCodeFinished('c1');
    expect(OAuthPkceCoordinator.alreadyFinishedAuthCode('c1'), isTrue);
    OAuthPkceCoordinator.clearOnLogout();
    expect(OAuthPkceCoordinator.alreadyFinishedAuthCode('c1'), isFalse);
  });
}
