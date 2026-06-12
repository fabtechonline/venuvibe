import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';
import 'package:venue_vibe/src/utils/slot_generator.dart';

void main() {
  final day = DateTime(2026, 6, 15); // a Monday
  final early = DateTime(2026); // "now" well before the test day

  Resource resource({String open = '07:00', String close = '23:00'}) =>
      Resource(
        id: 'r1',
        tenantId: 't1',
        name: 'Court',
        createdAt: DateTime(2026),
        openTime: open,
        closeTime: close,
      );

  group('windowsForWeekday', () {
    test('falls back to the legacy single window when no rows exist', () {
      final w = windowsForWeekday(
        const [],
        DateTime.monday,
        resource(open: '08:00', close: '20:00'),
      );
      expect(w, hasLength(1));
      expect(w.single.open, '08:00');
      expect(w.single.close, '20:00');
    });

    test('closed day yields no windows', () {
      final hours = [
        const ResourceHours(resourceId: 'r1', weekday: 1, isClosed: true),
      ];
      expect(windowsForWeekday(hours, 1, resource()), isEmpty);
    });

    test('a break splits the day into two windows', () {
      final hours = [
        const ResourceHours(
          resourceId: 'r1',
          weekday: 1,
          openTime: '08:00',
          closeTime: '22:00',
          breakStart: '13:00',
          breakEnd: '14:00',
        ),
      ];
      final w = windowsForWeekday(hours, 1, resource());
      expect(w, hasLength(2));
      expect(w[0].open, '08:00');
      expect(w[0].close, '13:00');
      expect(w[1].open, '14:00');
      expect(w[1].close, '22:00');
    });
  });

  group('generateSlots', () {
    test('walks the window in slot-minute steps', () {
      final slots = generateSlots(
        day: day,
        windows: const [DayWindow('08:00', '10:00')],
        slotMinutes: 60,
        busy: const [],
        now: early,
      );
      expect(slots, hasLength(2));
      expect(slots.first.start.hour, 8);
      expect(slots.last.end.hour, 10);
      expect(slots.every((s) => s.status == 'available'), isTrue);
    });

    test('no slot spans a break (two windows)', () {
      final slots = generateSlots(
        day: day,
        windows: const [
          DayWindow('12:00', '13:00'),
          DayWindow('14:00', '16:00'),
        ],
        slotMinutes: 60,
        busy: const [],
        now: early,
      );
      expect(
        slots.map((s) => s.start.hour).toList(),
        [12, 14, 15],
      );
    });

    test('buffer padding blocks neighbouring slots on both sides', () {
      final busy = [
        BusySlot(
          start: DateTime(2026, 6, 15, 10),
          end: DateTime(2026, 6, 15, 11),
          kind: 'booked',
        ),
      ];
      final slots = generateSlots(
        day: day,
        windows: const [DayWindow('08:00', '14:00')],
        slotMinutes: 60,
        busy: busy,
        bufferMinutes: 15,
        now: early,
      );
      final byHour = {for (final s in slots) s.start.hour: s.status};
      expect(byHour[8], 'available');
      expect(byHour[9], 'booked'); // 09:00–10:00 collides with 09:45 pad
      expect(byHour[10], 'booked');
      expect(byHour[11], 'booked'); // 11:00–12:00 collides with 11:15 pad
      expect(byHour[12], 'available');
    });

    test('maintenance blocks are not padded and win over bookings', () {
      final busy = [
        BusySlot(
          start: DateTime(2026, 6, 15, 10),
          end: DateTime(2026, 6, 15, 11),
          kind: 'maintenance',
        ),
      ];
      final slots = generateSlots(
        day: day,
        windows: const [DayWindow('09:00', '12:00')],
        slotMinutes: 60,
        busy: busy,
        bufferMinutes: 30,
        now: early,
      );
      final byHour = {for (final s in slots) s.start.hour: s.status};
      expect(byHour[9], 'available'); // no pad on maintenance
      expect(byHour[10], 'maintenance');
      expect(byHour[11], 'available');
    });

    test('past slots are marked past', () {
      final slots = generateSlots(
        day: day,
        windows: const [DayWindow('08:00', '10:00')],
        slotMinutes: 60,
        busy: const [],
        now: DateTime(2026, 6, 15, 9),
      );
      expect(slots.first.status, 'past');
      expect(slots.last.status, 'available');
    });
  });

  group('validateCustomRange', () {
    const windows = [DayWindow('08:00', '13:00'), DayWindow('14:00', '22:00')];

    String? validate(
      DateTime start,
      DateTime end, {
      List<BusySlot> busy = const [],
      int minMinutes = 60,
      int buffer = 0,
    }) =>
        validateCustomRange(
          start: start,
          end: end,
          windows: windows,
          busy: busy,
          minBookingMinutes: minMinutes,
          bufferMinutes: buffer,
          now: early,
        );

    test('valid range inside a window passes', () {
      expect(
        validate(DateTime(2026, 6, 15, 9), DateTime(2026, 6, 15, 11)),
        isNull,
      );
    });

    test('shorter than the minimum is rejected', () {
      expect(
        validate(
          DateTime(2026, 6, 15, 9),
          DateTime(2026, 6, 15, 9, 30),
        ),
        contains('Minimum'),
      );
    });

    test('a range spanning the break is rejected', () {
      expect(
        validate(DateTime(2026, 6, 15, 12), DateTime(2026, 6, 15, 15)),
        contains('Outside trading hours'),
      );
    });

    test('overlap with a buffered booking is rejected', () {
      final busy = [
        BusySlot(
          start: DateTime(2026, 6, 15, 10),
          end: DateTime(2026, 6, 15, 11),
          kind: 'booked',
        ),
      ];
      expect(
        validate(
          DateTime(2026, 6, 15, 11),
          DateTime(2026, 6, 15, 12),
          busy: busy,
          buffer: 15,
        ),
        contains('overlaps'),
      );
      expect(
        validate(
          DateTime(2026, 6, 15, 11, 30),
          DateTime(2026, 6, 15, 12, 30),
          busy: busy,
          buffer: 15,
        ),
        isNull,
      );
    });

    test('a range in the past is rejected', () {
      expect(
        validateCustomRange(
          start: DateTime(2026, 6, 15, 9),
          end: DateTime(2026, 6, 15, 11),
          windows: windows,
          busy: const [],
          minBookingMinutes: 60,
          now: DateTime(2026, 6, 15, 10),
        ),
        contains('past'),
      );
    });
  });
}
