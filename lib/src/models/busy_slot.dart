/// A busy time range for a resource, returned by the `get_busy_slots` RPC.
/// Combines confirmed/pending bookings and maintenance blocks into one shape
/// with no booking PII, so availability works under RLS.
class BusySlot {
  const BusySlot({
    required this.start,
    required this.end,
    required this.kind,
  });

  factory BusySlot.fromJson(Map<String, dynamic> json) {
    return BusySlot(
      start: DateTime.parse(json['start_time'] as String).toLocal(),
      end: DateTime.parse(json['end_time'] as String).toLocal(),
      kind: json['kind'] as String? ?? 'booked',
    );
  }

  final DateTime start;
  final DateTime end;

  /// One of: 'booked', 'pending', 'maintenance'.
  final String kind;
}
