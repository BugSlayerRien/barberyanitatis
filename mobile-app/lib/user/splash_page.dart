import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_bootstrap.dart';
import 'auth_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();
    _routeTimer = Timer(const Duration(milliseconds: 1200), _routeNext);
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

    final restored = await AuthBootstrap.restoreSessionOnColdStart();
    if (!mounted || restored || AuthBootstrap.didNavigateAfterSignIn) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/TATIS.png',
              height: 120,
            ),
            const SizedBox(height: 16),
            const Text(
              'BARBERYA NI TATIS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'AI Hairstyle Recommender',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
