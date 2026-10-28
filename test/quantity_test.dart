import 'package:flutter_test/flutter_test.dart';
import 'package:stock_count/utilis/quantity.dart';

void main() {
  group('parseQuantity', () {
    test('accepts whole and decimal numbers', () {
      expect(parseQuantity('15'), 15);
      expect(parseQuantity('15.5'), 15.5);
      expect(parseQuantity('0.25'), 0.25);
      expect(parseQuantity(' 7.75 '), 7.75);
    });

    test('accepts a comma as decimal separator', () {
      expect(parseQuantity('15,5'), 15.5);
    });

    test('rejects zero, negatives and non-numbers', () {
      for (final text in ['', '0', '0.0', '-3', 'abc', '1.2.3', 'NaN', 'Infinity']) {
        expect(parseQuantity(text), isNull, reason: text);
      }
    });
  });

  group('formatQuantity', () {
    test('hides the decimal part of whole numbers', () {
      expect(formatQuantity(15.0), '15');
      expect(formatQuantity(15.5), '15.5');
    });
  });
}
