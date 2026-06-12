import 'package:venue_vibe/src/models/resource.dart';

/// One row per weekday (ISO: 1 = Monday … 7 = Sunday, matching
/// [DateTime.weekday]). A day is either closed, or open between
/// [openTime]–[closeTime] with an optional break window that splits the day
/// into two bookable windows.
class ResourceHours {
  const ResourceHours({
    required this.resourceId,
    required this.weekday,
    this.id = '',
    this.isClosed = false,
    this.openTime = '07:00',
    this.closeTime = '23:00',
    this.breakStart,
    this.breakEnd,
  });

  factory ResourceHours.fromJson(Map<String, dynamic> json) {
    return ResourceHours(
      id: json['id'] as String? ?? '',
      resourceId: json['resource_id'] as String,
      weekday: json['weekday'] as int,
      isClosed: json['is_closed'] as bool? ?? false,
      openTime: _normalize(json['open_time'] as String?, '07:00'),
      closeTime: _normalize(json['close_time'] as String?, '23:00'),
      breakStart: _normalizeOrNull(json['break_start'] as String?),
      breakEnd: _normalizeOrNull(json['break_end'] as String?),
    );
  }
  final String id;
  final String resourceId;
  final int weekday; // ISO 1=Mon … 7=Sun
  final bool isClosed;
  final String openTime; // 'HH:MM' local wall-clock
  final String closeTime; // 'HH:MM'
  final String? breakStart; // 'HH:MM' or null (no break)
  final String? breakEnd;

  bool get hasBreak => breakStart != null && breakEnd != null;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        'weekday': weekday,
        'is_closed': isClosed,
        'open_time': openTime,
        'close_time': closeTime,
        'break_start': breakStart,
        'break_end': breakEnd,
      };

  ResourceHours copyWith({
    bool? isClosed,
    String? openTime,
    String? closeTime,
    String? breakStart,
    String? breakEnd,
    bool clearBreak = false,
  }) =>
      ResourceHours(
        id: id,
        resourceId: resourceId,
        weekday: weekday,
        isClosed: isClosed ?? this.isClosed,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        breakStart: clearBreak ? null : (breakStart ?? this.breakStart),
        breakEnd: clearBreak ? null : (breakEnd ?? this.breakEnd),
      );

  static String _normalize(String? raw, String fallback) =>
      (raw == null || raw.length < 5) ? fallback : raw.substring(0, 5);

  static String? _normalizeOrNull(String? raw) =>
      (raw == null || raw.length < 5) ? null : raw.substring(0, 5);

  static const weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  String get weekdayName => weekdayNames[weekday - 1];
}

/// A bookable window within a single day, in 'HH:MM' wall-clock strings.
class DayWindow {
  const DayWindow(this.open, this.close);
  final String open;
  final String close;
}

/// Resolves the bookable windows for [weekday] (ISO 1–7): the day's
/// [ResourceHours] row minus its break (0, 1 or 2 windows), falling back to
/// the resource's legacy single open/close window when no row exists.
List<DayWindow> windowsForWeekday(
  List<ResourceHours> hours,
  int weekday,
  Resource resource,
) {
  ResourceHours? day;
  for (final h in hours) {
    if (h.weekday == weekday) {
      day = h;
      break;
    }
  }
  if (day == null) {
    return [DayWindow(resource.openTime, resource.closeTime)];
  }
  if (day.isClosed) return const [];
  if (!day.hasBreak) return [DayWindow(day.openTime, day.closeTime)];
  return [
    if (day.breakStart! != day.openTime)
      DayWindow(day.openTime, day.breakStart!),
    if (day.breakEnd! != day.closeTime) DayWindow(day.breakEnd!, day.closeTime),
  ];
}
