import 'package:flutter/material.dart';

import 'calendar_page.dart';
import 'group_booking_page.dart';

class GroupSizePage extends StatefulWidget {
  final int barberId;
  final String barberName;

  const GroupSizePage({
    super.key,
    required this.barberId,
    required this.barberName,
  });

  @override
  State<GroupSizePage> createState() => _GroupSizePageState();
}

class _GroupSizePageState extends State<GroupSizePage> {
  int _peopleCount = 1;

  void _continue() {
    if (_peopleCount <= 1) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CalendarPage(
            barberId: widget.barberId,
            barberName: widget.barberName,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupBookingPage(
          barberId: widget.barberId,
          barberName: widget.barberName,
          peopleCount: _peopleCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        title: const Text('Group size', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booking with ${widget.barberName}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'How many people?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Count includes you (e.g. 3 = you plus 2 guests). '
              'One account can hold one active booking. We find consecutive hour slots for the whole group.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(5, (index) {
                final count = index + 1;
                final selected = _peopleCount == count;
                return ChoiceChip(
                  label: Text('$count'),
                  selected: selected,
                  onSelected: (_) => setState(() => _peopleCount = count),
                  selectedColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: const Color(0xFF1A1A1A),
                  side: const BorderSide(color: Colors.white24),
                );
              }),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _continue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _peopleCount == 1 ? 'Continue (just me)' : 'Find slots for $_peopleCount',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
