import 'package:book_it/src/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Booking time handling', () {
    final json = <String, dynamic>{
      'id': 'b1',
      'user_id': 'u1',
      'resource_id': 'r1',
      'start_time': '2026-06-11T15:30:00Z',
      'end_time': '2026-06-11T17:00:00Z',
      'total_price': 38.5,
      'commission_amount': 3.5,
      'created_at': '2026-06-11T10:00:00Z',
    };

    test('fromJson exposes times in local zone but the same instant', () {
      final booking = Booking.fromJson(json);
      expect(booking.startTime.isUtc, isFalse);
      expect(booking.startTime.toUtc(), DateTime.utc(2026, 6, 11, 15, 30));
      expect(booking.endTime.toUtc(), DateTime.utc(2026, 6, 11, 17));
    });

    test('toJson writes the times back as UTC', () {
      final booking = Booking.fromJson(json);
      final out = booking.toJson();
      expect(out['start_time'], '2026-06-11T15:30:00.000Z');
      expect(out['end_time'], '2026-06-11T17:00:00.000Z');
    });
  });
}
