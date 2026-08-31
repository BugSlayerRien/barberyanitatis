import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_brand.dart';
import 'auth_bootstrap.dart';
import 'auth_page.dart';
import 'auth_redirect.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _busy = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    unawaited(_routeNext());
  }

  Future<void> _routeNext() async {
    if (!mounted) {
      return;
    }

    final callback = kIsWeb && AuthBootstrap.isSupabaseAuthCallbackUri(Uri.base);
    if (callback || AuthBootstrap.isHandlingAuthCallback || AuthBootstrap.passwordRecoveryActive) {
      setState(() {
        _busy = true;
        _statusMessage = AuthBootstrap.passwordRecoveryActive
            ? 'Opening password reset...'
            : 'Completing sign-in...';
      });
    }

    while (AuthBootstrap.isHandlingAuthCallback && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    if (!mounted || AuthBootstrap.didNavigateAfterSignIn) {
      return;
    }

    bool restored = false;
    try {
      restored = await AuthBootstrap.restoreSessionOnColdStart();
    } catch (_) {
      restored = false;
    }
    if (!mounted || restored || AuthBootstrap.didNavigateAfterSignIn) {
      return;
    }

    if (callback) {
      setState(() {
        _busy = true;
        _statusMessage =
            'Sign-in callback received but session was not restored. In Supabase → Auth → URL: set Site URL to your Flutter origin (e.g. http://localhost — or match the address bar), not the .supabase.co URL. Add redirect: ${AuthRedirect.oauthCallbackPageBaseUri}** and http://localhost:*';
      });
      return;
    }

    if (!mounted || AuthBootstrap.didNavigateAfterSignIn) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandWordmark(logoHeight: 120, showTagline: true),
            if (_busy) ...[
              const SizedBox(height: 24),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppBrand.gold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _statusMessage.isNotEmpty
                    ? _statusMessage
                    : 'Completing sign-in...',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
