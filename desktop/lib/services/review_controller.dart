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
}
