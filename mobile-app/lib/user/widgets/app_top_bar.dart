import 'package:flutter/material.dart';
import '../app_brand.dart';
import '../customer_api.dart';
import '../user_session.dart';

class AppTopBar extends StatefulWidget implements PreferredSizeWidget {
  final bool showBack;
  final bool showCustomerActions;
  final VoidCallback? onBack;
  final VoidCallback? onProfileTap;
  final VoidCallback? onNotificationsTap;
  /// Opaque bar for pages where content scrolls under the header (e.g. detail).
  final bool solidBackground;

  const AppTopBar({
    super.key,
    this.showBack = false,
    this.showCustomerActions = true,
    this.onBack,
    this.onProfileTap,
    this.onNotificationsTap,
    this.solidBackground = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<AppTopBar> createState() => _AppTopBarState();
}

class _AppTopBarState extends State<AppTopBar> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshUnreadCount();
  }

  Future<void> _refreshUnreadCount() async {
    final count = await _fetchUnreadCount();
    if (!mounted) {
      return;
    }
    setState(() => _unreadCount = count);
  }

  /// Addresses the request to the right inbox.
  ///
  /// This bar is shared by the customer and barber apps and always sent
  /// `userID`, so notifications.php resolved the recipient as a *customer*
  /// with the barber's id. Every row written for the barber -- a new booking,
  /// a cancellation -- was filed under recipient_type 'Barber' and never
  /// looked at, which is why their bell was permanently empty.
  Map<String, dynamic> _notificationRecipient() {
    if (UserSession.roles.contains('barber')) {
      return {'barberID': UserSession.userId, 'recipientType': 'barber'};
    }

    return {'userID': UserSession.userId};
  }

