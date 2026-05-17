import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigator.dart';
import '../user/auth_bootstrap.dart';
import '../user/payment_result_page.dart';
import '../user/scanner/overlay_asset_cache.dart';
import 'kiosk_home_page.dart';
import 'kiosk_theme.dart';

/// Boots the walk-in kiosk shell (shared with standalone `kiosk/` project).
Future<void> runKioskApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    setUrlStrategy(PathUrlStrategy());
  }

  await Supabase.initialize(
    url: 'https://sergfnujsutcschocuuz.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcmdmbnVqc3V0Y3NjaG9jdXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxODM3NzQsImV4cCI6MjA4OTc1OTc3NH0.tr2aFcXaKYt5LwvWp48VRAi-IS2nI1bur_CnRd7OHCg',
    authCallbackUrlHostname: 'login-callback',
  );

  await AuthBootstrap.initialize();
  unawaited(OverlayAssetCache.preload());

  runApp(const KioskApp());
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.dark().textTheme.apply(fontFamily: 'CenturyGothic');
    return MaterialApp(
      title: 'Tatis Walk-In Kiosk',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: KioskColors.background,
        fontFamily: 'CenturyGothic',
        textTheme: baseTextTheme.copyWith(
          titleSmall: GoogleFonts.montserrat(textStyle: baseTextTheme.titleSmall),
          titleMedium: GoogleFonts.montserrat(textStyle: baseTextTheme.titleMedium),
          titleLarge: GoogleFonts.montserrat(textStyle: baseTextTheme.titleLarge),
        ),
      ),
      home: const KioskHomePage(),
      routes: {
        '/payment-result': (context) => const PaymentResultPage(),
      },
    );
  }
}
