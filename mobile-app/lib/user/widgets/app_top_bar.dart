import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../user_session.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBack;
  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationsTap;

  const AppTopBar({
    super.key,
    this.showBack = false,
    this.onBack,
    this.onProfileTap,
    this.onNotificationsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      leadingWidth: showBack ? 150 : 120,
      leading: Row(
        children: [
          if (showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack ?? () => Navigator.of(context).pop(),
            ),
          const SizedBox(width: 16),
          Image.asset(
            'assets/images/TATIS.png',
            height: 26,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none, color: Colors.white),
          onPressed: onNotificationsTap ?? () => _showNotifications(context),
        ),
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          onPressed: onProfileTap,
        ),
      ],
    );
  }

  Future<void> _showNotifications(BuildContext context) async {
    final notifications = await _loadNotifications();
    if (!context.mounted) return;
    showModalBottomSheet<void>(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notifications',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (notifications.isEmpty)
                const Text('No notifications yet.', style: TextStyle(color: Colors.white70, fontSize: 12))
              else
                ...notifications.map(
                  (item) => _notificationTile(item['title'] ?? 'Update', item['subtitle'] ?? ''),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, String>>> _loadNotifications() async {
    if (UserSession.userId == null) {
      return [];
    }
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/notifications.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userID': UserSession.userId}),
      );
      if (response.statusCode != 200 || response.body.isEmpty) {
        return [];
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = (data['notifications'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      return rows
          .map((row) => {
                'title': row['title']?.toString() ?? 'Update',
                'subtitle': row['subtitle']?.toString() ?? '',
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Widget _notificationTile(String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.notifications, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    );
  }
}
