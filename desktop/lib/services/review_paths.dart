/// Pure helpers for the on-disk / in-repo paths of AI review files.
///
/// Reviews live alongside notes under `notes/`, but in NON-day directories so
/// the note loader (which only recognizes numeric day folders) never mistakes
/// them for notes:
///   notes/{YYYY-MM}/{N}주차/weekly-review.md   (weekly)
///   notes/{YYYY-MM}/monthly-review.md          (monthly, Phase 3)
library;

String _ym(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// 1-based week ordinal within the month of [weekStart] (expected to be a
/// Monday). Days 1–7 → 1, 8–14 → 2, … A week is filed under the month its
/// Monday falls in, so callers pass the week's Monday.
int weekOfMonth(DateTime weekStart) => ((weekStart.day - 1) ~/ 7) + 1;

/// Directory label for the week beginning [weekStart], e.g. `3주차`.
String weekLabel(DateTime weekStart) => '${weekOfMonth(weekStart)}주차';

/// Repo/basePath-relative path of the weekly review for the week beginning
/// [weekStart] (Monday).
String weeklyReviewPath(DateTime weekStart) =>
    'notes/${_ym(weekStart)}/${weekLabel(weekStart)}/weekly-review.md';

/// Repo/basePath-relative path of the monthly review for [month]. Lives directly
/// under the month folder (a non-day, non-week location) so it stays out of the
/// note list. Only year+month are used.
String monthlyReviewPath(DateTime month) =>
    'notes/${_ym(month)}/monthly-review.md';

/// All Monday week-starts whose week overlaps [year]-[month] — from the Monday
/// of the 1st through the Monday of the last day. Splits a month into the weeks
/// a monthly review is built from (each week may already have a saved weekly
/// review, or is summarized on demand). Weeks at the month boundary are
/// included so no day of the month is dropped.
List<DateTime> weekStartsForMonth(int year, int month) {
  DateTime mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final firstWeek = mondayOf(DateTime(year, month, 1));
  final lastWeek = mondayOf(DateTime(year, month + 1, 0));
  final weeks = <DateTime>[];
  for (var w = firstWeek;
      !w.isAfter(lastWeek);
      w = w.add(const Duration(days: 7))) {
    weeks.add(w);
  }
  return weeks;
}
