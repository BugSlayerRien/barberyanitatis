import 'package:flutter/material.dart';

class CompletedAppointmentDetailPage extends StatelessWidget {
  final Map<String, dynamic> appointment;

  const CompletedAppointmentDetailPage({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Appointment Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                image: const DecorationImage(image: AssetImage('assets/images/kalbo.png'), fit: BoxFit.cover),
                border: Border.all(color: const Color(0xFFA99941), width: 1),
              ),
            ),
            const SizedBox(height: 16),
            Text(appointment['service'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text(appointment['barber'] as String, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Color(0xFFA99941), size: 16),
                const SizedBox(width: 8),
                Text(appointment['date'] as String, style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time, color: Color(0xFFA99941), size: 16),
                const SizedBox(width: 8),
                Text(appointment['time'] as String, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Duration: ${appointment['duration']}', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Text('Price: ${appointment['price']}', style: const TextStyle(color: Color(0xFFA99941), fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE74C3C),
                      side: const BorderSide(color: Color(0xFFE74C3C), width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA99941),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Done', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
