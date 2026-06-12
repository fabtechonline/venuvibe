import 'package:venue_vibe/src/models/pricing_period.dart';

/// A run of days with no pricing period covering them (both ends inclusive).
class PricingGap {
  const PricingGap(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// Truncates [d] to a date-only value for inclusive day comparisons.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The active period whose inclusive start–end date range covers [day],
/// or null when the date has no pricing (booking must be blocked).
PricingPeriod? findCoveringPeriod(List<PricingPeriod> periods, DateTime day) {
  final d = dateOnly(day);
  for (final p in periods) {
    if (!p.isActive) continue;
    if (!d.isBefore(dateOnly(p.startDate)) && !d.isAfter(dateOnly(p.endDate))) {
      return p;
    }
  }
  return null;
}

/// Missing-day ranges strictly BETWEEN consecutive active periods (adjacent
/// periods — next starts the day after the previous ends — leave no gap).
/// Days before the first or after the last period are not reported.
List<PricingGap> computeGaps(List<PricingPeriod> periods) {
  final active = periods.where((p) => p.isActive).toList()
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  final gaps = <PricingGap>[];
  for (var i = 1; i < active.length; i++) {
    final prevEnd = dateOnly(active[i - 1].endDate);
    final nextStart = dateOnly(active[i].startDate);
    final gapStart = prevEnd.add(const Duration(days: 1));
    if (nextStart.isAfter(gapStart)) {
      gaps.add(
        PricingGap(gapStart, nextStart.subtract(const Duration(days: 1))),
      );
    }
  }
  return gaps;
}

/// Inclusive date-range intersection — mirrors the DB's
/// `daterange(start, end, '[]') &&` exclusion check.
bool periodsOverlap(PricingPeriod a, PricingPeriod b) =>
    !dateOnly(a.startDate).isAfter(dateOnly(b.endDate)) &&
    !dateOnly(b.startDate).isAfter(dateOnly(a.endDate));

String _fmtDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Human-readable conflicts between [candidates] and the [existing] active
/// periods (used by the season dialog and the copy preflight). When editing a
/// period, the caller excludes it from [existing] first.
List<String> findOverlapConflicts(
  List<PricingPeriod> existing,
  List<PricingPeriod> candidates,
) {
  final conflicts = <String>[];
  for (final c in candidates) {
    if (!c.isActive) continue;
    for (final e in existing) {
      if (!e.isActive) continue;
      if (periodsOverlap(c, e)) {
        conflicts.add(
          '"${c.name}" (${_fmtDay(c.startDate)} – ${_fmtDay(c.endDate)}) '
          'overlaps "${e.name}" '
          '(${_fmtDay(e.startDate)} – ${_fmtDay(e.endDate)})',
        );
      }
    }
  }
  return conflicts;
}
