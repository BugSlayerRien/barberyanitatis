import 'package:flutter/material.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  int _selectedSection = 0; // 0: Salon Info, 1: Working Hours, 2: Payment, 3: Notifications, 4: Backup

  final TextEditingController _salonName = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _salonName.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kDarkBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSettingsTabs(),
            const SizedBox(height: 16),
            _buildSectionContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTabs() {
    final tabs = [
      'Salon Information',
      'Working Hours',
      'Payment Settings',
      'Notifications',
      'Backup & Security',
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white),
      ),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(tabs.length, (i) {
          final selected = _selectedSection == i;
          return ElevatedButton(
            onPressed: () => setState(() => _selectedSection = i),
            style: ElevatedButton.styleFrom(
              backgroundColor: selected ? Colors.white : Colors.transparent,
              foregroundColor: selected ? Colors.black : Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              tabs[i],
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSectionContent() {
    switch (_selectedSection) {
      case 0:
        return _buildSalonInfo();
      case 1:
        return _buildWorkingHours();
      case 2:
        return _buildPaymentSettings();
      case 3:
        return _buildNotifications();
      case 4:
      default:
        return _buildBackupSecurity();
    }
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      filled: true,
      fillColor: const Color(0xFF0F0F0F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[800]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[800]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: kGoldColor),
      ),
    );
  }

  Widget _buildSalonInfo() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Salon Information', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: _salonName, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Salon Name')),
          const SizedBox(height: 12),
          TextField(controller: _address, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Business Address')),
          const SizedBox(height: 12),
          TextField(controller: _phone, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Phone Number')),
          const SizedBox(height: 12),
          TextField(controller: _email, style: const TextStyle(color: Colors.white), decoration: _inputDecoration('Email Address')),
          const SizedBox(height: 16),
          _buildLogoUpload(),
          const SizedBox(height: 16),
          Row(
            children: [
              _whiteButton('Save Changes', () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
              }),
              const SizedBox(width: 8),
              _goldOutlineButton('Reset', () {
                _salonName.clear();
                _address.clear();
                _phone.clear();
                _email.clear();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoUpload() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.upload_file, color: Colors.white),
              SizedBox(width: 8),
              Text('Upload Salon Logo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text('PNG, JPG up to 2MB', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              _whiteButton('Choose File', () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File picker coming soon')));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkingHours() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Working Hours', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Configure opening and closing times for each day.', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          _whiteButton('Edit Hours', () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hours editor coming soon')));
          }),
        ],
      ),
    );
  }

  Widget _buildPaymentSettings() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Payment Settings', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Connect payment providers and set payout preferences.', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          _whiteButton('Connect Provider', () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payments integration coming soon')));
          }),
        ],
      ),
    );
  }

  Widget _buildNotifications() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Configure email and push notifications.', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          _whiteButton('Manage Alerts', () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications settings coming soon')));
          }),
        ],
      ),
    );
  }

  Widget _buildBackupSecurity() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Backup & Security', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Manage backups, access control, and security settings.', style: TextStyle(color: Colors.grey[500])),
          const SizedBox(height: 16),
          Row(
            children: [
              _whiteButton('Backup Now', () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup triggered')));
              }),
              const SizedBox(width: 8),
              _goldOutlineButton('Manage Access', () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Access control coming soon')));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whiteButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
  }

  Widget _goldOutlineButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
  }
}
