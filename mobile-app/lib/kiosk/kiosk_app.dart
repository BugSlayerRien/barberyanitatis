import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigator.dart';
import '../app_orientation.dart';
import '../user/api_config.dart';
import '../user/auth_bootstrap.dart';
import '../user/payment_result_page.dart';
import '../user/scanner/overlay_asset_cache.dart';
import 'kiosk_home_page.dart';
import 'kiosk_theme.dart';

/// Boots the walk-in kiosk shell (shared with standalone `kiosk/` project).
Future<void> runKioskApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppOrientation.lockForKiosk();
  await ApiConfig.ensureInitialized();
  if (kIsWeb) {
    setUrlStrategy(PathUrlStrategy());
  }

  await Supabase.initialize(
    url: 'https://sergfnujsutcschocuuz.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlcmdmbnVqc3V0Y3NjaG9jdXV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQxODM3NzQsImV4cCI6MjA4OTc1OTc3NH0.tr2aFcXaKYt5LwvWp48VRAi-IS2nI1bur_CnRd7OHCg',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  await AuthBootstrap.initialize();
  unawaited(OverlayAssetCache.preload());

  runApp(const KioskApp());
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark();
    final centuryTextTheme =
        base.textTheme.apply(fontFamily: 'CenturyGothic');
    final centuryPrimaryTextTheme =
        base.primaryTextTheme.apply(fontFamily: 'CenturyGothic');
    return MaterialApp(
      title: 'Barberya ni Tatis',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: KioskColors.background,
        colorScheme: const ColorScheme.dark(
          primary: KioskColors.gold,
          onPrimary: Colors.black,
          surface: KioskColors.panel,
          onSurface: KioskColors.textPrimary,
        ),
        fontFamily: 'CenturyGothic',
        textTheme: centuryTextTheme,
        primaryTextTheme: centuryPrimaryTextTheme,
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: KioskColors.background,
          titleTextStyle: centuryTextTheme.titleLarge,
          toolbarTextStyle: centuryTextTheme.bodyMedium,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: KioskColors.gold,
        ),
        dividerTheme: const DividerThemeData(color: KioskColors.border),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: KioskColors.gold,
            textStyle: const TextStyle(fontFamily: 'CenturyGothic'),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(
              fontFamily: 'CenturyGothic',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            textStyle: const TextStyle(
              fontFamily: 'CenturyGothic',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      builder: (context, child) {
        return DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'CenturyGothic'),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const KioskHomePage(),
      routes: {
        '/payment-result': (context) => const PaymentResultPage(),
      },
    );
  }
}
