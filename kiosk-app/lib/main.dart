import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const KioskApp());
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tatis Kiosk',
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'CenturyGothic',
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const WelcomeScreen(),
    );
  }
}
