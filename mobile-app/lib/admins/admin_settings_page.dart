import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_api_service.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _openTime = TextEditingController(text: '09:00');
  final _closeTime = TextEditingController(text: '20:00');
  final _fromEmail = TextEditingController();
  final _testEmail = TextEditingController();

  bool _emailNotifications = false;
  bool _autoBackup = false;
  bool _forceMfa = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _openTime.dispose();
    _closeTime.dispose();
    _fromEmail.dispose();
    _testEmail.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await AdminApiService.fetchSettings();
      if (!mounted) return;
      setState(() {
        _openTime.text = settings['openTime']?.toString() ?? '09:00';
        _closeTime.text = settings['closeTime']?.toString() ?? '20:00';
        _fromEmail.text = settings['notificationFromEmail']?.toString() ?? '';
        _emailNotifications = settings['emailNotificationsEnabled'] == 1;
        _autoBackup = settings['autoBackupEnabled'] == 1;
        _forceMfa = settings['forceMfa'] == 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AdminApiService.saveSettings(
        openTime: _openTime.text.trim(),
        closeTime: _closeTime.text.trim(),
        emailNotificationsEnabled: _emailNotifications,
        autoBackupEnabled: _autoBackup,
        forceMfa: _forceMfa,
        notificationFromEmail: _fromEmail.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _backup() async {
    setState(() => _saving = true);
    try {
      final result = await AdminApiService.downloadBackup();
      final backup = result['backup'];
      if (backup != null) {
        final json = const JsonEncoder.withIndent('  ').convert(backup);
        await Clipboard.setData(ClipboardData(text: json));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backup copied (${result['fileName'] ?? 'snapshot'}). '
              'Also saved on server under storage/backups.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTestEmail() async {
    final to = _testEmail.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a test email address')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await AdminApiService.sendTestEmail(to);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Test sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _processQueue() async {
    setState(() => _saving = true);
    try {
      final result = await AdminApiService.processNotifications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? 'Queue processed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Container(
      color: kDarkBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Retry')),
              const SizedBox(height: 12),
            ],
            _sectionTitle('Shop hours'),
            _card(
              child: Column(
                children: [
                  _field('Open time (HH:MM)', _openTime),
                  const SizedBox(height: 12),
                  _field('Close time (HH:MM)', _closeTime),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Notifications'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Email notifications', style: TextStyle(color: Colors.white)),
                    value: _emailNotifications,
                    activeThumbColor: kGoldColor,
                    onChanged: (v) => setState(() => _emailNotifications = v),
                  ),
                  _field('From email', _fromEmail),
                  const SizedBox(height: 12),
                  _field('Send test to', _testEmail),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _outlineBtn('Send test email', _saving ? null : _sendTestEmail),
                      _outlineBtn('Process queue', _saving ? null : _processQueue),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionTitle('Backup & security'),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatic backups (flag)', style: TextStyle(color: Colors.white)),
                    subtitle: const Text(
                      'Stores preference; run Backup database for an immediate snapshot.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _autoBackup,
                    activeThumbColor: kGoldColor,
                    onChanged: (v) => setState(() => _autoBackup = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require MFA', style: TextStyle(color: Colors.white)),
                    value: _forceMfa,
                    activeThumbColor: kGoldColor,
                    onChanged: (v) => setState(() => _forceMfa = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _backup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kGoldColor,
                        foregroundColor: Colors.black,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Backup database', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: Text(
                  _saving ? 'Working…' : 'Save all settings',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: child,
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF0F0F0F),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: kGoldColor),
        ),
      ),
    );
  }

  Widget _outlineBtn(String label, VoidCallback? onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
      ),
      child: Text(label),
    );
  }
}
