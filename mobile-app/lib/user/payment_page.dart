import 'package:flutter/material.dart';
import 'appointments_page.dart';

class PaymentPage extends StatefulWidget {
  final String barberName;
  final String date;
  final String time;
  final int amount;
  final String haircutName;

  const PaymentPage({
    super.key,
    required this.barberName,
    required this.date,
    required this.time,
    required this.amount,
    required this.haircutName,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  int _selectedMethod = 0; // 0=Card,1=Gcash/Qrph

  @override
  Widget build(BuildContext context) {
    final servicePrice = widget.amount.toDouble();
    final tax = (servicePrice * 0.05);
    final total = servicePrice + tax;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Payment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 12),
            Text('${widget.date} • ${widget.time}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 20),

            // Payment Methods
            Container(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Choose Payment Method', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),

                  // Card (uses single credit card icon)
                  _paymentMethodTile(
                    0,
                    title: 'Credit/Debit Card',
                    trailing: Row(children: [
                      _paymentIcon('assets/images/creditcard.png'),
                    ]),
                  ),

                  const SizedBox(height: 8),

                  // GCash / QRPh
                  _paymentMethodTile(1, title: 'Gcash, Paymaya, QRPh', trailing: _paymentIcon('assets/images/gcash.png')),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Mock card inputs (only visible for card method)
            if (_selectedMethod == 0) ...[
              const TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  hintText: 'John Doe',
                ),
              ),
              const SizedBox(height: 8),
              const TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black,
                  hintText: '1234 5678 9012 3456',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(filled: true, fillColor: Colors.black, hintText: 'MM/YY'),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(filled: true, fillColor: Colors.black, hintText: 'CVV'),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),

            // Summary Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.haircutName, style: const TextStyle(color: Colors.white70)),
                      Text('₱${servicePrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tax', style: TextStyle(color: Colors.white70)),
                      Text('₱${tax.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('₱${total.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Complete payment -> go to AppointmentsPage
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AppointmentsPage()),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Complete Payment', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentMethodTile(int id, {required String title, Widget? trailing}) {
    final selected = _selectedMethod == id;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111111) : const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.white : Colors.white10),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: id,
              groupValue: _selectedMethod,
              onChanged: (v) => setState(() => _selectedMethod = v ?? 0),
              fillColor: MaterialStateProperty.all(Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white))),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _paymentIcon(String asset) {
    return Image.asset(
      asset,
      height: 20,
      width: 40,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Container(
        height: 20,
        width: 40,
        alignment: Alignment.center,
        child: const Icon(Icons.payment, color: Colors.white24, size: 18),
      ),
    );
  }
}
