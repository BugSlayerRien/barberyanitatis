/// Pure auth navigation state machine. No Flutter, no Supabase.
enum AuthArrival {
  none,
  passwordLogin,
  oauthCallback,
  recoveryCallback,
  splashRestore,
}

enum AuthDestination {
  stay,
  dashboard,
  changePassword,
}

class AuthFlowSnapshot {
  const AuthFlowSnapshot({
    this.signedOutIdle = false,
    this.expectingOAuth = false,
    this.recoveryPending = false,
    this.recoveryActive = false,
    this.didNavigate = false,
    this.onRecoveryRoute = false,
  });

  final bool signedOutIdle;
  final bool expectingOAuth;
  final bool recoveryPending;
  final bool recoveryActive;
  final bool didNavigate;
  final bool onRecoveryRoute;

  AuthFlowSnapshot copyWith({
    bool? signedOutIdle,
    bool? expectingOAuth,
    bool? recoveryPending,
    bool? recoveryActive,
    bool? didNavigate,
    bool? onRecoveryRoute,
  }) {
    return AuthFlowSnapshot(
      signedOutIdle: signedOutIdle ?? this.signedOutIdle,
      expectingOAuth: expectingOAuth ?? this.expectingOAuth,
      recoveryPending: recoveryPending ?? this.recoveryPending,
      recoveryActive: recoveryActive ?? this.recoveryActive,
      didNavigate: didNavigate ?? this.didNavigate,
      onRecoveryRoute: onRecoveryRoute ?? this.onRecoveryRoute,
    );
  }
}

class AuthFlowEngine {
  AuthFlowSnapshot state = const AuthFlowSnapshot();

  void markSignedOut() {
    state = const AuthFlowSnapshot(signedOutIdle: true);
  }

  void markExpectingOAuth() {
    state = state.copyWith(expectingOAuth: true, signedOutIdle: false);
  }

  void markRecoveryRequested() {
    state = state.copyWith(recoveryPending: true, signedOutIdle: false);
  }

  void markRecoveryActive() {
    state = state.copyWith(
      recoveryActive: true,
      recoveryPending: true,
      signedOutIdle: false,
    );
  }

  void markRecoveryCompleted() {
    state = state.copyWith(
      recoveryActive: false,
      recoveryPending: false,
      onRecoveryRoute: false,
      didNavigate: false,
    );
  }

  void markPasswordLogin() {
    state = state.copyWith(signedOutIdle: false, expectingOAuth: false);
  }

  void markNavigatedToDashboard() {
    state = state.copyWith(
      didNavigate: true,
      expectingOAuth: false,
      recoveryActive: false,
    );
  }

  void markNavigatedToRecovery() {
    state = state.copyWith(
      didNavigate: true,
      onRecoveryRoute: true,
      recoveryActive: true,
      expectingOAuth: false,
    );
  }

  static bool uriLooksLikeRecovery({
    required Map<String, String> query,
    required Map<String, String> fragment,
  }) {
    final type = (query['type'] ?? fragment['type'] ?? '').toLowerCase();
    return type == 'recovery';
  }

  /// Recovery wins over signedIn. Typing/resume/token refresh never navigate.
  AuthDestination decide({
    required String event,
    required AuthArrival arrival,
    required bool sessionIsRecovery,
    required bool redirectTypeRecovery,
    required bool hasSession,
    required bool hasUserId,
  }) {
    if (event == 'signedOut') {
      return AuthDestination.stay;
    }

    final recoverySignal = event == 'passwordRecovery' ||
        redirectTypeRecovery ||
        (sessionIsRecovery &&
            arrival != AuthArrival.none &&
            arrival != AuthArrival.passwordLogin) ||
        (state.recoveryPending &&
            !state.expectingOAuth &&
            arrival == AuthArrival.recoveryCallback &&
            (sessionIsRecovery || redirectTypeRecovery));

    if (recoverySignal && arrival != AuthArrival.passwordLogin) {
      return AuthDestination.changePassword;
    }

    if (event == 'tokenRefreshed' ||
        event == 'initialSession' ||
        event == 'userUpdated') {
      return AuthDestination.stay;
    }

    if (state.didNavigate &&
        !state.onRecoveryRoute &&
        arrival != AuthArrival.recoveryCallback) {
      return AuthDestination.stay;
    }

    if (arrival == AuthArrival.none) {
      return AuthDestination.stay;
    }

    if (state.signedOutIdle &&
        arrival != AuthArrival.passwordLogin &&
        arrival != AuthArrival.oauthCallback &&
        arrival != AuthArrival.recoveryCallback) {
      return AuthDestination.stay;
    }

    if (arrival == AuthArrival.recoveryCallback) {
      return AuthDestination.stay;
    }

    if (arrival == AuthArrival.oauthCallback ||
        arrival == AuthArrival.passwordLogin ||
        arrival == AuthArrival.splashRestore) {
      if (!hasSession) {
        return AuthDestination.stay;
      }
      if (arrival == AuthArrival.splashRestore && state.signedOutIdle) {
        return AuthDestination.stay;
      }
      if (!hasUserId) {
        return AuthDestination.stay;
      }
      return AuthDestination.dashboard;
    }

    return AuthDestination.stay;
  }

  AuthDestination decideResumeFlush({required bool hasPendingExplicitNavigation}) {
    if (!hasPendingExplicitNavigation) {
      return AuthDestination.stay;
    }
    if (state.recoveryActive || state.onRecoveryRoute) {
      return AuthDestination.changePassword;
    }
    return AuthDestination.dashboard;
  }
}