  Future<int> _fetchUnreadCount() async {
    if (UserSession.userId == null) {
      return 0;
    }
    try {
      final data = await CustomerApi.postDecoded('notifications.php', {
        'action': 'unreadCount',
        ..._notificationRecipient(),
      });
      return (data['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _loadNotifications() async {
    if (UserSession.userId == null) {
      return [];
    }
    try {
      final data = await CustomerApi.postDecoded('notifications.php', {
        'action': 'list',
        ..._notificationRecipient(),
      });
      final unread = (data['unreadCount'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() => _unreadCount = unread);
      }
      final rows = (data['notifications'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      return rows
          .map((row) => {
                'notificationID': (row['notificationID'] as num?)?.toInt() ?? 0,
                'title': row['title']?.toString() ?? 'Update',
                'subtitle': row['subtitle']?.toString() ?? '',
                'isRead': row['isRead'] == true,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _markNotificationRead(int notificationID) async {
    if (UserSession.userId == null || notificationID <= 0) {
      return false;
    }
    try {
      await CustomerApi.postDecoded('notifications.php', {
        'action': 'markRead',
        ..._notificationRecipient(),
        'notificationID': notificationID,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _markAllNotificationsRead() async {
    if (UserSession.userId == null) {
      return false;
    }
    try {
      await CustomerApi.postDecoded('notifications.php', {
        'action': 'markAllRead',
        ..._notificationRecipient(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteNotification(int notificationID) async {
    if (UserSession.userId == null || notificationID <= 0) {
      return false;
    }
    try {
      await CustomerApi.postDecoded('notifications.php', {
        'action': 'delete',
        ..._notificationRecipient(),
        'notificationID': notificationID,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showNotifications(BuildContext context) async {
    if (widget.onNotificationsTap != null) {
      widget.onNotificationsTap!();
      await _refreshUnreadCount();
      return;
    }

    final notifications = await _loadNotifications();
    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: SizedBox(
                  height: MediaQuery.of(dialogContext).size.height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Notifications',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (notifications.any(
                            (n) => (n['isRead'] as bool?) != true,
                          ))
                            TextButton(
                              onPressed: () async {
                                final ok = await _markAllNotificationsRead();
                                if (!context.mounted) return;
                                if (ok) {
                                  setDialogState(() {
                                    for (final n in notifications) {
                                      n['isRead'] = true;
                                    }
                                  });
                                  setState(() => _unreadCount = 0);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not mark all notifications as read.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'Mark all as read',
                                style: TextStyle(
                                  color: AppBrand.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (notifications.isEmpty)
                        const Text(
                          'No notifications yet.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            itemCount: notifications.length,
                            itemBuilder: (_, index) {
                              final item = notifications[index];
                              return _notificationTile(
                                item: item,
                                onTap: () async {
                                  final notificationID =
                                      (item['notificationID'] as int?) ?? 0;
                                  if (notificationID <= 0) {
                                    return;
                                  }
                                  if ((item['isRead'] as bool?) != true) {
                                    final ok = await _markNotificationRead(notificationID);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    if (ok) {
                                      setDialogState(() {
                                        item['isRead'] = true;
                                      });
                                      setState(() {
                                        _unreadCount =
                                            (_unreadCount - 1).clamp(0, 999);
                                      });
                                    }
                                  }
                                },
                                onAction: (action) async {
                                  final notificationID =
                                      (item['notificationID'] as int?) ?? 0;
                                  if (notificationID <= 0) {
                                    return;
                                  }

                                  if (action == 'markRead') {
                                    if ((item['isRead'] as bool?) == true) {
                                      return;
                                    }
                                    final ok = await _markNotificationRead(notificationID);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    if (ok) {
                                      setDialogState(() {
                                        item['isRead'] = true;
                                      });
                                      setState(() {
                                        _unreadCount =
                                            (_unreadCount - 1).clamp(0, 999);
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Could not mark notification as read.'),
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  if (action == 'delete') {
                                    final wasUnread = item['isRead'] != true;
                                    final ok = await _deleteNotification(notificationID);
                                    if (!context.mounted) {
                                      return;
                                    }
                                    if (ok) {
                                      setDialogState(() {
                                        notifications.removeWhere(
                                          (n) =>
                                              (n['notificationID'] as int?) ==
                                              notificationID,
                                        );
                                      });
                                      if (wasUnread) {
                                        setState(() {
                                          _unreadCount =
                                              (_unreadCount - 1).clamp(0, 999);
                                        });
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Could not delete notification.'),
                                        ),
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (mounted) {
      await _refreshUnreadCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor:
          widget.solidBackground ? const Color(0xFF0A0A0A) : Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: widget.solidBackground
          ? const PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: Color(0x21FFFFFF)),
            )
          : null,
      titleSpacing: 0,
      leadingWidth: widget.showBack ? 112 : 64,
      leading: Row(
        children: [
          if (widget.showBack)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
            ),
          const SizedBox(width: 8),
          // Badge only — it already carries the wordmark.
          const BrandMark(size: 42),
        ],
      ),
      actions: widget.showCustomerActions
          ? [
              IconButton(
                onPressed: () => _showNotifications(context),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      _unreadCount > 0 ? Icons.notifications : Icons.notifications_none,
                      color: Colors.white,
                    ),
                    if (_unreadCount > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE74C3C),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF111111), width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline, color: Colors.white),
                onPressed: widget.onProfileTap,
              ),
            ]
          : null,
    );
  }

  Widget _notificationTile({
    required Map<String, dynamic> item,
    required VoidCallback onTap,
    required Future<void> Function(String action) onAction,
  }) {
    final title = item['title']?.toString() ?? 'Update';
    final subtitle = item['subtitle']?.toString() ?? '';
    final isRead = item['isRead'] == true;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        isRead ? Icons.notifications_none : Icons.notifications,
        color: isRead ? Colors.white54 : AppBrand.accent,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isRead ? Colors.white70 : Colors.white,
          fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white70),
        color: const Color(0xFF1C1C1C),
        onSelected: (value) async {
          await onAction(value);
        },
        itemBuilder: (_) {
          final items = <PopupMenuEntry<String>>[];
          if (!isRead) {
            items.add(
              const PopupMenuItem<String>(
                value: 'markRead',
                child: Text('Mark as read', style: TextStyle(color: Colors.white)),
              ),
            );
          }
          items.add(
            const PopupMenuItem<String>(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          );
          return items;
        },
      ),
    );
  }
}
