import 'package:flutter/material.dart';

import 'app_brand.dart';
import 'auth_page.dart';

/// Shown when staff/admin/receptionist sign in on mobile — those roles use the web portal only.
class StaffWebPortalPage extends StatelessWidget {
  const StaffWebPortalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandWordmark(logoHeight: 88),
              const SizedBox(height: 28),
              const Text(
                'Use the Web Portal',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Admin and receptionist accounts are only available in the operations web portal, not in this customer/barber mobile app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              const Text(
                'Open in your browser:\nweb-admin/login.html',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppBrand.gold, fontSize: 13),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                    (route) => false,
                  );
                },
                style: AppBrand.primaryButton,
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
