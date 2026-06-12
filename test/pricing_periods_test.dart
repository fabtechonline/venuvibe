import 'package:flutter_test/flutter_test.dart';
import 'package:venue_vibe/src/models/pricing_period.dart';
import 'package:venue_vibe/src/utils/pricing_periods.dart';

PricingPeriod period(
  String name,
  String start,
  String end, {
  bool isActive = true,
  double? hourlyRate,
}) =>
    PricingPeriod(
      id: name,
      resourceId: 'r1',
      name: name,
      startDate: DateTime.parse(start),
      endDate: DateTime.parse(end),
      hourlyRate: hourlyRate,
      isActive: isActive,
    );

void main() {
  group('findCoveringPeriod', () {
    final summer = period('Summer', '2026-06-01', '2026-08-31');
    final winter = period('Winter', '2026-09-01', '2026-11-30');

    test('day inside a period', () {
      expect(
        findCoveringPeriod([summer, winter], DateTime(2026, 7, 15)),
        summer,
      );
    });

    test('start and end boundaries are inclusive', () {
      expect(findCoveringPeriod([summer], DateTime(2026, 6)), summer);
      expect(findCoveringPeriod([summer], DateTime(2026, 8, 31)), summer);
    });

    test('time-of-day is ignored', () {
      expect(
        findCoveringPeriod([summer], DateTime(2026, 8, 31, 23, 59)),
        summer,
      );
    });

    test('uncovered day returns null', () {
      expect(findCoveringPeriod([summer], DateTime(2026, 12)), isNull);
    });

    test('inactive periods are ignored', () {
      final inactive = period(
        'Old',
        '2026-06-01',
        '2026-08-31',
        isActive: false,
      );
      expect(findCoveringPeriod([inactive], DateTime(2026, 7)), isNull);
    });

    test('empty list returns null', () {
      expect(findCoveringPeriod([], DateTime(2026, 7)), isNull);
    });
  });

  group('computeGaps', () {
    test('adjacent periods leave no gap', () {
      final gaps = computeGaps([
        period('A', '2026-01-01', '2026-03-31'),
        period('B', '2026-04-01', '2026-06-30'),
      ]);
      expect(gaps, isEmpty);
    });

    test('single period has no gaps', () {
      expect(computeGaps([period('A', '2026-01-01', '2026-03-31')]), isEmpty);
    });

    test('one-day gap is reported', () {
      final gaps = computeGaps([
        period('A', '2026-01-01', '2026-03-30'),
        period('B', '2026-04-01', '2026-06-30'),
      ]);
      expect(gaps, hasLength(1));
      expect(gaps.single.start, DateTime(2026, 3, 31));
      expect(gaps.single.end, DateTime(2026, 3, 31));
    });

    test('multiple gaps, unsorted input', () {
      final gaps = computeGaps([
        period('C', '2026-09-15', '2026-12-31'),
        period('A', '2026-01-01', '2026-03-31'),
        period('B', '2026-05-01', '2026-08-31'),
      ]);
      expect(gaps, hasLength(2));
      expect(gaps.first.start, DateTime(2026, 4));
      expect(gaps.first.end, DateTime(2026, 4, 30));
      expect(gaps.last.start, DateTime(2026, 9));
      expect(gaps.last.end, DateTime(2026, 9, 14));
    });

    test('inactive periods do not bridge a gap', () {
      final gaps = computeGaps([
        period('A', '2026-01-01', '2026-03-31'),
        period('Off', '2026-04-01', '2026-04-30', isActive: false),
        period('B', '2026-05-01', '2026-06-30'),
      ]);
      expect(gaps, hasLength(1));
      expect(gaps.single.start, DateTime(2026, 4));
      expect(gaps.single.end, DateTime(2026, 4, 30));
    });
  });

  group('overlap detection', () {
    test('disjoint ranges do not overlap', () {
      expect(
        periodsOverlap(
          period('A', '2026-01-01', '2026-03-31'),
          period('B', '2026-04-01', '2026-06-30'),
        ),
        isFalse,
      );
    });

    test('shared boundary day overlaps (inclusive bounds)', () {
      expect(
        periodsOverlap(
          period('A', '2026-01-01', '2026-03-31'),
          period('B', '2026-03-31', '2026-06-30'),
        ),
        isTrue,
      );
    });

    test('identical ranges overlap', () {
      final a = period('A', '2026-01-01', '2026-03-31');
      expect(periodsOverlap(a, a), isTrue);
    });

    test('findOverlapConflicts reports each clash and skips inactive', () {
      final existing = [
        period('Standard', '2026-01-01', '2026-06-30'),
        period('Old', '2026-07-01', '2026-12-31', isActive: false),
      ];
      final candidates = [
        period('Summer', '2026-06-01', '2026-08-31'),
        period('Spring 2027', '2027-03-01', '2027-05-31'),
      ];
      final conflicts = findOverlapConflicts(existing, candidates);
      expect(conflicts, hasLength(1));
      expect(conflicts.single, contains('Summer'));
      expect(conflicts.single, contains('Standard'));
    });

    test('candidate spanning two existing periods reports both', () {
      final existing = [
        period('A', '2026-01-01', '2026-03-31'),
        period('B', '2026-04-01', '2026-06-30'),
      ];
      final conflicts = findOverlapConflicts(
        existing,
        [period('Wide', '2026-03-01', '2026-05-01')],
      );
      expect(conflicts, hasLength(2));
    });
  });

  group('PricingPeriod JSON', () {
    test('fromJson/toJson roundtrip', () {
      final p = PricingPeriod.fromJson(const {
        'id': 'p1',
        'resource_id': 'r1',
        'name': 'Summer',
        'start_date': '2026-06-01',
        'end_date': '2026-08-31',
        'hourly_rate': 350,
        'is_active': true,
        'created_at': '2026-06-12T08:00:00Z',
      });
      expect(p.hourlyRate, 350);
      final json = p.toJson();
      expect(json['start_date'], '2026-06-01');
      expect(json['end_date'], '2026-08-31');
      expect(json.containsKey('id'), isFalse);
    });

    test('null hourly_rate survives', () {
      final p = PricingPeriod.fromJson(const {
        'id': 'p1',
        'resource_id': 'r1',
        'name': 'Standard',
        'start_date': '2026-06-01',
        'end_date': '2026-08-31',
        'hourly_rate': null,
      });
      expect(p.hourlyRate, isNull);
      expect(p.isActive, isTrue);
      expect(p.toJson()['hourly_rate'], isNull);
    });

    test('copyWith clearHourlyRate', () {
      final p = period('A', '2026-01-01', '2026-03-31', hourlyRate: 100);
      expect(p.copyWith(hourlyRate: 200).hourlyRate, 200);
      expect(p.copyWith().hourlyRate, 100);
      expect(p.copyWith(clearHourlyRate: true).hourlyRate, isNull);
    });
  });
}
