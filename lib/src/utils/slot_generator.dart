import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';

/// A generated bookable slot with its availability status:
/// 'available' | 'booked' | 'pending' | 'maintenance' | 'past'.
class GeneratedSlot {
  const GeneratedSlot(this.start, this.end, this.status);
  final DateTime start;
  final DateTime end;
  final String status;
}

DateTime _at(DateTime day, String hhmm) {
  final parts = hhmm.split(':');
  return DateTime(
    day.year,
    day.month,
    day.day,
    int.tryParse(parts.first) ?? 0,
    parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

/// Walks each bookable [windows] of [day] in [slotMinutes] steps and marks
/// each slot's status against [busy] ranges padded by [bufferMinutes] on both
/// sides (turnaround time before AND after every existing booking/block).
List<GeneratedSlot> generateSlots({
  required DateTime day,
  required List<DayWindow> windows,
  required int slotMinutes,
  required List<BusySlot> busy,
  int bufferMinutes = 0,
  DateTime? now,
}) {
  final slots = <GeneratedSlot>[];
  final clock = now ?? DateTime.now();
  for (final w in windows) {
    var current = _at(day, w.open);
    final windowEnd = _at(day, w.close);
    while (!current.add(Duration(minutes: slotMinutes)).isAfter(windowEnd)) {
      final end = current.add(Duration(minutes: slotMinutes));
      final overlap = _busyStatus(current, end, busy, bufferMinutes);
      final isPast = current.isBefore(clock);
      slots.add(
        GeneratedSlot(current, end, isPast ? 'past' : overlap ?? 'available'),
      );
      current = end;
    }
  }
  return slots;
}

/// 'maintenance' wins over 'pending'/'booked'; null means free.
/// Buffer padding applies to bookings, not maintenance blocks (a block is an
/// explicit range chosen by the tenant).
String? _busyStatus(
  DateTime start,
  DateTime end,
  List<BusySlot> busy,
  int bufferMinutes,
) {
  String? status;
  for (final b in busy) {
    final pad = b.kind == 'maintenance'
        ? Duration.zero
        : Duration(minutes: bufferMinutes);
    if (start.isBefore(b.end.add(pad)) && end.isAfter(b.start.subtract(pad))) {
      if (b.kind == 'maintenance') return 'maintenance';
      status = b.kind;
    }
  }
  return status;
}

/// Validates a customer-chosen custom range ([start]–[end]):
/// returns null when valid, or a human-readable problem description.
String? validateCustomRange({
  required DateTime start,
  required DateTime end,
  required List<DayWindow> windows,
  required List<BusySlot> busy,
  required int minBookingMinutes,
  int bufferMinutes = 0,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  if (!end.isAfter(start)) return 'End time must be after start time';
  if (start.isBefore(clock)) return 'Start time is in the past';
  final minutes = end.difference(start).inMinutes;
  if (minutes < minBookingMinutes) {
    return 'Minimum booking is $minBookingMinutes minutes';
  }
  if (windows.isEmpty) return 'The venue is closed on this day';
  final insideAWindow = windows.any((w) {
    final wStart = _at(start, w.open);
    final wEnd = _at(start, w.close);
    return !start.isBefore(wStart) && !end.isAfter(wEnd);
  });
  if (!insideAWindow) {
    return 'Outside trading hours (or spans a break)';
  }
  if (_busyStatus(start, end, busy, bufferMinutes) != null) {
    return 'That time overlaps an existing booking';
  }
  return null;
}
