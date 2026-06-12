import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/models/booking.dart';

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

    test('parses the price breakdown columns with safe defaults', () {
      final booking = Booking.fromJson(json);
      expect(booking.basePrice, isNull);
      expect(booking.addonsTotal, 0);
      expect(booking.discountAmount, 0);

      final withBreakdown = Booking.fromJson({
        ...json,
        'base_price': 30.0,
        'addons_total': 5.0,
        'discount_amount': 2.5,
      });
      expect(withBreakdown.basePrice, 30.0);
      expect(withBreakdown.addonsTotal, 5.0);
      expect(withBreakdown.discountAmount, 2.5);
    });
  });

  group('Booking status helpers', () {
    Booking withStatus(String status, {DateTime? start}) => Booking(
          id: 'b1',
          userId: 'u1',
          startTime: start ?? DateTime.now().add(const Duration(days: 1)),
          endTime: (start ?? DateTime.now().add(const Duration(days: 1)))
              .add(const Duration(hours: 1)),
          totalPrice: 100,
          createdAt: DateTime.now(),
          status: status,
        );

    test('approval-pipeline statuses count as upcoming and hold the slot', () {
      expect(withStatus('confirmed').isUpcoming, isTrue);
      expect(withStatus('pending_approval').isUpcoming, isTrue);
      expect(withStatus('approved').isUpcoming, isTrue);
      expect(withStatus('rejected').isUpcoming, isFalse);
      expect(withStatus('cancelled').isUpcoming, isFalse);
    });

    test('state flags map to the right statuses', () {
      expect(withStatus('pending_approval').isAwaitingApproval, isTrue);
      expect(withStatus('approved').isAwaitingPayment, isTrue);
      expect(withStatus('rejected').isRejected, isTrue);
      expect(withStatus('confirmed').isAwaitingApproval, isFalse);
    });

    test('unpaid pipeline bookings can always be cancelled', () {
      // Even inside the free-cancellation window cut-off.
      final soon = DateTime.now().add(const Duration(hours: 1));
      expect(
        withStatus('pending_approval', start: soon).isCancellableWithin(24),
        isTrue,
      );
      expect(
        withStatus('approved', start: soon).isCancellableWithin(24),
        isTrue,
      );
      expect(
        withStatus('confirmed', start: soon).isCancellableWithin(24),
        isFalse,
      );
    });
  });
}
