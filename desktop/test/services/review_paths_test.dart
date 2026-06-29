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
}
