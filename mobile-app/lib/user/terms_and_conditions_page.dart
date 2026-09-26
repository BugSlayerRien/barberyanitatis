import 'package:flutter/material.dart';
import 'app_brand.dart';

/// Full terms shown at sign-up (with an acceptance checkbox in
/// [AuthPage]) and reachable any time after from Settings. Describes how the
/// app actually behaves -- account data, face scan/AI processing, payments,
/// bookings, retention, and kiosk handling -- rather than generic boilerplate.
class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  static const String lastUpdated = 'September 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Terms and Conditions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Tati\'s Barbershop app — Terms and Conditions',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: $lastUpdated. By creating an account or using this app, you agree to the terms below.',
            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _section(
            title: '1. Account and personal data',
            body:
                'Creating an account collects your name, email, and password. You may later add a phone number and profile photo. This information is used to identify you, manage your appointments, and communicate booking updates. You are responsible for keeping your login credentials secure.',
          ),
          _section(
            title: '2. Face scan and AI processing',
            body:
                'The AI Face Scan feature captures front, left, and right photos of your face, once per session. These photos are sent to the app\'s AI service to estimate face shape, hair texture, and hair length, which powers hairstyle recommendations. Captured photos and analysis results are stored so you can review and revisit your scan results, and so the shop\'s barbers can reference them for your appointment.',
          ),
          _section(
            title: '3. AI-generated hairstyle previews',
            body:
                'AI previews are generated images showing how a chosen hairstyle may look on you, based on your scan. These previews are not a guarantee of the exact final result, which depends on your barber\'s execution, hair condition, and growth pattern. Generated previews are not saved to your account unless you explicitly choose to save them; unsaved previews may be discarded. You may delete any preview you saved at any time from the Saved page.',
          ),
          _section(
            title: '4. Free previews and purchased credits',
            body:
                'The app provides a limited number of free AI previews per account. Additional previews can be purchased as one-time credit bundles. Purchased credits do not expire and are not refundable once a preview has been generated using them, except where required by applicable law or at the shop\'s discretion for a verified technical failure.',
          ),
          _section(
            title: '5. Payments',
            body:
                'Payments for appointments and preview credits are processed through GCash via PayMongo, a third-party payment gateway. The app does not store your GCash credentials or full payment card details. Refunds for cancelled or undeliverable services are handled according to the shop\'s cancellation policy and applicable payment gateway rules.',
          ),
          _section(
            title: '6. Appointments, cancellations, and no-shows',
            body:
                'Booking an appointment reserves a time slot with a specific barber. Cancellation and rescheduling are available up to the limits shown in the app. Unpaid appointments not confirmed before their scheduled time may be automatically cancelled. Repeated no-shows may affect your ability to book future appointments.',
          ),
          _section(
            title: '7. Data retention and deletion',
            body:
                'Your face scan photos and the AI previews made from them are deleted automatically 90 days after they are created. The plain description derived from a scan (face shape and hair texture) is kept so recommendations continue to work. Account and appointment records are kept for up to 3 years of inactivity, after which they may be removed. Completed payment records may be retained longer where required for accounting or legal purposes. You may request deletion of your account and associated data at any time by contacting shop staff.',
          ),
          _section(
            title: '8. Kiosk mode (walk-in scans)',
            body:
                'When the AI Face Scan is used in kiosk mode at the shop (without signing in), captured photos and scan results are tied only to that walk-in session, not to a personal account, and are used solely to show hairstyle recommendations during that visit.',
          ),
          _section(
            title: '9. Acceptable use',
            body:
                'You agree not to upload photos of anyone other than yourself without their consent, misuse the booking system (for example, repeated fake bookings), or attempt to interfere with the app\'s normal operation.',
          ),
          _section(
            title: '10. Changes to these terms',
            body:
                'These terms may be updated from time to time to reflect changes in how the app or shop operates. Continued use of the app after an update constitutes acceptance of the revised terms. Material changes will be highlighted in the app where practical.',
          ),
          _section(
            title: '11. Contact',
            body:
                'Questions about these terms, your data, or your account can be directed to shop staff at the front desk or through Help & FAQ in Settings.',
          ),
        ],
      ),
    );
  }

  static Widget _section({required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: AppBrand.accent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
