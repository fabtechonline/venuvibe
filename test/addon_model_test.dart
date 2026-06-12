import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';

void main() {
  test('ResourceAddon parses and round-trips', () {
    final a = ResourceAddon.fromJson(const {
      'id': 'a1',
      'resource_id': 'r1',
      'name': 'Racquet hire',
      'price': 50,
      'max_qty': 4,
      'is_active': true,
    });
    expect(a.name, 'Racquet hire');
    expect(a.price, 50.0);
    expect(a.maxQty, 4);
    expect(a.toJson()['max_qty'], 4);
  });

  test('BookingAddon snapshots compute a line total', () {
    final ba = BookingAddon.fromJson(const {
      'id': 'ba1',
      'booking_id': 'b1',
      'addon_id': null,
      'name': 'Table hire',
      'unit_price': 25.5,
      'qty': 3,
    });
    expect(ba.addonId, isNull); // catalog entry deleted; snapshot remains
    expect(ba.lineTotal, 76.5);
  });

  test('ResourceHours normalizes Postgres time strings', () {
    final h = ResourceHours.fromJson(const {
      'id': 'h1',
      'resource_id': 'r1',
      'weekday': 6,
      'is_closed': false,
      'open_time': '09:00:00',
      'close_time': '17:30:00',
      'break_start': null,
      'break_end': null,
    });
    expect(h.openTime, '09:00');
    expect(h.closeTime, '17:30');
    expect(h.hasBreak, isFalse);
    expect(h.weekdayName, 'Saturday');
  });
}
