import 'package:flutter/foundation.dart';

/// Lifecycle phase of one stage of a review.
enum ReviewPhase { idle, generating, done, error }

/// Immutable state of a single stage (outline or review).
@immutable
class StageState {
  const StageState(this.phase, {this.content, this.error});
  const StageState.idle()
      : phase = ReviewPhase.idle,
        content = null,
        error = null;

  final ReviewPhase phase;
  final String? content;
  final String? error;
}

/// Immutable snapshot of one period's two-stage review.
///
/// Stage 1 ([outline]) is a checkbox list of the period's key items, produced by
/// the fixed system instruction; the user checks the items to keep. Stage 2
/// ([review]) is the final write-up generated from the checked items by the
/// user-editable instruction. Each stage can be (re)generated independently.
@immutable
class ReviewEntry {
  const ReviewEntry({required this.outline, required this.review});
  const ReviewEntry.idle()
      : outline = const StageState.idle(),
        review = const StageState.idle();

  final StageState outline;
  final StageState review;

  ReviewEntry copyWith({StageState? outline, StageState? review}) => ReviewEntry(
        outline: outline ?? this.outline,
        review: review ?? this.review,
      );
}

/// Owns two-stage AI review state OUTSIDE the view so generation survives the
/// panel being closed or another note opened — it keeps running in the
/// background and its result is here when the view returns.
///
/// Held by a long-lived owner (the document screen state). Views subscribe and
/// render [weekly]/[monthly]; the Generate actions call the generate* methods.
class ReviewController extends ChangeNotifier {
  final Map<String, ReviewEntry> _weekly = {};
  final Map<String, ReviewEntry> _monthly = {};

  static String _weekKey(DateTime weekStart) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return 'w:${d.year}-${d.month}-${d.day}';
  }

  static String _monthKey(DateTime month) => 'm:${month.year}-${month.month}';

  /// Current two-stage state for the week beginning [weekStart] (idle if untouched).
  ReviewEntry weekly(DateTime weekStart) =>
      _weekly[_weekKey(weekStart)] ?? const ReviewEntry.idle();

  /// Current two-stage state for [month] (idle if untouched).
  ReviewEntry monthly(DateTime month) =>
      _monthly[_monthKey(month)] ?? const ReviewEntry.idle();

  // ── Generation (background, survives view rebuilds/unmounts) ──

  /// Generates one stage ([outline] true = stage 1, false = stage 2) in the
  /// background. [generate] produces the text; [persist] saves it. No-op if that
  /// stage is already in flight. A save failure never discards a generated
  /// result — it stays shown and can be re-saved later.
  Future<void> _generateStage(
    Map<String, ReviewEntry> store,
    String key, {
    required bool outline,
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) async {
    StageState stageOf(ReviewEntry e) => outline ? e.outline : e.review;
    ReviewEntry withStage(ReviewEntry e, StageState s) =>
        outline ? e.copyWith(outline: s) : e.copyWith(review: s);

    final cur = store[key] ?? const ReviewEntry.idle();
    if (stageOf(cur).phase == ReviewPhase.generating) return;
    store[key] = withStage(cur, const StageState(ReviewPhase.generating));
    notifyListeners();

    final String text;
    try {
      text = await generate();
    } catch (e) {
      final c = store[key] ?? const ReviewEntry.idle();
      store[key] =
          withStage(c, StageState(ReviewPhase.error, error: e.toString()));
      notifyListeners();
      return;
    }

    final c = store[key] ?? const ReviewEntry.idle();
    store[key] = withStage(c, StageState(ReviewPhase.done, content: text));
    notifyListeners();

    try {
      await persist(text);
    } catch (_) {
      // Swallow: the generated result remains shown.
    }
  }

  /// Stage 1 (outline) for the week beginning [weekStart].
  Future<void> generateWeeklyOutline(
    DateTime weekStart, {
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) =>
      _generateStage(_weekly, _weekKey(weekStart),
          outline: true, generate: generate, persist: persist);

  /// Stage 2 (review) for the week beginning [weekStart].
  Future<void> generateWeeklyReview(
    DateTime weekStart, {
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) =>
      _generateStage(_weekly, _weekKey(weekStart),
          outline: false, generate: generate, persist: persist);

  /// Stage 1 (outline) for [month].
  Future<void> generateMonthlyOutline(
    DateTime month, {
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) =>
      _generateStage(_monthly, _monthKey(month),
          outline: true, generate: generate, persist: persist);

  /// Stage 2 (review) for [month].
  Future<void> generateMonthlyReview(
    DateTime month, {
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) =>
      _generateStage(_monthly, _monthKey(month),
          outline: false, generate: generate, persist: persist);

  // ── Outline edits (checkbox toggles) ──

  /// Replaces the outline content in place (e.g. after a checkbox toggle). The
  /// caller persists the new content. No-op while the outline is generating.
  void _setOutlineContent(
      Map<String, ReviewEntry> store, String key, String content) {
    final cur = store[key] ?? const ReviewEntry.idle();
    if (cur.outline.phase == ReviewPhase.generating) return;
    store[key] =
        cur.copyWith(outline: StageState(ReviewPhase.done, content: content));
    notifyListeners();
  }

  void setWeeklyOutlineContent(DateTime weekStart, String content) =>
      _setOutlineContent(_weekly, _weekKey(weekStart), content);

  void setMonthlyOutlineContent(DateTime month, String content) =>
      _setOutlineContent(_monthly, _monthKey(month), content);

  // ── Seeding saved results ──

  /// Seeds a previously-saved stage result (or resets to idle when [content] is
  /// null), without disturbing an in-flight generation or clobbering an
  /// already-shown result with an empty load.
  void _setLoaded(
    Map<String, ReviewEntry> store,
    String key, {
    required bool outline,
    required String? content,
  }) {
    StageState stageOf(ReviewEntry e) => outline ? e.outline : e.review;
    ReviewEntry withStage(ReviewEntry e, StageState s) =>
        outline ? e.copyWith(outline: s) : e.copyWith(review: s);

    final cur = store[key] ?? const ReviewEntry.idle();
    if (stageOf(cur).phase == ReviewPhase.generating) return;
    if (content == null && stageOf(cur).phase == ReviewPhase.done) return;
    store[key] = withStage(
        cur,
        content == null
            ? const StageState.idle()
            : StageState(ReviewPhase.done, content: content));
    notifyListeners();
  }

  void setLoadedWeeklyOutline(DateTime weekStart, String? content) =>
      _setLoaded(_weekly, _weekKey(weekStart), outline: true, content: content);
  void setLoadedWeeklyReview(DateTime weekStart, String? content) =>
      _setLoaded(_weekly, _weekKey(weekStart), outline: false, content: content);
  void setLoadedMonthlyOutline(DateTime month, String? content) =>
      _setLoaded(_monthly, _monthKey(month), outline: true, content: content);
  void setLoadedMonthlyReview(DateTime month, String? content) =>
      _setLoaded(_monthly, _monthKey(month), outline: false, content: content);
}
