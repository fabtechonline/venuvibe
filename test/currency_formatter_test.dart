import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

void main() {
  group('currencySymbol', () {
    test('maps known ISO codes to symbols', () {
      expect(currencySymbol('ZAR'), 'R');
      expect(currencySymbol('USD'), r'$');
      expect(currencySymbol('GBP'), '£');
    });

    test('is case-insensitive', () {
      expect(currencySymbol('eur'), '€');
    });

    test('falls back to the code itself when unknown', () {
      expect(currencySymbol('XYZ'), 'XYZ');
    });
  });

  group('formatPrice', () {
    test('prefixes the symbol and uses two decimals', () {
      expect(formatPrice(25, 'ZAR'), 'R 25.00');
      expect(formatPrice(38.5, 'ZAR'), 'R 38.50');
    });

    test('formatPriceShort drops the decimals', () {
      expect(formatPriceShort(25, 'USD'), r'$ 25');
    });
  });
}
