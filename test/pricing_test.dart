import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/utils/pricing.dart';

void main() {
  group('customBasePrice', () {
    test('pro-rates the hourly rate to minutes', () {
      expect(customBasePrice(200, 90), 300.00); // 1.5h @ R200
      expect(customBasePrice(200, 60), 200.00);
      expect(customBasePrice(150, 45), 112.50);
    });

    test('rounds to cents', () {
      expect(customBasePrice(100, 50), 83.33);
    });
  });

  group('commissionOn / orderTotal', () {
    test('commission applies to base + addons', () {
      expect(
        commissionOn(base: 100, addons: 50, ratePercent: 10),
        15.00,
      );
    });

    test('discount reduces the commissionable amount', () {
      expect(
        commissionOn(base: 100, addons: 50, discount: 20, ratePercent: 10),
        13.00,
      );
    });

    test('order total = base − discount + addons + commission', () {
      expect(
        orderTotal(base: 100, addons: 50, discount: 20, ratePercent: 10),
        143.00,
      );
    });
  });
}
