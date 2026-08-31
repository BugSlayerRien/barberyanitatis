import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatis_barbershop/user/supabase_password_identity.dart';

String _jwtWithPayload(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}'));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.sig';
}

void main() {
  test('decodeJwtPayload reads recovery AMR', () {
    final token = _jwtWithPayload({
      'amr': [
        {'method': 'recovery', 'timestamp': 1},
      ],
    });
    final decoded = decodeJwtPayload(token);
    expect(decoded, isNotNull);
    expect(decoded!['amr'], isA<List>());
  });

  test('decodeJwtPayload reads oauth AMR without recovery method', () {
    final token = _jwtWithPayload({
      'amr': [
        {'method': 'oauth', 'timestamp': 1},
      ],
    });
    final decoded = decodeJwtPayload(token);
    final amr = decoded!['amr'] as List;
    expect(
      amr.any((item) => item is Map && item['method'] == 'recovery'),
      isFalse,
    );
  });
}
