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
  Timer? _routeTimer;
  bool _completingOAuth = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb && AuthBootstrap.isSupabaseAuthCallbackUri(Uri.base)) {
      _completingOAuth = true;
      _statusMessage = 'Completing sign-in...';
      unawaited(_routeNext());
    } else {
      _routeTimer = Timer(const Duration(milliseconds: 400), _routeNext);
    }
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    super.dispose();
  }

  Future<void> _routeNext() async {
    if (!mounted) {
      return;
    }

    if (kIsWeb && AuthBootstrap.isSupabaseAuthCallbackUri(Uri.base)) {
      setState(() {
        _completingOAuth = true;
        _statusMessage = 'Completing sign-in...';
      });
    }

    for (var i = 0; i < 25; i++) {
      if (AuthBootstrap.didNavigateAfterSignIn) {
        return;
      }
      if (AuthBootstrap.isHandlingAuthCallback ||
          AuthBootstrap.passwordRecoveryActive) {
        if (mounted && !_completingOAuth) {
          setState(() {
            _completingOAuth = true;
            _statusMessage = AuthBootstrap.passwordRecoveryActive
                ? 'Opening password reset...'
                : 'Completing sign-in...';
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }
      break;
    }

    final restored = await AuthBootstrap.restoreSessionOnColdStart();
    if (!mounted || restored || AuthBootstrap.didNavigateAfterSignIn) {
      return;
    }

    if (kIsWeb && AuthBootstrap.isSupabaseAuthCallbackUri(Uri.base)) {
      setState(() {
        _statusMessage =
            'Sign-in callback received but session was not restored. In Supabase → Auth → URL: set Site URL to your Flutter origin (e.g. http://localhost — or match the address bar), not the .supabase.co URL. Add redirect: ${AuthRedirect.oauthCallbackPageBaseUri}** and http://localhost:*';
      });
      await Future<void>.delayed(const Duration(seconds: 2));
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
            if (_completingOAuth) ...[
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
