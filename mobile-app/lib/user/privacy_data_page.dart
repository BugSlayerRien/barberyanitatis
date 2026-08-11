import 'package:flutter/material.dart';

import 'faq_library_page.dart';

class PrivacyDataPage extends StatelessWidget {
  const PrivacyDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Privacy & Data',
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
            'How Tati\'s Barbershop uses information in this app',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This summary reflects how the current app and shop systems work. It is not a full legal privacy policy.',
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _card(
            title: 'Account information',
            body:
                'Your account may store details you provide such as name, email, phone number, gender preference, hair texture preference, and profile photo. These are used to identify you in the app, personalize recommendations, and manage your bookings.',
          ),
          _card(
            title: 'Appointments and bookings',
            body:
                'Appointment and booking information (barber, service, date, time, and status) is stored so you and the shop can manage schedules, payments, cancellations, and reschedules.',
          ),
          _card(
            title: 'Face scan and captured images',
            body:
                'When you use AI Face Scan, photos you capture (for example front and side views) may be processed to estimate face shape and hair characteristics. That analysis helps power hairstyle recommendations and AI previews in the app.',
          ),
          _card(
            title: 'AI hairstyle previews',
            body:
                'AI-generated hairstyle previews are created from your scan and a chosen style so you can see a visual mockup before booking. Previews are tied to your scan session and style selection in the app. Generation may use the shop\'s configured AI services.',
          ),
          _card(
            title: 'What to avoid uploading',
            body:
                'Only upload photos and profile details needed for booking and styling features. Avoid sharing unnecessary sensitive documents, IDs, payment card numbers in free-text fields, or personal information that is not required for your haircut experience.',
          ),
          _card(
            title: 'Help with your data',
            body:
                'For questions about your account information or bookings, use Help & FAQ in Settings, ask through the in-app chatbot, or speak with shop staff at the front desk. Staff can help with account and appointment questions for this shop.',
          ),
          const SizedBox(height: 8),
          Material(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FaqLibraryPage()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.chat_bubble_outline, color: Color(0xFFA99941)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Open Help & FAQ',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Ask about bookings, scans, payments, and more',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white38),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _card({required String title, required String body}) {
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
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
