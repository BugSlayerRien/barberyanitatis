import 'package:flutter/material.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);

class AdminManageServicesPage extends StatefulWidget {
  const AdminManageServicesPage({super.key});

  @override
  State<AdminManageServicesPage> createState() => _AdminManageServicesPageState();
}

class _AdminManageServicesPageState extends State<AdminManageServicesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All Categories';
  String _sortBy = 'Sort by Name';

  final List<Map<String, dynamic>> _services = [
    {
      'name': 'Hair Color Transformation',
      'tag': 'HAIR COLOR',
      'description': 'Complete hair color change with premium products',
      'price': '₱2,500',
      'duration': '180 minutes',
      'available': true,
      'popular': false,
    },
    {
      'name': 'Hair Cut & Style',
      'tag': 'HAIR CUT',
      'description': 'Professional haircut with styling',
      'price': '₱850',
      'duration': '60 minutes',
      'available': true,
      'popular': true,
    },
    {
      'name': 'Hair Extensions',
      'tag': 'EXTENSIONS',
      'description': 'Premium hair extensions application',
      'price': '₱4,500',
      'duration': '120 minutes',
      'available': true,
      'popular': false,
    },
  ];

  List<Map<String, dynamic>> get _filteredServices {
    final q = _searchController.text.toLowerCase();
    return _services.where((s) {
      final matchesText = q.isEmpty ||
          s['name'].toString().toLowerCase().contains(q) ||
          s['description'].toString().toLowerCase().contains(q);
      final matchesCategory = _selectedCategory == 'All Categories' || s['tag'] == _selectedCategory.toUpperCase();
      return matchesText && matchesCategory;
    }).toList();
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
            _buildStatsRow(),
            const SizedBox(height: 16),
            _buildSectionHeader('Service Management'),
            const SizedBox(height: 8),
            _buildAddServiceButton(),
            const SizedBox(height: 12),
            _buildFilters(),
            const SizedBox(height: 16),
            ..._filteredServices.map(_buildServiceCard),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Total Services', _services.length.toString())),
      ],
    );
  }

  Widget _buildStatCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(value, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildAddServiceButton() {
    return ElevatedButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add service form coming soon'), backgroundColor: Color(0xFF1A1A1A)),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: const Text('Add New Service', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        // Search
        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search services...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            prefixIcon: const Icon(Icons.search, color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: kGoldColor),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        // Category
        DropdownButtonFormField<String>(
          value: _selectedCategory,
          items: const [
            'All Categories',
            'HAIR COLOR',
            'HAIR CUT',
            'EXTENSIONS',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _selectedCategory = v ?? 'All Categories'),
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Sort
        DropdownButtonFormField<String>(
          value: _sortBy,
          items: const [
            'Sort by Name',
            'Sort by Price',
            'Sort by Popular',
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _sortBy = v ?? 'Sort by Name'),
          dropdownColor: const Color(0xFF1A1A1A),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1A1A1A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey[800]!),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s['name'],
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  s['tag'],
                  style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (s['popular'] == true) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white),
                  ),
                  child: const Text(
                    'POPULAR',
                    style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ]
            ],
          ),
          const SizedBox(height: 8),
          Text(s['description'], style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetaChip(s['price'], Colors.white, Colors.black),
              const SizedBox(width: 8),
              _buildMetaChip(s['available'] ? 'Available' : 'Disabled', s['available'] ? Colors.white : Colors.white, s['available'] ? Colors.black : Colors.black),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildWhiteButton(label: s['available'] ? 'Disable' : 'Enable', onPressed: () {
                setState(() => s['available'] = !(s['available'] as bool));
              }),
              _buildGoldOutlineButton(label: s['popular'] ? 'Remove Popular' : 'Mark Popular', onPressed: () {
                setState(() => s['popular'] = !(s['popular'] as bool));
              }),
              _buildGoldOutlineButton(label: 'Edit', onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edit coming soon')));
              }),
              _buildGoldOutlineButton(label: 'Delete', onPressed: () {
                setState(() => _services.remove(s));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildWhiteButton({required String label, required VoidCallback onPressed}) {
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

  Widget _buildGoldOutlineButton({required String label, required VoidCallback onPressed}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    );
  }
}
