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
