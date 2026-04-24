import 'package:flutter/material.dart';
import '../shared/pagination_controls.dart';

const Color kGoldColor = Color(0xFFA99941);
const Color kDarkBackground = Color(0xFF0A0A0A);
const Color kCardShadow = Color(0x22000000);

class ReceptionistWalkInsPage extends StatefulWidget {
  final List<Map<String, dynamic>> walkIns;
  final Function(Map<String, dynamic>) onWalkInAdded;

  const ReceptionistWalkInsPage({
    super.key,
    required this.walkIns,
    required this.onWalkInAdded,
  });

  @override
  State<ReceptionistWalkInsPage> createState() =>
      _ReceptionistWalkInsPageState();
}

class _ReceptionistWalkInsPageState extends State<ReceptionistWalkInsPage> {
  int _currentPage = 1;

  static const int _itemsPerPage = 6;

  @override
  void didUpdateWidget(covariant ReceptionistWalkInsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.walkIns.length != widget.walkIns.length) {
      final totalPages = _totalPages(widget.walkIns.length);
      if (_currentPage > totalPages) {
        _currentPage = totalPages;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalPages(widget.walkIns.length);
    final safePage = _currentPage.clamp(1, totalPages);
    final pagedWalkIns = _paginateWalkIns(widget.walkIns, safePage);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Walk-In Queue',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
              ElevatedButton.icon(
                onPressed: _showAddWalkInDialog,
                icon: const Icon(Icons.add),
                label: const Text('ADD WALK-IN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.walkIns.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 1),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.people_outline, color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    const Text('No walk-ins yet',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            )
          else
            ...pagedWalkIns.map((walkIn) => _buildWalkInCard(walkIn)).toList(),
          PaginationControls(
            currentPage: safePage,
            totalPages: totalPages,
            onPageChanged: (page) {
              setState(() {
                _currentPage = page;
              });
            },
          ),
        ],
      ),
    );
  }

  int _totalPages(int totalItems) {
    if (totalItems <= 0) {
      return 1;
    }
    return ((totalItems - 1) ~/ _itemsPerPage) + 1;
  }

  List<Map<String, dynamic>> _paginateWalkIns(
      List<Map<String, dynamic>> walkIns, int page) {
    final start = (page - 1) * _itemsPerPage;
    if (start >= walkIns.length) {
      return const <Map<String, dynamic>>[];
    }
    final end = (start + _itemsPerPage).clamp(0, walkIns.length);
    return walkIns.sublist(start, end);
  }

  Widget _buildWalkInCard(Map<String, dynamic> walkIn) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF252525)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (walkIn['name'] as String)
                        .split(' ')
                        .map((e) => e[0])
                        .join()
                        .toUpperCase(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      walkIn['name'] as String,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      walkIn['service'] as String,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      walkIn['phone'] as String,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kGoldColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kGoldColor),
                ),
                child: const Text(
                  'WAITING',
                  style: TextStyle(
                      color: kGoldColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddWalkInDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedService = 'Quick Trim';
    var isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('ADD NEW WALK-IN',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Name',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF111111),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: kGoldColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Contact Number',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF111111),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: kGoldColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedService,
                    items: [
                      'Quick Trim',
                      'Precision Cut',
                      'Color Treatment',
                      'Styling',
                      'Full Package'
                    ]
                        .map((service) => DropdownMenuItem(
                              value: service,
                              child: Text(service,
                                  style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: isSubmitting
                        ? null
                        : (value) {
                            selectedService = value ?? 'Quick Trim';
                          },
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF111111),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: kGoldColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    dropdownColor: const Color(0xFF111111),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('CANCEL',
                    style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        if (nameController.text.isNotEmpty &&
                            phoneController.text.isNotEmpty) {
                          setDialogState(() => isSubmitting = true);
                          final newWalkIn = {
                            'name': nameController.text,
                            'phone': phoneController.text,
                            'service': selectedService,
                          };
                          widget.onWalkInAdded(newWalkIn);
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Walk-in added successfully')),
                          );
                          _showAIAvailabilityCheckDialog();
                        }
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black),
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('ADD WALK-IN',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAIAvailabilityCheckDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Availability Check',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Smart scheduling and walk-in management system',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 20),
                // Current System Status
                const Text(
                  'Current System Status',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const Text('85%',
                            style: TextStyle(
                                color: Color(0xFFE74C3C),
                                fontWeight: FontWeight.bold,
                                fontSize: 28)),
                        const SizedBox(height: 4),
                        const Text('CURRENT LOAD',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('3',
                            style: TextStyle(
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.bold,
                                fontSize: 28)),
                        const SizedBox(height: 4),
                        const Text('AVAILABLE',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('2',
                            style: TextStyle(
                                color: Color(0xFFFFA726),
                                fontWeight: FontWeight.bold,
                                fontSize: 28)),
                        const SizedBox(height: 4),
                        const Text('RESCHEDULES',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Best Slot Suggestions
                const Text(
                  'Best Slot Suggestions',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 12),
                _buildSlotSuggestionDialog(
                    '2:30 PM',
                    'Stylist: Emma R.',
                    'Service: Cut & Style',
                    '95% Match',
                    'LOW IMPACT',
                    const Color(0xFF4CAF50)),
                const SizedBox(height: 10),
                _buildSlotSuggestionDialog(
                    '3:15 PM',
                    'Stylist: Mike C.',
                    'Service: Color Touch-up',
                    '88% Match',
                    'MEDIUM IMPACT',
                    const Color(0xFFFFA726)),
                const SizedBox(height: 10),
                _buildSlotSuggestionDialog(
                    '4:00 PM',
                    'Stylist: Sarah J.',
                    'Service: Full Color',
                    '92% Match',
                    'LOW IMPACT',
                    const Color(0xFF4CAF50)),
                const SizedBox(height: 20),
                // Close Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('CLOSE',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotSuggestionDialog(String time, String stylist, String service,
      String match, String impact, Color impactColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                time,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: impactColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: impactColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: impactColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      impact,
                      style: TextStyle(
                          color: impactColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stylist,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            service,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                match,
                style: const TextStyle(
                    color: kGoldColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Booking slot at $time')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  minimumSize: const Size(0, 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'BOOK SLOT',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
