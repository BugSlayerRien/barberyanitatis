import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/auth_flow_state.dart';

void main() {
  late AuthFlowEngine engine;

  setUp(() {
    engine = AuthFlowEngine();
  });

  test('token refresh and initialSession never navigate', () {
    engine.markExpectingOAuth();
    expect(
      engine.decide(
        event: 'tokenRefreshed',
        arrival: AuthArrival.none,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.stay,
    );
    expect(
      engine.decide(
        event: 'initialSession',
        arrival: AuthArrival.splashRestore,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.stay,
    );
  });

  test('resume without pending explicit navigation stays', () {
    engine.markSignedOut();
    expect(
      engine.decideResumeFlush(hasPendingExplicitNavigation: false),
      AuthDestination.stay,
    );
  });

  test('stale session after logout does not open dashboard', () {
    engine.markSignedOut();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.none,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: false,
      ),
      AuthDestination.stay,
    );
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.splashRestore,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.stay,
    );
  });

  test('recovery pending plus leftover session is not Change Password', () {
    engine.markRecoveryRequested();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.splashRestore,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.none,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.stay,
    );
  });

  test('recovery callback without recovery session signals stays', () {
    engine.markRecoveryRequested();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.recoveryCallback,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.stay,
    );
  });

  test('password login with userId goes to dashboard', () {
    engine.markPasswordLogin();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.passwordLogin,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
  });

  test('oauth callback without userId stays until bootstrap', () {
    engine.markExpectingOAuth();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.oauthCallback,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: false,
      ),
      AuthDestination.stay,
    );
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.oauthCallback,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
  });

  test('recovery pending does not hijack a later Google login', () {
    engine.markRecoveryRequested();
    engine.markExpectingOAuth();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.oauthCallback,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
  });

  test('recovery takes priority over signedIn', () {
    engine.markRecoveryRequested();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.recoveryCallback,
        sessionIsRecovery: true,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.changePassword,
    );
    expect(
      engine.decide(
        event: 'passwordRecovery',
        arrival: AuthArrival.recoveryCallback,
        sessionIsRecovery: true,
        redirectTypeRecovery: true,
        hasSession: true,
        hasUserId: false,
      ),
      AuthDestination.changePassword,
    );
  });

  test('normal oauth is not treated as recovery', () {
    engine.markExpectingOAuth();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.oauthCallback,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
  });

  test('logout resets flags so typing cannot navigate', () {
    engine.markExpectingOAuth();
    engine.markNavigatedToDashboard();
    engine.markSignedOut();
    expect(engine.state.signedOutIdle, isTrue);
    expect(engine.state.expectingOAuth, isFalse);
    expect(engine.state.didNavigate, isFalse);
    expect(
      engine.decideResumeFlush(hasPendingExplicitNavigation: false),
      AuthDestination.stay,
    );
  });

  test('recovery completed allows later dashboard login', () {
    engine.markRecoveryActive();
    engine.markNavigatedToRecovery();
    engine.markRecoveryCompleted();
    engine.markPasswordLogin();
    expect(
      engine.decide(
        event: 'signedIn',
        arrival: AuthArrival.passwordLogin,
        sessionIsRecovery: false,
        redirectTypeRecovery: false,
        hasSession: true,
        hasUserId: true,
      ),
      AuthDestination.dashboard,
    );
  });

  test('uri type=recovery is detected', () {
    expect(
      AuthFlowEngine.uriLooksLikeRecovery(
        query: const {'type': 'recovery', 'code': 'abc'},
        fragment: const {},
      ),
      isTrue,
    );
    expect(
      AuthFlowEngine.uriLooksLikeRecovery(
        query: const {'code': 'abc'},
        fragment: const {},
      ),
      isFalse,
    );
  });
}
