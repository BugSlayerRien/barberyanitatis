import 'package:flutter/material.dart';
import 'app_brand.dart';

import '../barber/barber_edit_profile_page.dart';
import 'change_password_page.dart';
import 'faq_library_page.dart';
import 'privacy_data_page.dart';
import 'profile_page.dart';
import 'session_logout.dart';
import 'terms_and_conditions_page.dart';
import 'user_session.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loggingOut = false;

  Future<void> _confirmLogout() async {
    if (_loggingOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title:
            const Text('Confirm logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Log out',
                style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await SessionLogout.perform(context);
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBarber = UserSession.roles.contains('barber');
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('Account'),
          _settingsTile(
            icon: Icons.person_outline,
            title: 'Edit profile',
            subtitle: isBarber
                ? 'Name, specialty, about you'
                : 'Name, phone, photo, hair texture',
            // Barbers and customers are separate accounts in separate
            // tables. Sending a barber to the customer profile screen
            // made the API reject them outright.
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => isBarber
                      ? const BarberEditProfilePage()
                      : const ProfilePage(),
                ),
              );
            },
          ),
          _settingsTile(
            icon: Icons.lock_outline,
            title: 'Change password',
            subtitle: 'Update your account password',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
              );
            },
          ),
          _settingsTile(
            icon: Icons.info_outline,
            title: 'Signed in as',
            subtitle: UserSession.email?.isNotEmpty == true
                ? UserSession.email!
                : 'Customer account',
            onTap: null,
          ),
          // The Notifications section is hidden until reminders are
          // actually sent. A switch that changes nothing is worse than
          // no switch: it tells the customer they will be reminded.
          // The stored preference is left alone so flipping this back on
          // restores whatever they last chose.
          const SizedBox(height: 20),
          _sectionTitle('AI & Data'),
          _settingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & Data',
            subtitle: 'How account, booking, and scan data are used',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyDataPage()),
              );
            },
          ),
          _settingsTile(
            icon: Icons.description_outlined,
            title: 'Terms and Conditions',
            subtitle: 'The terms you agreed to when you signed up',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const TermsAndConditionsPage()),
              );
            },
          ),
          _settingsTile(
            icon: Icons.refresh,
            title: 'Reset scan preferences',
            subtitle: 'Clears saved hairstyle scan session data',
            onTap: () async {
              UserSession.resetScanState();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Scan preferences cleared. Library compatibility badges are hidden until your next successful scan.',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          _sectionTitle('Support'),
          _settingsTile(
            icon: Icons.help_outline,
            title: 'Help & FAQ',
            subtitle: 'Booking, payments, AI scan, account help',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FaqLibraryPage()),
              );
            },
          ),
          const SizedBox(height: 20),
          _sectionTitle('Session'),
          _settingsTile(
            icon: Icons.logout,
            title: 'Log out',
            subtitle: 'Sign out of this device',
            onTap: _loggingOut ? null : _confirmLogout,
            destructive: true,
            trailing: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFE74C3C),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool destructive = false,
    Widget? trailing,
  }) {
    final accent = destructive ? const Color(0xFFE74C3C) : AppBrand.accent;
    final titleColor = destructive ? const Color(0xFFE74C3C) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: titleColor, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right,
                    color: destructive
                        ? const Color(0xFFE74C3C).withValues(alpha: 0.7)
                        : Colors.white38,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
