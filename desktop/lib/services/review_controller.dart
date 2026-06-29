import 'package:flutter/foundation.dart';

/// Lifecycle phase of a single review (weekly/monthly).
enum ReviewPhase { idle, generating, done, error }

/// Immutable snapshot of one review's state.
@immutable
class ReviewEntry {
  const ReviewEntry(this.phase, {this.content, this.error});
  const ReviewEntry.idle()
      : phase = ReviewPhase.idle,
        content = null,
        error = null;

  final ReviewPhase phase;
  final String? content;
  final String? error;
}

/// Owns AI review generation state OUTSIDE the view so it survives the weekly
/// panel being closed or another note being opened — the generation keeps
/// running in the background and its result is here when the view returns.
///
/// Held by a long-lived owner (the document screen state). Views subscribe and
/// render [weekly]; the Generate action calls [generateWeekly].
class ReviewController extends ChangeNotifier {
  final Map<String, ReviewEntry> _weekly = {};

  static String _weekKey(DateTime weekStart) {
    final d = DateTime(weekStart.year, weekStart.month, weekStart.day);
    return 'w:${d.year}-${d.month}-${d.day}';
  }

  /// Current state for the week beginning [weekStart] (idle if untouched).
  ReviewEntry weekly(DateTime weekStart) =>
      _weekly[_weekKey(weekStart)] ?? const ReviewEntry.idle();

  /// Generates the weekly review in the background. [generate] produces the text
  /// (e.g. Claude Code); [persist] saves it. No-op if a generation for this week
  /// is already in flight. Survives view rebuilds/unmounts.
  Future<void> generateWeekly(
    DateTime weekStart, {
    required Future<String> Function() generate,
    required Future<void> Function(String content) persist,
  }) async {
    final key = _weekKey(weekStart);
    if (_weekly[key]?.phase == ReviewPhase.generating) return;
    _weekly[key] = const ReviewEntry(ReviewPhase.generating);
    notifyListeners();

    final String text;
    try {
      text = await generate();
    } catch (e) {
      _weekly[key] = ReviewEntry(ReviewPhase.error, error: e.toString());
      notifyListeners();
      return;
    }

    _weekly[key] = ReviewEntry(ReviewPhase.done, content: text);
    notifyListeners();

    // Persist is best-effort: a save failure must not discard a generated
    // review — it stays visible and can be regenerated / re-saved later.
    try {
      await persist(text);
    } catch (_) {
      // Swallow: the generated result remains shown.
    }
  }

  /// Seeds a previously-saved review for [weekStart] (or resets to idle when
  /// [content] is null), without disturbing an in-flight generation.
  void setLoadedWeekly(DateTime weekStart, String? content) {
    final key = _weekKey(weekStart);
    final phase = _weekly[key]?.phase;
    // Never disturb an in-flight generation.
    if (phase == ReviewPhase.generating) return;
    // Don't clobber an already-shown result with an empty load — e.g. a freshly
    // generated review whose save hasn't propagated to the read source yet.
    if (content == null && phase == ReviewPhase.done) return;
    _weekly[key] = content == null
        ? const ReviewEntry.idle()
        : ReviewEntry(ReviewPhase.done, content: content);
    notifyListeners();
  }

  // ── Monthly ──

  final Map<String, ReviewEntry> _monthly = {};

  static String _monthKey(DateTime month) => 'm:${month.year}-${month.month}';

  /// Current monthly state for [month] (idle if untouched).
  ReviewEntry monthly(DateTime month) =>
      _monthly[_monthKey(month)] ?? const ReviewEntry.idle();

  /// Generates the monthly review in the background.
  ///
  /// For each week in [weekStarts], in parallel, it reuses a saved weekly review
  /// ([loadWeekly]) or generates one ([generateWeekly]); the per-week reviews are
  /// then combined by [synthesize] and saved via [persist]. A week that yields
  /// nothing (no notes → [generateWeekly] throws) is skipped. No-op if a monthly
  /// generation is already in flight; survives view rebuilds/unmounts.
  Future<void> generateMonthly(
    DateTime month, {
    required List<DateTime> weekStarts,
    required Future<String?> Function(DateTime weekStart) loadWeekly,
    required Future<String> Function(DateTime weekStart) generateWeekly,
    required Future<String> Function(List<String> weeklyReviews) synthesize,
    required Future<void> Function(String content) persist,
  }) async {
    final key = _monthKey(month);
    if (_monthly[key]?.phase == ReviewPhase.generating) return;
    _monthly[key] = const ReviewEntry(ReviewPhase.generating);
    notifyListeners();

    final String text;
    try {
      // Per week, in parallel: prefer the saved weekly review, else generate
      // one. A week with no notes contributes an empty string and is dropped.
      final perWeek = await Future.wait(weekStarts.map((w) async {
        final existing = await loadWeekly(w);
        if (existing != null && existing.trim().isNotEmpty) return existing;
        try {
          return await generateWeekly(w);
        } catch (_) {
          return '';
        }
      }));
      final reviews = perWeek.where((r) => r.trim().isNotEmpty).toList();
      if (reviews.isEmpty) {
        throw Exception('이번 달에 요약할 노트가 없습니다.');
      }
      text = await synthesize(reviews);
    } catch (e) {
      _monthly[key] = ReviewEntry(ReviewPhase.error, error: e.toString());
      notifyListeners();
      return;
    }

    _monthly[key] = ReviewEntry(ReviewPhase.done, content: text);
    notifyListeners();
    try {
      await persist(text);
    } catch (_) {
      // Swallow: the generated result remains shown.
    }
  }

  /// Seeds a previously-saved monthly review for [month] (or resets to idle when
  /// [content] is null), without disturbing an in-flight generation or clobbering
  /// an already-shown result with an empty load.
  void setLoadedMonthly(DateTime month, String? content) {
    final key = _monthKey(month);
    final phase = _monthly[key]?.phase;
    if (phase == ReviewPhase.generating) return;
    if (content == null && phase == ReviewPhase.done) return;
    _monthly[key] = content == null
        ? const ReviewEntry.idle()
        : ReviewEntry(ReviewPhase.done, content: content);
    notifyListeners();
  }
}
