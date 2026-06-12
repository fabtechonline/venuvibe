import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/models/notification.dart';
import 'package:venue_vibe/src/models/review.dart';
import 'package:venue_vibe/src/models/slot_block.dart';

void main() {
  group('AppNotification.fromJson', () {
    test('parses fields and exposes created_at in local time', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'title': 'Booking confirmed',
        'message': 'See you there',
        'is_read': false,
        'type': 'booking',
        'created_at': '2026-06-11T10:00:00Z',
      });
      expect(n.title, 'Booking confirmed');
      expect(n.isRead, isFalse);
      expect(n.type, 'booking');
      expect(n.createdAt.isUtc, isFalse);
      expect(n.createdAt.toUtc(), DateTime.utc(2026, 6, 11, 10));
    });

    test('defaults missing fields', () {
      final n = AppNotification.fromJson({
        'id': 'n2',
        'created_at': '2026-06-11T10:00:00Z',
      });
      expect(n.title, '');
      expect(n.message, '');
      expect(n.isRead, isFalse);
      expect(n.type, isNull);
    });
  });

  group('Review.fromJson', () {
    test('parses rating + joined user name', () {
      final r = Review.fromJson({
        'id': 'r1',
        'resource_id': 'res1',
        'user_id': 'u1',
        'rating': 5,
        'comment': 'Great!',
        'created_at': '2026-06-11T10:00:00Z',
        'profiles': {'full_name': 'Sarah Johnson'},
      });
      expect(r.rating, 5);
      expect(r.comment, 'Great!');
      expect(r.userName, 'Sarah Johnson');
    });
  });

  group('SlotBlock.fromJson', () {
    test('converts stored UTC times to local', () {
      final b = SlotBlock.fromJson({
        'id': 'b1',
        'resource_id': 'res1',
        'start_time': '2026-06-11T08:00:00Z',
        'end_time': '2026-06-11T09:00:00Z',
        'reason': 'maintenance',
        'created_at': '2026-06-11T07:00:00Z',
        'resources': {'name': 'Tennis Court A'},
      });
      expect(b.startTime.isUtc, isFalse);
      expect(b.startTime.toUtc(), DateTime.utc(2026, 6, 11, 8));
      expect(b.resourceName, 'Tennis Court A');
    });
  });
}
