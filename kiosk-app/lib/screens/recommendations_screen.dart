import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'queue_screen.dart';

class RecommendationsScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Map<String, dynamic>> recommendations;
  final String sessionId;

  const RecommendationsScreen({
    super.key,
    required this.imageBytes,
    required this.recommendations,
    required this.sessionId,
  });

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  bool _submitting = false;
  String? _error;

  Future<int?> _fetchDefaultServiceId() async {
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/services.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'list'}),
    );
    if (response.statusCode != 200 || response.body.isEmpty) {
      return null;
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final services = (data['services'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final haircut = services.firstWhere(
      (service) => (service['category']?.toString() ?? '').toLowerCase() == 'haircut',
      orElse: () => services.isNotEmpty ? services.first : <String, dynamic>{},
    );
    if (haircut.isEmpty) {
      return null;
    }
    return haircut['service_id'] is int
        ? haircut['service_id'] as int
        : int.tryParse('${haircut['service_id']}');
  }

  Future<void> _proceedToQueue() async {
    if (widget.sessionId.isEmpty) {
      setState(() => _error = 'Session missing. Please rescan.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final serviceId = await _fetchDefaultServiceId();
      if (serviceId == null) {
        setState(() => _error = 'No services available.');
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/receptionist.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'createWalkin',
          'sessionID': widget.sessionId,
          'serviceIDs': [serviceId],
        }),
      );

      if (!mounted) return;
      final data = response.body.isNotEmpty ? jsonDecode(response.body) as Map<String, dynamic> : {};
      if (response.statusCode != 200) {
        setState(() => _error = data['error']?.toString() ?? 'Queue failed.');
        return;
      }

      final queueNumber = data['queueNumber']?.toString() ?? 'W-000';
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QueueScreen(queueNumber: queueNumber),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Queue failed: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendations'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(widget.imageBytes, height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
            const Text('Top Matches', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: widget.recommendations.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = widget.recommendations[index];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cut, color: Colors.white70),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['style_name']?.toString() ?? 'Style', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              Text('Match ${(double.tryParse(item['confidence_score']?.toString() ?? '') ?? 0) * 100 ~/ 1}%',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _proceedToQueue,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                      )
                    : const Text('Proceed to Queue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
