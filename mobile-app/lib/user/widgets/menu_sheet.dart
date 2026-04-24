import 'package:flutter/material.dart';
import '../about_page.dart';
import '../auth_page.dart';
import '../contact_page.dart';
import '../history_page.dart';
import '../settings_page.dart';

Future<void> showAppMenuSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MenuItem(
              icon: Icons.settings,
              label: 'Settings',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              },
            ),
            _MenuItem(
              icon: Icons.phone,
              label: 'Contact',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactPage()));
              },
            ),
            _MenuItem(
              icon: Icons.info_outline,
              label: 'About',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
              },
            ),
            _MenuItem(
              icon: Icons.history,
              label: 'History',
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage()));
              },
            ),
            _MenuItem(
              icon: Icons.logout,
              label: 'Logout',
              isDestructive: true,
              onTap: () async {
                Navigator.of(ctx).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Confirm logout', style: TextStyle(color: Colors.white)),
                    content: const Text('Are you sure you want to log out?', style: TextStyle(color: Colors.white70)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        child: const Text('Logout', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthPage()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? const Color(0xFFE74C3C) : Colors.white),
      title: Text(label, style: TextStyle(color: isDestructive ? const Color(0xFFE74C3C) : Colors.white)),
      onTap: onTap,
    );
  }
}
