import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tatis_barbershop/user/auth_page.dart';

String _typed(String input) {
  var value = const TextEditingValue();
  for (final f in PersonName.inputFormatters) {
    value = f.formatEditUpdate(
      value,
      TextEditingValue(
        text: input,
        selection: TextSelection.collapsed(offset: input.length),
      ),
    );
    input = value.text;
  }
  return value.text;
}

void main() {
  group('PersonName.errorFor', () {
    test('rejects digits', () {
      expect(PersonName.errorFor('Juan1', 'First name'), isNotNull);
      expect(PersonName.errorFor('123', 'First name'), isNotNull);
      expect(PersonName.errorFor('Dela Cruz 2', 'Last name'), isNotNull);
    });

    test('rejects symbols', () {
      for (final bad in ['Juan!', 'J@an', 'Ju_an', 'Juan#', '😀']) {
        expect(PersonName.errorFor(bad, 'First name'), isNotNull, reason: bad);
      }
    });

    test('accepts real names', () {
      for (final good in [
        'Juan',
        'Dela Cruz',
        "O'Neil",
        'Anne-Marie',
        'Jr.',
        'José',
        'Ñoño',
      ]) {
        expect(PersonName.errorFor(good, 'First name'), isNull, reason: good);
      }
    });

    test('must start with a letter', () {
      expect(PersonName.errorFor('-Juan', 'First name'), isNotNull);
      expect(PersonName.errorFor("'Juan", 'First name'), isNotNull);
    });

    test('empty and over-long are rejected', () {
      expect(PersonName.errorFor('   ', 'First name'), 'First name is required.');
      expect(PersonName.errorFor('a' * 51, 'First name'), isNotNull);
      expect(PersonName.errorFor('a' * 50, 'First name'), isNull);
    });

    test('message names the field', () {
      expect(PersonName.errorFor('Juan1', 'Last name'), startsWith('Last name'));
    });
  });

  group('PersonName.inputFormatters', () {
    test('digits cannot be typed', () {
      expect(_typed('Juan123'), 'Juan');
      expect(_typed('D3la Cruz'), 'Dla Cruz');
    });

    test('allowed punctuation survives typing', () {
      expect(_typed("Anne-Marie O'Neil Jr."), "Anne-Marie O'Neil Jr.");
    });

    test('length is capped at 50', () {
      expect(_typed('a' * 80).length, 50);
    });
  });
}
