import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_page.dart';
import 'user_session.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _appointmentReminders = true;
  bool _promotionAlerts = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _appointmentReminders = prefs.getBool('settings_appointment_reminders') ?? true;
      _promotionAlerts = prefs.getBool('settings_promotion_alerts') ?? false;
      _loadingPrefs = false;
    });
  }

  Future<void> _savePref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _sectionTitle('Account'),
                _settingsTile(
                  icon: Icons.person_outline,
                  title: 'Edit profile',
                  subtitle: 'Name, phone, photo, hair texture',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfilePage()),
                    );
                  },
                ),
                const SizedBox(height: 20),
                _sectionTitle('Notifications'),
                _switchTile(
                  title: 'Appointment reminders',
                  subtitle: 'Booking confirmations and schedule updates',
                  value: _appointmentReminders,
                  onChanged: (v) async {
                    setState(() => _appointmentReminders = v);
                    await _savePref('settings_appointment_reminders', v);
                  },
                ),
                _switchTile(
                  title: 'Promotions & offers',
                  subtitle: 'Deals and shop announcements',
                  value: _promotionAlerts,
                  onChanged: (v) async {
                    setState(() => _promotionAlerts = v);
                    await _savePref('settings_promotion_alerts', v);
                  },
                ),
                const SizedBox(height: 20),
                _sectionTitle('App'),
                _settingsTile(
                  icon: Icons.info_outline,
                  title: 'Signed in as',
                  subtitle: UserSession.email?.isNotEmpty == true
                      ? UserSession.email!
                      : 'Customer account',
                  onTap: null,
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
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
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
                Icon(icon, color: const Color(0xFFA99941)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          activeThumbColor: const Color(0xFFA99941),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ),
    );
  }
}
