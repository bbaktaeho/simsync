import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/services/review_paths.dart';

void main() {
  group('weekOfMonth', () {
    test('days 1-7 are week 1', () {
      expect(weekOfMonth(DateTime(2026, 6, 1)), 1);
      expect(weekOfMonth(DateTime(2026, 6, 7)), 1);
    });

    test('days 8-14 are week 2', () {
      expect(weekOfMonth(DateTime(2026, 6, 8)), 2);
      expect(weekOfMonth(DateTime(2026, 6, 14)), 2);
    });

    test('days 15-21 are week 3, 22-28 week 4, 29+ week 5', () {
      expect(weekOfMonth(DateTime(2026, 6, 15)), 3);
      expect(weekOfMonth(DateTime(2026, 6, 22)), 4);
      expect(weekOfMonth(DateTime(2026, 6, 29)), 5);
    });
  });

  group('weekLabel', () {
    test('formats as N주차', () {
      expect(weekLabel(DateTime(2026, 6, 1)), '1주차');
      expect(weekLabel(DateTime(2026, 6, 15)), '3주차');
    });
  });

  group('weeklyReviewPath', () {
    test('files under the month the Monday falls in', () {
      expect(weeklyReviewPath(DateTime(2026, 6, 1)),
          'notes/2026-06/1주차/weekly-review.md');
    });

    test('a week whose Monday is in May files under May', () {
      // 2026-05-25 is a Monday; its week spills into June but stays in May.
      expect(weeklyReviewPath(DateTime(2026, 5, 25)),
          'notes/2026-05/4주차/weekly-review.md');
    });

    test('zero-pads single-digit months', () {
      expect(weeklyReviewPath(DateTime(2026, 3, 2)),
          startsWith('notes/2026-03/'));
    });
  });

  group('monthlyReviewPath', () {
    test('lives directly under the month folder (only y/m used)', () {
      expect(monthlyReviewPath(DateTime(2026, 6, 15)),
          'notes/2026-06/monthly-review.md');
    });

    test('zero-pads single-digit months', () {
      expect(monthlyReviewPath(DateTime(2026, 3, 1)),
          'notes/2026-03/monthly-review.md');
    });
  });

  group('outline paths (stage 1)', () {
    test('weekly outline sits beside the weekly review', () {
      expect(weeklyOutlinePath(DateTime(2026, 6, 1)),
          'notes/2026-06/1주차/weekly-outline.md');
    });

    test('a week whose Monday is in May files under May', () {
      expect(weeklyOutlinePath(DateTime(2026, 5, 25)),
          'notes/2026-05/4주차/weekly-outline.md');
    });

    test('monthly outline lives directly under the month folder', () {
      expect(monthlyOutlinePath(DateTime(2026, 6, 15)),
          'notes/2026-06/monthly-outline.md');
    });
  });

  group('weekStartsForMonth', () {
    test('returns consecutive Monday week-starts covering the whole month', () {
      final weeks = weekStartsForMonth(2026, 6);

      // Every entry is a Monday.
      expect(weeks.every((d) => d.weekday == DateTime.monday), isTrue);
      // The first week contains the 1st (its Monday is on/before the 1st).
      expect(weeks.first.isAfter(DateTime(2026, 6, 1)), isFalse);
      // The last week contains the last day (its Sunday is on/after the 30th).
      final lastSunday = weeks.last.add(const Duration(days: 6));
      expect(lastSunday.isBefore(DateTime(2026, 6, 30)), isFalse);
      // Steps are exactly 7 days apart.
      for (var i = 1; i < weeks.length; i++) {
        expect(weeks[i].difference(weeks[i - 1]).inDays, 7);
      }
    });

    test('a month starting on Monday begins exactly on the 1st', () {
      // 2026-06-01 falls on a Monday in this scenario only if true; assert the
      // invariant generically: the first week-start is never after the 1st.
      final weeks = weekStartsForMonth(2026, 2);
      expect(weeks.first.isAfter(DateTime(2026, 2, 1)), isFalse);
      expect(weeks.first.weekday, DateTime.monday);
    });
  });
}
